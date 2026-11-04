# TGLv10 development

TGLv10 grows from TGLv9. Coordinates still use screen cells, with relative
coordinates inside frames. The current version is `0.10.0`.
New graphics features prioritize Tier 3 rather than designing around Tier 2.

## Themes

TGL starts with built-in defaults. It does not read a theme file on import.
Load and select one before creating the UI:

```lua
local theme,err=tgl.sys.loadTheme() -- /etc/tgl/theme.st
if theme then tgl.theme=theme
else print(err) end
```

`tgl.sys.loadTheme(path)` accepts another path. It returns a complete theme or
`nil,error`, and never changes `tgl.theme` itself. Missing entries use built-in
defaults. Missing files, invalid sections/roles, invalid colors and invalid glyphs
return an error. Files are limited to 16 KiB; the file is closed after reading.

The file is an OpenOS serialized table, not a Lua program loaded with `dofile`:

```lua
{
  colors={
    button={0x000000,0xCCCCCC},
    input={0x000000,0xFFFFFF},
    focus={0x000000,0xFFCC33}
  },
  chars={scrollbarTrack="▒",scrollbarThumb="█"}
}
```

Colors are `{foreground,background}` RGB integers from `0` to `0xFFFFFF`.
`is_palette=true` makes both values palette indices from `0` to `15` instead;
these require a color depth that supports palette indices. Loaded colors are
`Color2` objects. A serialized `tgl.theme` table can be loaded again.

| Color role | Constructor defaults |
| --- | --- |
| `text` | Text |
| `button` | Button, EventButton, CheckBox, RadioButton and DropdownMenu |
| `frame` | Frame |
| `input` | InputField, InputBox, TextBox and ScrollFrame |
| `scrollbar` | Scrollbar and internal scrollbars |
| `progressbar` | Progressbar |
| `focus` | Keyboard focus colors |

`chars.scrollbarTrack` and `chars.scrollbarThumb` must each be a single glyph
occupying one screen cell. The built-in track is `▒` and the thumb is `█`.
`checkboxChecked`/`checkboxUnchecked` default to `🗹`/`🗷`;
`radioSelected`/`radioUnselected` default to `●`/`○`. These state glyphs may
occupy one or two cells, as reported by `unicode.wlen()`.

Constructors copy theme defaults. Assigning another `tgl.theme`, or editing its
entries, affects newly constructed widgets. Existing widgets keep their colors
and decorations, including internal scrollbars created later. Passing a color to
a constructor overrides its theme role. Existing explicit colors inside UI helper
functions also keep their meaning; `tgl.defaults.colors2.white`, `black` and other
named colors remain available.

To change an existing widget, set its usual fields and redraw: `col2`,
`focusCol2`, or a scrollbar's `trackChar`/`thumbChar`. Containers with internal
scrollbars expose `scrollcol2`, `scrollTrackChar` and `scrollThumbChar`.

## Core widgets

`CheckBox`, `Progressbar` and `DropdownMenu` are included in `require("tgl")`.
They use the same constructors and behavior as their earlier `tgl-ui` versions:

```lua
local tgl=require("tgl")
local check=tgl.CheckBox:new(tgl.Pos2:new(2,2))
local progress=tgl.Progressbar:new(tgl.Pos2:new(2,4),20)
local dropdown=tgl.DropdownMenu:new(tgl.Pos2:new(2,6),16,nil,{"One","Two"})
progress:setValue(0.5,true)
```

They support the shared theme defaults, container clipping and object disposal.
CheckBox and DropdownMenu also participate in keyboard navigation and owned
event handling. Frame enable/disable methods recognize them without loading
`tgl-ui`.

`require("tgl-ui").CheckBox`, `.Progressbar` and `.DropdownMenu` are aliases to
the same classes. Existing programs can keep their imports. Loading `tgl-ui`
does not recreate or wrap these classes again. Dialogs, file pickers and window
helpers remain in `tgl-ui`.

### CheckBox and RadioButton

`CheckBox:new(pos2,col2,width,char,uncheckedChar)` displays separate checked and
unchecked glyphs. All arguments are optional. The width is a minimum in screen
cells and expands to fit both glyphs. `char` is the checked glyph;
`uncheckedChar` is the unchecked glyph. Existing calls supplying only a custom
`char` retain a blank unchecked state. Default calls use the theme's `🗹`/`🗷`.

`check:setValue(boolean,render)` changes the state and optionally redraws it;
`check:toggle()` changes and redraws it. They return false for an unchanged or
destroyed object. Rendering derives `text` from `value` and the glyph fields.
There is no delayed toggle animation. Clicks work across the glyph's cell width;
the renderer's z information rejects clicks covered by other objects.

`RadioButton:new(pos2,col2,group,width,char,uncheckedChar)` uses the same styling.
Pass a shared group table for mutually exclusive choices:

```lua
local group={}
local first=tgl.RadioButton:new(tgl.Pos2:new(2,2),nil,group)
local second=tgl.RadioButton:new(tgl.Pos2:new(2,3),nil,group)
first:setValue(true)
```

Use `setValue(true,render)` to select an option and clear the others. Clicking,
Space or Enter selects it; activating it again keeps it selected. With a TGL input
context, arrow keys move focus and selection through eligible group members.
Groups start with no selection. `setValue(false,render)` can clear a selection
explicitly. Use these methods rather than assigning radio `value` fields directly
to preserve exclusivity. Destroying a radio removes it from its group; it does
not automatically select a replacement. Omitting the group makes it independent.

`tgl-ui.RadioButton` is also an alias to the core class.

## TMG images

TMG support is part of TGL, loaded on first use of `tgl.Image` or `tgl.img`.
Text-only programs do not load the image code or codec tables.

```lua
local tgl=require("tgl")
local image,err=tgl.Image:load("/home/picture.tmg",tgl.Pos2:new(3,3))
if not image then error(err) end
image:render()
tgl.sys.renderer:flush(true)
-- When finished with the image:
image:destroy()
tgl.sys.renderer:flush()
```

`tgl.Image` is the existing Image class: loading/saving, partial rendering,
4/8-bit colors, extended characters, compression and transparency keep their
current behavior. Images use character-cell coordinates; an ordinary half-block
cell represents two vertical pixels. Owned images obey frame clipping and are
destroyed with their parent.

`tgl.img` contains the codec helpers and settings previously exposed by
`tgl-img`, including `autoPreload`, `enableCompressing` and `saveScreenToTmg`.
`require("tgl-img")` returns that same table, and its `Image` field is exactly
`tgl.Image`. Loading either name repeatedly does not recreate the image class,
reset settings or register another renderer command. Settings are shared across
programs using the same TGL instance; use `image.autoPreload=false` for a local
preloading override.

The file format and image API are documented in [TMG images](TGL-IMG.md).

## Gradients

Gradients are optional decorations. Solid widget colors remain the default.

```lua
local blue=tgl.Gradient:new(0x000080,0x0080FF)
local vertical=tgl.Gradient:new(0x202020,0x606060,true)
```

`Gradient:new(from,to,vertical,steps)` takes two RGB colors. Direction defaults to
horizontal; `vertical=true` runs top to bottom. The optional `steps` limits the
number of color bands, with a minimum of two. Without it, every column or row
gets an interpolated color. A one-cell extent uses the start color. Invalid
arguments return nil. The GPU approximates colors to its current color space;
gradient rendering does not change the palette.

Renderer methods:

- `r:gradient(area,gradient,col2,z_index,buf)` fills a background gradient.
- `r:gradientText(pos2,text,gradient,area,col2,z_index,vertical,buf)` draws text
  with its background sampled from the same gradient area. `area` defaults to
  the text's bounds. The second `vertical` controls text direction.

`col2` supplies the foreground color; the gradient supplies the background.
Each call queues one command. Execution combines adjacent identical colors into
runs or strips. There is no per-cell retained command list or image dependency.
Clipping preserves the full gradient's coordinates, so a partial redraw matches
the original. Geometry, colors and gradient settings are captured when queued.
Use `r:flush(true)` for buffered presentation when drawing decorated regions.

Set `gradient` on a Frame, ScrollFrame, Text or Progressbar:

```lua
local caption=tgl.Text:new("Window title",tgl.Color2:new(0xFFFFFF,0),tgl.Pos2:new(2,1))
local titlebar=tgl.Frame:new({caption=caption},tgl.Size2:new(5,3,40,1))
titlebar.gradient=blue
caption.gradient=blue
titlebar:open(true)
tgl.sys.renderer:flush(true)
```

A Text sharing its parent's gradient automatically samples the parent's bounds.
Otherwise, set `text.gradientArea` to an explicit rectangle, or omit it to use
the text's own bounds. Text remains readable without drawing a flat background
rectangle over the titlebar. Wide characters use the background at their leading
cell. Frame borders and other children retain their explicit colors.

For a progress bar, `progress.gradient=blue` colors its filled part. Colors are
anchored to the full bar, so increasing progress reveals more of the same ramp.
Both solid and gradient progress bars use `▌` for half-cell increments.
The unfilled part uses `progress.col2`'s background. Shrinking or clearing progress
repaints that area. ScrollFrame gradients remain anchored to the visible frame.

Titlebars, section headers and progress bars are good uses. Frame backgrounds
can use a subtle ramp, while text-heavy areas usually benefit from solid colors.

## Event ownership

`tgl.Event` groups OpenOS listeners and timers under one owner. It uses the
existing OpenOS event system; callbacks receive the usual event arguments.
It does not filter input by window or provide a sandbox.

```lua
local events=tgl.Event:new()
events:listen("touch",function(_,screen,x,y,button,player)
  -- Handle the event.
end)
local timer=events:timer(1,function()
  -- Update once per second.
end,math.huge)

events:cancel(timer)
events:destroy()
```

- `tgl.Event:new(parent)` creates a scope. The default parent is the library scope.
- `scope:listen(name,callback)` registers a listener. Returns false for a duplicate
  within that scope or a destroyed scope. Different scopes may use the same callback.
- `scope:ignore(name,callback)` removes that scope's listener only.
- `scope:timer(interval,callback,times)` returns an OpenOS timer ID. The default
  count is one; `math.huge` repeats indefinitely.
- `scope:cancel(id)` cancels a timer owned by that scope only.
- `scope:clear()` removes listeners and timers from this scope and its children.
  The scopes can be used again.
- `scope:destroy()` clears and permanently closes this scope and its children.
  Repeated calls are harmless. Registration then returns false.

Returning false from a callback removes its registration. Finished timers are
removed from the scope automatically. Callback errors remove the registration
and are passed back to OpenOS's event error handling.

Keep the scope for as long as its owner exists. Active callbacks also keep it
alive. Parent tracking uses weak keys, so unused scopes are not retained just
because the library is loaded.

Widgets that register listeners create `object.events=tgl.Event:new()` in their
constructors and use it directly. The renderer does the same. Objects without
registrations do not allocate a scope. The existing enable/disable methods
use owned listeners, including the temporary InputBox scroll listener. These
methods remain reusable; disabling a widget does not destroy its scope.
Custom widget listeners should be explicitly removed on disable as appropriate.

Call `tgl.finish()` when leaving a standalone UI. It finishes the renderer,
releases GPU buffers, and clears all library event scopes. LTDE calls it during
shutdown and crash exit. Apps running inside LTDE must clean up their own scope;
they must not call `tgl.finish()` on the shared library.

`renderer:finish()` still finishes only the renderer and allows it to restart.
Neither finish method stops application threads or cleans up direct OpenOS
registrations. Removing a listener does not interrupt a callback already running;
widget disable logic still needs to cancel any pending animation or input work.
Automatic app ownership is separate work.

## Keyboard navigation

`tgl.Input` is an opt-in input context for a standalone UI. Existing programs
keep their current mouse listeners and blocking `input()` calls until they use
a context. LTDE does not enable this automatically.

```lua
local tgl=require("tgl")
local event=require("event")
local done=false
local field=tgl.InputField:new("                ",tgl.Pos2:new(2,2))
local close=tgl.Button:new("Close",function() done=true end,tgl.Pos2:new(2,4))
local frame=tgl.Frame:new({field=field,close=close},tgl.Size2:new(2,2,24,7))
frame:open()
local input=tgl.Input:new(frame)
input:start()
while not done do event.pull() end
input:destroy()
frame:close()
frame:destroy()
tgl.sys.renderer:flush()
tgl.finish()
```

- Tab / Shift+Tab moves forward/backward, wrapping within the active root.
- Enter / Space activates buttons, EventButtons and checkboxes.
- Text fields receive typing, editing keys and arrows when focused. Enter
  finishes a single-line field; further typing starts editing it again.
- Multiline editors insert literal tabs by default. Ctrl+Tab / Ctrl+Shift+Tab
  leaves the editor. Set `box.acceptTab=false` to use ordinary Tab traversal.
- Dropdowns use Up/Down to highlight choices and Enter/Space to select. Moving
  focus away dismisses the choices without committing the highlighted value.
- Scrollbars and scrollable text/frame controls accept Up/Down, Page Up/Down,
  Home and End.
- Escape is ignored by the context. Provide keyboard-reachable Cancel and Close
  buttons; no action depends on Minecraft forwarding Escape.

Focus order defaults to top-to-bottom, then left-to-right, with object keys
breaking ties. Hidden, disabled, destroyed and scrolled-out controls are skipped.
Set numeric `control.tabIndex` values to prioritize controls, or provide an
explicit prefix such as `frame.focusOrder={field,close}`. Remaining controls
follow the default order. Set `focusable=false` to exclude a control from focus.

For a group of buttons, set their container's `navigation="horizontal"` or
`navigation="vertical"`. The matching arrow keys move between immediate child
controls. A control's own key handling takes priority, so text editing and
dropdown/scroll navigation retain their arrows.

The focus color defaults to `tgl.defaults.colors2.focus`. Override it per control
with `control.focusCol2`. It is applied while drawing; `control.col2` is unchanged.
Multiline editors preserve their caret position across focus changes. Managed
single-line fields preserve their text on focus, even when the legacy `erase`
option is true. Focus alone never clears their text.

### Context methods

- `tgl.Input:new(root)` creates a context without owning or opening the root.
- `input:start()` registers owned listeners and focuses the first control.
  Only one context can listen at a time; a second active context is rejected.
- `input:start(false)` enables manual forwarding instead. Call
  `input:handle(event.pull())` in your loop. Do not also register automatic
  listeners. `handle()` returns whether the context handled the event.
- `input:focus(control)` changes focus; false means the control is ineligible.
  `input:focus(nil)` clears it. `input:next(reverse)` traverses the focus order.
- `input:pushModal(dialog)` confines input to an already-open dialog.
  After closing the dialog, call `input:popModal()` to restore the previous root
  and focus. Modal scopes can nest; they do not open or close frames themselves.
- `input:stop()` unregisters listeners, commits an active editor and restores
  native widget mouse handling. The context can start again.
- `input:destroy()` stops and permanently disposes of the context.

The context routes mouse focus and prevents enrolled widgets' native listeners
from handling the same click twice. Added controls are discovered on navigation
and pointer events. Detached controls are released for reuse. Destroying the
main root or calling `tgl.finish()` also destroys its context.

Custom controls can set `focusable=true`, `enabled=true`, and implement
`keyDown(char,code,shift,ctrl)`, returning true for a handled key. An optional
`activate()` handles Enter/Space. Use `focused` and `focusCol2` in `render()` for
the focus indication. Focusable custom controls need `pos2` and `width`/`text`,
or `size2`, for ordering and hit testing.

Managed editors use coroutines driven by the context; other focused controls
remain responsive. This does not consume signals from unrelated OpenOS listeners,
provide a sandbox, or decide desktop window focus. Desktop integration remains
separate work.

## Pointer routing and capture

Pointer hit tests use the visible part of a control, clipped by its containers
and the active area. ScrollFrame children cannot receive input through the
scrollbar column or outside the viewport. A modal root blocks clicks and wheel
events from reaching the previous root. Dropdown choices outside the parent
clip cannot be selected.

Dragging a built-in scrollbar captures its gesture. Further drag/drop events go
to that control even when the pointer leaves it, crosses other controls, or
leaves the active area. Scrollbars inside TextBox, InputBox and ScrollFrame use
the same routing. Capture matches the original screen, mouse button and player.
Another player's or button's release cannot finish it. A normal drop releases
capture, including a drop with no preceding drag.

The context normally accepts pointer-down and wheel input from the GPU's bound
screen. Set `input.screen` to an explicit screen address if needed. Changing the
bound/selected screen cancels a capture from the previous screen.

Capture is canceled when its control is disabled, destroyed, detached, loses
focus, or is covered by a new modal input scope. Stopping the context cancels it
too. Built-in disable/close/destroy methods cancel immediately. Direct field
changes such as `control.hidden=true` or `control.enabled=false` are checked
before the next input event. This keeps ordinary Lua fields without adding a
polling timer or property setters.

Wheel events start at the deepest visible control. If it has no wheel handler,
or its handler returns false, routing continues through its containers, stopping
at the current root. This lets a scroll frame scroll when the pointer is over
one of its buttons. Return nil or true to handle the wheel event. A scrollbar
can use `hitArea` to extend its wheel area; container clipping still applies.

### Custom pointer hooks

Controls with `enabled=true` and `pos2`/`width` or `size2` can supply these callback
fields. They do not need to be keyboard-focusable:

- `pointerDown(name,screen,x,y,button,player)` receives a touch.
- `pointerDrag(name,screen,x,y,button,player)` receives captured drags.
- `pointerDrop(name,screen,x,y,button,player)` receives the captured release.
- `pointerScroll(name,screen,x,y,direction,player)` handles or declines wheel input.
- `pointerCancel(reason,screen,button,player)` resets state after cancellation.

These are callback fields called with dot syntax, without an implicit self.
Their event argument order follows OpenComputers' [screen signals](https://ocdoc.cil.li/component:signals).
The context clips synchronous drawing in pointer handlers to their containers.
Captured coordinates can be outside the control: clamp them when the tool needs
bounded coordinates. Keep cancellation hooks focused on clearing gesture state;
the control may already be hidden or destroyed.

```lua
canvas.pointerDown=function(_,screen,x,y,button,player)
  if button==0 then
    canvas.pressed=canvas.inputContext:capturePointer(canvas)
  end
end
canvas.pointerDrag=function(_,screen,x,y,button,player)
  -- Update this canvas's gesture using x and y.
end
canvas.pointerDrop=function()
  canvas.pressed=false
end
canvas.pointerCancel=function(reason)
  canvas.pressed=false
end
```

- `input:capturePointer(control,screen,button,player)` captures an eligible
  control. Inside pointerDown the event metadata can be omitted. Returns false
  if it is unavailable or another control already owns capture.
- `input:releasePointer(reason)` cancels capture, calling pointerCancel once.
  The default reason is `released`. Normal drops call pointerDrop instead.
- `input:cancelPointer(control,reason)` cancels capture belonging to that control
  or its descendants. Custom disable methods can use it for immediate cleanup.
- `input.capture` is nil when idle. While captured it records `object`, `owner`,
  `root`, `screen`, `button`, `player`, and the last `x`/`y` coordinates.

Cancellation reasons include `disabled`, `destroyed`, `detached`, `focus`,
`modal`, `stopped`, `screen`, `unavailable` and `error`. Pointer callback errors
are logged through TGL and cancel the gesture without removing the router's
listener. None of this filters signals from unrelated OpenOS listeners or raw
GPU access.

## Object lifetime

- `disable()` stops the widget's usual input handlers. It can be enabled again.
- `Frame:close()` hides and disables a frame, restoring its saved background if
  present. `open()` can show it again.
- `object:destroy()` permanently disposes of an object. It returns true on the
  first call and false on subsequent calls. Destroyed objects cannot be rendered,
  enabled, opened or added to another frame.

Destruction closes `self.events`, destroys owned children and internal scrollbars,
and unloads owned GPU buffers. It wakes active built-in input/drag loops and
prevents pending built-in animations from drawing again. A callback already
running is not forcibly interrupted; custom callbacks must check the owner's
`destroyed` flag after yielding.

Frames own controls passed to their constructor or added with `frame:add()`.
A control can belong to one container at a time; cycles are rejected.
`frame:remove(name)` disables and detaches the control, clears its parent link,
and returns it for reuse. It does not destroy the control. Replacing a named
control also detaches the old one; the caller is responsible for reusing or
destroying it. Use these methods when changing ownership.

```lua
local button=frame:remove("button")
otherFrame:add(button,"button")
otherFrame:destroy() -- destroys the button too
```

`destroy()` does not restore screen pixels or flush the renderer. Buffer releases
are queued in drawing order; use the normal redraw/flush path to complete them.
`ScreenSave:destroy()` discards its saved area; `Image:destroy()` also releases
decoded image data. Removing an LTDE managed window destroys its frame and
redraws the exposed region. This also covers app exit, crashes and termination
through runctl. Close callbacks run once, after disposal.

Custom widgets can override `destroy()` for additional resources and call
`tgl.UIObject.destroy(self)` for standard cleanup. Images held only in an app's
own variables, direct OpenOS registrations and app-owned background tasks still
require explicit cleanup. Automatic app scopes are not implemented yet.

## Clipping and redraws

Frames clip their children to their bounds. Scroll frames also exclude the
scrollbar column and skip children outside the visible rows. Built-in controls
and images keep these limits during direct redraws, including button animations
and text updates. Hidden or destroyed ancestors suppress those redraws.

`frame:renderRegion(region)` intersects the requested region with the renderer's
current clip. Custom drawing can use the same scoped behavior:

```lua
renderer:withClip(region,function()
  frame:render()
end)
```

The previous clip is restored even if drawing fails. This queues drawing as
usual; it does not flush. Custom widgets drawn by a frame are clipped too; custom
widgets drawing themselves directly can use `tgl.sys.drawObject(self,draw,...)`.

Dropdown snapshots cover only their visible area. Reopening a frame preserves
its original saved background, and closing nested frames restores the outer
background last. Snapshots keep their own bounds when a frame changes size.
The RAM snapshot fallback flushes queued drawing before reading screen cells.
Snapshots restore the original per-cell z values as well as characters and
colors. RAM snapshots use packed rows; restoration queues one command and groups
adjacent cells with matching colors and z into text runs. Both storage paths
consume the snapshot when restored. Pass `false` as `ScreenSave:new(area,false)`
to explicitly use RAM storage.

Queued commands capture their geometry, colors and clip when submitted, so moving
an object before a flush does not move its earlier drawing commands. Custom
command payloads remain the custom renderer's responsibility.

Screen copies obey destination clipping and adjust their source accordingly.
`renderer:copy(area,offset)` takes an offset, matching `gpu.copy`, and preserves
the source's per-cell z values. `bufcopy` writes its command's z value to the
screen; saved backgrounds supply their original z values instead. Copies into
offscreen buffers use buffer-local coordinates, without the screen clip.

Updating text to the same value queues nothing; shorter text clears its old
tail. Moving or shrinking a standalone frame still requires the caller to redraw
the exposed area. Clipping alone cannot reconstruct the background there.

## Argument checks

Public constructors and methods use OpenOS's global `checkArg` for argument types.
TGL does not provide a replacement. A wrong type raises the usual argument error
at the API call, including its argument number. Optional arguments still accept
nil and use their existing defaults. Callback/event payloads and deliberately
coercive methods such as `Text:updateText(value)` keep their original behavior.

`checkArg` validates types, not the contents of every table. Existing geometry,
range, ownership and file-format checks remain separate. Invalid ranges and I/O
failures retain their documented nil/false returns instead of becoming type
errors. Numeric-string conversions remain supported where the API already used
them, including Pos2, Color2, Size2 dimensions and Progressbar values.

## Next work

- Consider common renderer shortcuts.
- Choose the final release version and review the archive before tagging.

Installation, migration and archive building are in [release preparation](TGLv10-RELEASE.md).
