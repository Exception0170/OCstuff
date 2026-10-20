# Windows and drawing

TGL provides Frames and controls. LTDE adds a window manager (`ltwm`) and an app
API (`ltwapi`). Apps normally use ltwapi; the window manager is also available at
`require("tgl").sys.wm` for composition and lower-level operations.

## Managed windows

A managed window is a record containing `frame`, `pid`, `noTaskbar`, `minimized`
and an insertion index. The manager keeps:

- `windows`: records sorted by the Frame's `z_index`.
- `pidWindows[pid]`: ordinary windows belonging to a program.
- `activeWindow`: the record currently receiving keyboard focus.
- `locked`: prevents ordinary focus changes and dragging during modal dialogs.

`addWindow(frame,pid,noTaskbar)` cascades placement, assigns a z-index above the
other windows, and focuses ordinary app windows. `addWindowDirect` is used for
system UI without cascading. `addOverlay` registers a Frame at its existing
z-index without creating a taskbar entry or changing focus.

Focus changes raise a window and invoke its `onFocusChange(active)` callback.
Ltwapi uses that callback to change the title-bar color. Minimizing hides the
Frame and disables its controls; restoring enables them and focuses the window.
Closing disables controls, drains queued drawing, removes the record and redraws
the exposed area. It also calls the app's `onClose` callback.

Closing a window does not itself terminate its app thread. The callback should
wake the app's event loop so it can clean up and return.

## Coordinates

Positions are character cells, starting at 1. A `Pos2` contains `x,y`; a `Size2`
contains bounds and dimensions. A Frame's children are added using coordinates
relative to that Frame. Moving it translates its children into screen positions.
Do not keep reusing a control object across different Frames.

`ltwapi.addWindow(width,height,title,opts)` returns `frame,area`, or nil if the
window manager is unavailable. Width and height include the title bar. `area`
is the usable area in Frame-relative coordinates: it starts at row 2 normally,
or row 3 when a toolbar is present.

## Redrawing

Change the app's objects, then redraw through the manager:

```lua
message.text="Saved"
local wm=tgl.sys.wm
local window=wm:getManagedWindow(frame)
if window and not frame.hidden then
  wm:renderRegions({wm:getWindowBounds(window)})
end
```

`renderRegions` removes overlap between damaged rectangles, clips drawing to
those areas, paints the background, then renders intersecting visible windows
in z-order. TGL's buffered compositor prepares the result before copying it to
the display when GPU buffers are available. Covering windows are included, so
an update in a background app does not paint over them.

A move redraws both the old and new bounds. During a title-bar drag, a small
cursor follows the pointer; the window itself moves on drop. `renderAll` redraws
the desktop. Use it for an explicit refresh, rather than every content change.
The renderer also keeps z information for control hit checks and handles nested
Frame/ScrollFrame clipping.

## ltwapi reference

| Call | Effect |
| --- | --- |
| `addWindow(w,h,title,opts)` | Create, register and enable a titled Frame; return Frame and content area |
| `removeWindow(frame)` | Close the managed window; safe if it is already removed |
| `setTitle(frame,title)` | Change the title Text; request a redraw afterward |
| `minimize(frame)` | Hide and disable the window |
| `focus(frame)` | Bring the window forward; restore a minimized window through the manager first |
| `refresh()` | Redraw the whole desktop |
| `setToolbarEnabled(frame,bool)` | Enable/disable toolbar controls |
| `setMenuItems(frame,label,items)` | Replace a named toolbar menu's items |
| `getMenuItems(frame,label)` | Return that menu's live item table, or nil |
| `showMenu(pos,items,col,z?)` | Show a blocking popup below an absolute screen position; return the selected item or nil |
| `openFile(path)` | Resolve a file association and launch it with the path as its first argument; return program or `nil,error` |

`opts.onClose` is a no-argument callback. `opts.toolbar=true` adds a menu row;
`opts.menuItems` defines its entries:

```lua
menuItems={
  {label="File",items={
    {label="Save",eventName=saveEvent},
    {label="Close",eventName=closeEvent}
  }}
}
```

Each popup item has `label`, optional `eventName` and optional `value`. Selecting
it returns the item and pushes its event if specified. There is no separator or
disabled-item syntax. A popup uses ScreenSave and temporarily restricts TGL's
active area; a full modal dialog uses the overlay system described below.

## Notifications and dialogs

Core provides `ltnotify` directly:

| Call | Result |
| --- | --- |
| `notify(title,text,timeout?)` | Temporary notification, without blocking the caller |
| `warn(title,text,timeout?)` | Temporary warning notification with a beep |
| `error(title,text)` | Error dialog with red stop symbol |
| `dialog(title,text,buttons?,barCol?,icon?,opts?)` | Chosen button label, and checkbox state |
| `prompt(title,description,secret?)` | Entered text; a blocking prompt with an OK button |

`prompt` has no separate Cancel button; do not assume an empty result means
cancellation. `secret=true` masks its input.

Dialog buttons default to `{"OK"}`. The first button is also the Enter choice,
so put Cancel first for a destructive action. `icon` is `{text=...,color=...}`.
`opts.checkbox="Apply to all"` adds an initially unchecked checkbox; the second
return value reports its state. Dialogs use blue title bars unless overridden.

For a custom modal Frame, pair the calls even if your interaction code fails:

```lua
local state=ltnotify.openModal(frame)
local ok,err=pcall(function()
  -- Wait for the dialog's events here.
end)
ltnotify.closeModal(frame,state)
if not ok then error(err,0) end
```

Opening a modal elevates it and its children, registers an overlay, locks window
focus/dragging and restricts TGL's active area. Closing flushes queued drawing
before removing it, restores the previous lock/active area, and redraws below.
Notification expiry uses a core-owned timer so notifications can outlive the app
that created them.
