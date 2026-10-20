# TGLv9

TGL is a text UI graphics library for OpenComputers and OpenOS. This guide
covers the v9 implementation in this repository, which reports `tgl.version`
as `0.9.5`.

TGL provides positioned text, buttons, input controls, Frames, scrollbars and a
queued renderer. It does not provide a desktop or app process manager. LTDE
builds those on top of it.

- [Core API](TGLv9-API.md): constructors, properties and helper functions.
- [Renderer](TGLv9-Renderer.md): drawing, clipping, buffers and lifecycle.

## Installation

Copy the complete `usr/lib/tgl` directory to `/usr/lib/tgl` on an OpenOS disk.
Load it with:

```lua
local tgl=require("tgl")
```

OpenOS supplies the component, event, thread, term, unicode and serialization
modules used by TGL. The code expects a GPU with buffer methods; Tier 2 or better
is the intended graphics setup. Select the screen resolution and color depth
before loading TGL: defaults cache them at initialization.

`require` loads the core, defaults, renderer, helpers and objects, then starts the
renderer timer and sets the active interaction area to the screen. It is not a
read-only import. The module is cached and shared by programs in the Lua machine.

`tgl-ui.lua` and `tgl-img.lua` are separate, optional modules. Copy them into
`/usr/lib` when using their additional controls or image support.

## A small program

This example runs directly in OpenOS and owns the renderer for its duration.
It needs at least a 34x12 screen. Click Count to update the label and Close to
exit. Each instance uses its own event name.

```lua
local tgl=require("tgl")
local event=require("event")
local term=require("term")
local r=tgl.sys.renderer
local done="tgl_example_"..tostring(math.random(1,1000000))
local count=0
local colors=tgl.Color2:new(0,0xD2D2D2)
local label=tgl.Text:new("Count: 0",colors,tgl.Pos2:new(3,3))
label.maxLength=20
local frame=tgl.Frame:new({
  label=label,
  count=tgl.EventButton("[Count]",done,"count",tgl.Pos2:new(3,6),colors),
  close=tgl.EventButton("[Close]",done,"close",tgl.Pos2:new(15,6),colors)
},tgl.Size2:new(2,2,32,9),colors)
frame.borders=tgl.defaults.boxes.single
frame.objects.count.onClick=nil
frame.objects.close.onClick=nil

local ok,err=pcall(function()
  r:stop()
  frame:open(true)
  r:flush(true)
  while true do
    local _,action=event.pull(done)
    if action=="close" then break end
    count=count+1
    label.text="Count: "..count
    r:stop()
    frame:render()
    r:flush(true)
  end
end)
frame:close()
r:finish()
term.clear()
if not ok then error(err,0) end
```

Inside LTDEv1, use its app/window API and `ltevent` instead. LTDE owns the shared
renderer, so an app must not call `finish()` when it closes. See
[LTDE's app example](../LTDE/docs/APPS.md).

## Coordinates

TGL uses a character grid, starting at `(1,1)` in the screen's top-left corner.
It does not use pixel coordinates or automatic layout. Some Unicode characters
occupy more than one screen column; `unicode.wlen(text)` gives display width.

`Pos2` is a point. `Size2` is a rectangle with inclusive bounds:

```lua
local position=tgl.Pos2:new(4,3)
local bounds=tgl.Size2:new(4,3,20,6)
-- x1=4, y1=3, x2=23, y2=8, sizeX=20, sizeY=6
```

A control used on its own has absolute screen coordinates. Coordinates given to
children of a Frame are relative to that Frame. A child at `(1,1)` starts at the
Frame's top-left cell, including its border if one is drawn.

Frames translate their children's positions when constructed, when children are
added, and when moved. They retain relative coordinates in `relpos2`/`relsize2`.
Treat a control as belonging to one Frame. Reusing an already translated object
in a different Frame can carry its old relative position with it.

To reposition a child after adding it, update its relative position and translate
the Frame. Changing only its absolute `pos2` will be overwritten by translation:

```lua
label.relpos2=tgl.Pos2:new(3,4)
frame:translate()
```

These values are tables, not immutable values. Avoid modifying a rectangle or
position after passing it to queued drawing; commands can retain that table.

## Objects and Frames

Classes are tables with metatable inheritance. Constructors normally use
`Class:new(...)`. `tgl.EventButton(...)` is the exception: it is a function.

Single-line objects have `pos2` and `col2`; rectangular objects have `size2` and
`col2`. Most have `type`, `z_index` and `hidden`. Setting properties changes the
object, not the displayed screen: call `render()` or redraw its parent afterward.

A Frame paints its background and optional border, then renders its children.
It owns a named or numbered `objects` table:

```lua
frame:add(tgl.Text:new("Ready",colors,tgl.Pos2:new(3,7)),"status")
frame:remove("status")
```

Removing a child disables it but does not repaint its old position. Redraw the
Frame to clear that area. Likewise, `hidden=true` skips drawing but does not
remove pixels already displayed. Disable hidden controls as part of hiding them.

`render()` queues drawing. `enable()` registers a control's handlers; it does not
render it. `Frame:enableAll()` enables children recursively, and `disableAll()`
removes those registrations. A standalone ScrollFrame also needs its own
`enable()`/`disable()` calls for its scrollbar.

## Ordering and redraws

Higher `z_index` commands draw after lower ones in the same batch. Commands with
equal z retain their enqueue order. A Frame derives each child's absolute z from
its own z and the child's saved `relativeZ`.

This is drawing order, not a retained scene: TGL does not automatically redraw
another Frame when an object below it changes. An application with overlapping
panels must repaint all affected layers in the right order. LTDE's compositor
does this for managed windows.

Batch a redraw to avoid showing intermediate clears:

```lua
r:stop()
frame:render()
r:flush(true)
```

`flush(true)` uses a temporary GPU buffer when available. Without enough buffer
memory it falls back to direct drawing. Avoid redrawing a whole screen when a
small region changes; use clipping or a compositor. Do not redraw on a scroll
attempt that leaves the scroll position unchanged.

## Events and input

Buttons listen for OpenOS `touch`; scrollbars use `scroll` and `touch`.
`Button` runs its callback from the event handler. `EventButton` pushes an event
so application logic can stay in the main event loop.

Give each instance unique event names. A Button's callback receives the touch
button value. Core buttons do not automatically distinguish left-click actions
from right-click actions; check that value when the distinction matters.

Buttons have a short inverted-color click animation in `onClick`. Set
`button.onClick=nil` to disable it. `disable()` cancels pending restore feedback.
Callback errors are caught and sent to TGL's logger; with debug logging disabled,
those errors are not printed to the screen. EventButton handlers let the main
loop handle its own errors instead.

`checkRendered=true` uses the renderer's cell z information to reject clicks
behind higher layers. It is not a window focus system. Direct GPU drawing does
not update TGL's z map, so it can make hit checks inconsistent.

The global active area limits where controls respond:

```lua
local previous=tgl.sys.getActiveArea()
tgl.sys.setActiveArea(panel.size2)
-- Interact with the panel.
tgl.sys.setActiveArea(previous)
```

`InputField:input()` and `InputBox:input()` are blocking editing loops. Clicking
enabled input controls enters those loops and emits their completion event when
they finish. Use stop events where the owning UI needs to end input explicitly.
TGL itself has no per-window keyboard focus or private event queues.

## Closing and cleanup

`Frame:open()` captures the background, draws and enables its children.
`Frame:close()` disables them and restores that snapshot. A snapshot is useful
for a short-lived popup over a static background; it can be stale if other
content changed behind it. Use `open(true)` to skip capture and handle repainting
yourself. `openAll`/`closeAll` also open/close nested Frames.

Always disable controls, cancel your timers, remove your own listeners and close
file handles on exit. TGL does not maintain an application-wide registry of
arbitrary event handlers. Calling renderer `finish()` does not disable widgets.
Only the program that owns the graphics session should stop the shared renderer.

## Defaults and logging

`tgl.defaults.colors16` contains named colors chosen for the GPU depth at load
time. Prefer these for Tier 2 displays. `colors2` contains common foreground/
background pairs; `boxes` contains border characters; `keys` and `keys2` contain
character and scan-code constants. Defaults are shared mutable tables.

Debug logging is disabled by default. To enable it for development:

```lua
tgl.debug=true
tgl.logfile="/home/tgl.log"
```

`tgl.util.log(text,module)` sends output to the Ocelot component when present,
otherwise to `tgl.logfile` if it is non-empty.

## Optional modules

`require("tgl-ui")` returns the extra controls module, version `1.3.2`:
CheckBox, Progressbar and DropdownMenu, plus window/layout helpers. Its checkbox
and dropdown types register with Frame's enable/disable dispatch. Their API
belongs to that module, not the core `tgl` table.

For example, a progress value is a fraction from 0 to 1:

```lua
local ui=require("tgl-ui")
local progress=ui.Progressbar:new(tgl.Pos2:new(3,3),20,
  tgl.defaults.colors2.progressbar)
progress:setValue(0.5,true)
```

`require("tgl-img")` returns image support, version `1.6`, including the TMG
format, compression helpers and an Image class. Use `Image:load(path,pos?)` to
obtain a new image object; it returns `false,error` if loading fails. `render()` queues
its drawing. Keep image buffers in your resource cleanup.

See [the tgl-img guide](TGL-IMG.md) for source rectangles, viewport clipping
and reusable image buffers.
