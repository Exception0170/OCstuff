# TGLv9 renderer

The live renderer is `tgl.sys.renderer`, created and started by `require("tgl")`.
Use that instance for drawing. This reference covers TGL `0.9.5`; see
[the guide](TGLv9.md) for widget usage.

## Queue and lifecycle

Most methods enqueue commands rather than changing the display immediately.
A timer renders dirty queues, normally every `1/20` second. A batch sorts by z,
then enqueue order. Commands added while a render is running go into the next
queue. After each render, the renderer emits `renderDone` on the OpenOS bus.

| Method | Effect |
| --- | --- |
| `tgl.Renderer:init(interval?)` | Create the singleton if absent; interval is seconds, default 0.05 |
| `r:start()` | Install timer and reset-key listener; do nothing if already started |
| `r:stop()` | Pause timer-driven rendering; commands can still be queued |
| `r:resume()` | Allow timer-driven rendering again |
| `r:flush(buffered?)` | Resume and immediately render dirty work if not already rendering |
| `r:finish()` | Remove timer/listener, discard pending queues and free GPU buffers |

`stop` is not teardown, and `flush` leaves the renderer running. `finish` does not
disable widgets. Disable their handlers first. It frees all GPU buffers, not just
those belonging to one app; only the owner of the graphics session should call
it. The same renderer can be started again after finish. Calling init while an
instance exists does not replace it or change its timer interval.

`waitForAll()` waits for the next `renderDone` event. It does not test whether the
queue is already empty and does not prove there is no next queue. For ordinary
app redraws, use `flush` rather than waiting for an event that may never arrive.

The reset listener uses character code 18 (Ctrl+R) by default. It queues a reset
to buffer 0 and the default black color pair; it is not a full widget redraw.
Set `r.resetKeybindEnabled=false` if the host application owns that shortcut.

## Drawing calls

| Call | Meaning |
| --- | --- |
| `set(pos,text,colors?,z?,vertical?,buf?)` | Write text from a Pos2 |
| `setPoint(x,y,text,colors?,z?,vertical?,buf?)` | Same operation with numeric coordinates |
| `fill(rect,char?,colors?,z?,buf?)` | Fill a Size2; nil character means a space |
| `copy(sourceRect,offset,buf?)` | GPU-style copy; Pos2 supplies x/y **offsets**, not destination coordinates |
| `bufcopy(src,dst,destinationRect,z?,sourcePos?)` | Copy between GPU buffers; source position defaults to `(1,1)` |
| `get(pos,buf?)` / `getPoint(x,y,buf?)` | Immediately read `character,Color2` |
| `getZ(x,y)` | Last recorded on-screen z at that cell, or 0 |

A missing `buf` targets screen buffer 0. `vertical=true` writes one character per
row. A successful enqueue result is not proof of successful GPU execution;
execution failures are sent to the debug logger.

The parameter called `dst_pos2` in `copy` is forwarded directly as GPU copy
translation offsets. Because Pos2 itself rejects nonpositive x values, this
wrapper is awkward for zero/negative offsets. Do not treat it as a general
absolute-position copy function. Use explicit buffer copying when appropriate.

Reads are immediate and see already rendered content, not queued changes. Flush
before reading a just-updated area. A nonzero buffer ID is an actual GPU buffer
identifier, not its index in `buffers()`.

`getZ` tracks TGL's screen text/fill writes. It is not a GPU-provided depth buffer
and does not reject writes by itself. Direct GPU writes and arbitrary buffer
copies do not reconstruct this map. Widget hit tests use it to detect higher
rendered layers, so avoid bypassing the renderer for interactive content.

## Buffered flush

```lua
local r=tgl.sys.renderer
r:stop()
background:render()
foreground:render()
r:flush(true)
```

A buffered flush tries to allocate a temporary screen-sized GPU buffer. It copies
the current display into that buffer, applies queued screen drawing there, then
copies the completed result back to the screen. Existing pixels outside the
changed area survive. The temporary buffer is freed after presentation.

Allocation depends on available GPU buffer memory. If it cannot allocate, drawing
falls back to screen writes. A batch that frees all buffers also disables the
temporary-buffer path. Buffering does not choose which widgets need redrawing;
the application or window manager still supplies all affected layers.

## Clipping

```lua
local old=r:getClipRegion()
r:setClipRegion(area)
frame:render()
r:setClipRegion(old)
r:flush(true)
```

`setClipRegion(rect)` applies to subsequently queued commands; nil removes it.
The current clip is captured on enqueue. Restore it after drawing a component
so later drawing does not inherit an unrelated clip. Do not mutate a captured
clip rectangle before the queue is flushed.

Text and fill commands enforce the clip at execution, including partial
horizontal wide-character intersections. Buffer copies and GPU copy commands do
not gain the same text/fill clipping behavior. `Frame:renderRegion` temporarily
sets a clip; callers of that method must choose a clip within any enclosing area.
ScrollFrame intersects its viewport with the inherited clip for nested content.

## GPU buffers

| Method | Effect |
| --- | --- |
| `allocateBuffer(width,height)` | Immediate allocation; return `true,id` or false if validation/memory check fails |
| `hasBuffer(id)` | Check a GPU ID; 0 is always treated as present |
| `buffers()` | Return the GPU's current buffer IDs |
| `setBuffer(id)` | Queue an active-buffer change |
| `freeBuffer(id)` | Queue release of a valid nonzero buffer; return whether queued |
| `freeAllBuffers()` | Queue release of all buffers |
| `resetCursor(colors?)` | Queue selection of buffer 0 and a color pair |

Allocation and reads are immediate; drawing and release are queued. Pass buffer
IDs explicitly to drawing methods rather than assuming a queued `setBuffer`
changes the target of future calls: their default is still buffer 0. Keep
buffer-dependent commands in a consistent z/order sequence so a release cannot
sort before the work that needs it. Flush when ordering immediate and queued
operations around the same buffer.

`allocateBuffer` checks available memory but GPU allocation itself can still
raise an error. Use `pcall` when an allocation failure must be recoverable.

## Implementation files

- [init.lua](../usr/lib/tgl/init.lua): module loading and automatic startup.
- [renderer.lua](../usr/lib/tgl/renderer.lua): queue, GPU commands and buffering.
- [objects.lua](../usr/lib/tgl/objects.lua): control rendering and event handlers.
- [core.lua](../usr/lib/tgl/core.lua): value classes and shared state.
- [defaults.lua](../usr/lib/tgl/defaults.lua): palette, dimensions and constants.
- [util.lua](../usr/lib/tgl/util.lua): colors and screen-read helpers.
