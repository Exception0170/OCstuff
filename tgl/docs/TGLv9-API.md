# TGLv9 core API

For TGL `0.9.5`. Start with [the guide](TGLv9.md) for a complete example and the
coordinate/event model. Unless noted, constructors use `:new` and drawing calls
queue work on `tgl.sys.renderer`.

## Values and geometry

| Constructor | Meaning |
| --- | --- |
| `tgl.Color2:new(fg?,bg?,is_palette?)` | Foreground/background pair; RGB values or palette indexes |
| `tgl.Pos2:new(x?,y?)` | Position; both default to 1 |
| `tgl.Size2:new(x,y,width,height)` | Rectangle from origin and dimensions |
| `tgl.Size2:newFromSize(x,y,width,height)` | Same as `new` |
| `tgl.Size2:newFromPoint(x1,y1,x2,y2)` | Rectangle from inclusive bounds |
| `tgl.Size2:newFromPos2(first,last)` | Rectangle from two points |

Use positive integer coordinates, positive dimensions and ordered bounds.
Constructors have uneven validation: some return nil for invalid arguments,
others assume well-formed input. `Pos2` checks x against screen width but does not
fully validate y; this allows relative content below a scroll viewport. It does
not mean arbitrary off-screen drawing is supported.

Color2 stores foreground in `[1]`, background in `[2]`, and `is_palette` when
palette indexes are intended. RGB values must be in `0..0xFFFFFF`. Omitted colors
use `tgl.defaults.foregroundColor` and `.backgroundColor`. `==` compares color
values, not the palette flag. `tgl.invertColor2(pair)` returns a new reversed pair.

Pos2 exposes `x,y` and numeric entries `[1],[2]`. `==` compares x/y. Size2 exposes
`x1,y1,x2,y2,sizeX,sizeY,pos1,pos2`. Use `size:moveToPos2(pos)` to preserve its
width and height. A BoxObject's `moveToPos2` delegates to its Size2; Frames also
translate their children.

## Text

```lua
local text=tgl.Text:new("Ready",colors,tgl.Pos2:new(2,2))
```

`Text:new(text,col2?,pos2?)` creates one positioned line. With no position, render
uses the current terminal cursor. `render(nextLine?)` only uses `nextLine` in
that cursor-based form. `updateText(text)` replaces the text and renders it.

- `text`: string to draw.
- `maxLength`: display limit, default -1 (unlimited). For limits over 4, render
  first clears the field and truncates long text with `..`; shorter limits just
  truncate. Truncation changes the object's text.
- `vertical`: one character per row, default false.

`MultiText:new(objects,pos2?)` groups Text objects. Positioned Text keeps its
position; Text without one is placed after previous text on the same line.
Iteration uses `pairs`, so do not use it to enforce a mixed named-child order.

## Buttons

```lua
local button=tgl.Button:new("[Save]",function(mouseButton)
  -- Handle the action.
end,tgl.Pos2:new(2,4),colors)

local eventButton=tgl.EventButton("[Save]",saveEvent,"save",
  tgl.Pos2:new(2,4),colors)
```

`Button:new(text,callback,pos2?,col2?)` uses the displayed text as its clickable
width. `EventButton(text,eventName,value?,pos2?,col2?)` has the same geometry but
pushes `eventName,value` instead of running an application callback.

Both support `render`, `enable`, `disable`, `text`, `col2`, `pos2`, `z_index`,
`hidden`, `checkRendered` and `onClick`. Default `onClick` briefly inverts colors.
Disable that with nil when opening another UI should not leave a delayed redraw.
Set unique event names before enabling. Changing `enabled` directly does not
register or unregister listeners: use the methods.

## Single-line input

`InputField:new(placeholder,pos2?,col2?)` starts with empty `.text`. The placeholder
is `.defaultText`; its display width defines the editing viewport.

| Field | Default | Meaning |
| --- | --- | --- |
| `text` | `""` | Current input |
| `eventName` | `"InputEvent"` | Event pushed after click-started editing finishes |
| `erase` | true | Clear existing text when editing starts |
| `secret` | false | Mask displayed characters |
| `maxLen` | -1 | Maximum character count; negative means unlimited |
| `scrollX` | false | Scroll horizontally instead of stopping at viewport width |
| `stopOnClickOutside` | false | End editing after an outside touch |
| `stopEventName` | nil | Additional event that ends editing |
| `charCol2` | Inverted colors | Editing cursor colors |

`render`, `enable` and `disable` have their usual roles. `input()` directly starts
the blocking editor and leaves its result in `.text`; it does not itself emit
`eventName`. The click handler emits that event with the text afterward.

Editing supports left/right, Backspace, Delete and typed characters. Enter,
Escape or interruption ends it. Escape is not a separate cancel result. Input
focus temporarily restricts the active area and restores it afterward.

## TextBox

`TextBox:new(text,size2,col2?)` is a read-only multiline area. It splits at newlines,
expands tabs using `tabSize` (default 2), truncates long lines and shows a scrollbar
when needed. It does not wrap paragraphs.

`showScroll` defaults true; `viewY` is the line offset. `enable`/`disable` control
the generated scrollbar's input. Rendering creates or removes that scrollbar
as the content changes. Replace `.text` and render to update it.

## InputBox

`InputBox:new(text,size2,col2?)` is a multiline editor. Clicking enters
`input(startX?,startY?)`; arguments are screen coordinates for initial placement.
The click handler emits `eventName,text` when editing finishes.

| Field | Default | Meaning |
| --- | --- | --- |
| `text` | Constructor text | Editable content |
| `eventName` | `"InputBoxEvent"` | Completion event |
| `stopEventName` | `"InputBoxStop"` | Event used to end active editing |
| `stopOnClickOutside` | true | Outside touch ends editing |
| `clearOnClick` | false | Start with cleared content |
| `wrap` | false | Wrap visual lines to the available width |
| `lineNumbers` | false | Show a line-number column |
| `lineNumCol2` | nil | Optional line-number colors |
| `tabSize` | 2 | Tab display/insertion width |
| `showScroll` | true | Show overflow scrollbar |
| `viewY` | 0 | Current vertical offset |
| `cursorCol2` | Inverted colors | Editing cursor colors |

Use distinct stop/completion event names for each instance. `disable()` requests
that an active edit end and leaves the control disabled. `input()` stores the
edited text when its loop exits. It has its own input loop, rather than an
application-wide keyboard dispatcher.

## Scrollbar

`Scrollbar:new(size2,col2?)` is a vertical, one-column scrollbar. Foreground is
the thumb color and background is the track color.

- `scroll`: current offset, initially 0.
- `maxScroll`: largest offset, initially 0; the caller supplies it.
- `visibleSize`: content viewport height, initially the track height.
- `scrollSpeed`: wheel multiplier, initially 1.
- `hitArea`: wheel-sensitive area, initially the scrollbar rectangle.
- `onChange`: optional function called with the new offset.

`setScroll(n)` clamps the offset to `0..maxScroll`, calls `onChange` and redraws.
No callback or redraw occurs when the offset is unchanged. `enable` installs
wheel/touch handlers; `disable` removes them. Interactions check the active area
and higher drawn z values. Setting `.scroll` directly does not call `onChange`.

## Frame

`Frame:new(objects,size2,col2?)` contains a table of named or numbered controls.
An empty table is valid. Children are translated from relative coordinates.

| Method | Meaning |
| --- | --- |
| `add(object,name?)` | Insert a child, translate positions; return true on success |
| `remove(key)` | Disable and remove a child; repaint separately |
| `translate()` | Recompute children's absolute coordinates from relative values |
| `moveToPos2(pos)` | Move bounds and translate children |
| `render()` | Paint background, border and children |
| `renderRegion(rect)` | Render with a temporary clip; restore previous clip afterward |
| `enableAll()` / `disableAll()` | Recursively register/remove child handlers |
| `open(ignore_ss?)` | Unhide, optionally capture background, render and enable children |
| `close()` | Hide, disable children and restore captured background if present |
| `openAll(ignore_ss?)` / `closeAll()` | Also open/close nested Frames |

`borders` is nil by default. Set it to `tgl.defaults.boxes.single`, `.double` or
`.round`, or a string whose first six characters are horizontal, vertical,
top-left, top-right, bottom-left and bottom-right. `borderType` is `"inline"`
(default) or `"outline"`. An outline occupies one cell outside each edge.

`ignoreOpen=true` on a child skips its recursive open. `relativeZ` is saved when
rendering, then added to the parent Frame's z. Do not expect `pairs` iteration
to give sibling overlays a particular order: use different z values.

## ScrollFrame

`ScrollFrame:new(objects,size2,col2?,scrollcol2?)` inherits Frame behavior and
clips vertically scrolled content to a viewport. It reserves the rightmost
column for its scrollbar when visible.

Set `maxScroll` explicitly; the constructor's default is 5, not a measured
content height. For one-row items:

```lua
local list=tgl.ScrollFrame:new({},tgl.Size2:new(2,2,24,6),colors)
for i=1,20 do
  list:add(tgl.Text:new("Item "..i,colors,tgl.Pos2:new(1,i)),i)
end
list.maxScroll=math.max(0,20-list.size2.sizeY)
list.scroll=0
list:render()
list:enable()
list:enableAll()
```

`showScroll` defaults true. `scroll` starts at 0. `scrollcol2` colors the thumb
and track. After replacing content, clamp scroll to the new range and translate
new children. No generic automatic content-height function is provided.

`enableAll`/`disableAll` operate on children. Also enable/disable the ScrollFrame
itself to manage its scrollbar. A parent Frame's dispatch does both for a
ScrollFrame child. Nested scrolling preserves the inherited renderer clip.

## ScreenSave

`ScreenSave:new(size2?,useBuffer?)` immediately captures a rectangle; with no
bounds it captures the screen. It prefers a GPU buffer and falls back to stored
character/color cells. Flush pending drawing before capturing what is displayed.

`render()` queues restoration. A buffer-backed restoration also queues freeing
the saved buffer, so treat it as a one-use snapshot. `unload()` releases a saved
buffer without restoring. Flush queued releases before ending the graphics
session. `save(useBuffer)` recaptures; release an existing saved buffer first.

`dump(filename?)` and `load(filename)` are legacy serialized snapshot helpers;
`dump` defaults to `screensave.st`. They are not TMG image-file operations. In
this implementation, passing false to the ScreenSave constructor still chooses
the buffer-preferred path.

## Helpers and system state

| Call | Meaning |
| --- | --- |
| `tgl.getCurrentPos2()` | Current terminal cursor position |
| `tgl.changeToPos2(pos,ignore?,offsetX?)` | Move cursor; return previous position unless ignored |
| `tgl.getCurrentColor2()` | Current GPU foreground/background pair |
| `tgl.changeToColor2(colors,ignore?)` | Set colors; return previous pair unless ignored |
| `tgl.getCursorState()` | Return position and color pair |
| `tgl.setCursorState(pos,colors,ignore?)` | Set both; return previous state unless ignored |
| `tgl.cwrite(text,colors?)` / `tgl.cprint(text,colors?)` | Immediate colored terminal output, restoring colors afterward |
| `tgl.sys.getActiveArea()` | Current shared interaction rectangle |
| `tgl.sys.setActiveArea(rect)` | Replace the interaction rectangle |
| `tgl.sys.resetActiveArea()` | Set interaction area to the cached screen bounds |
| `tgl.util.pointInSize2(x,y,rect)` | Inclusive point containment |
| `tgl.util.pos2InSize2(pos,rect)` | Position containment |
| `tgl.util.size2Intersects(a,b)` | Rectangle overlap |
| `tgl.util.size2InSize2(outer,inner)` | Whether the **second** rectangle is inside the first |
| `tgl.util.getLine(pos,length)` | Read a displayed line from the renderer/GPU |
| `tgl.util.getLineMatched(pos,text,colors?)` | Count matching displayed characters, optionally checking colors |
| `tgl.util.log(text,module?)` | Debug output when enabled |
| `tgl.util.objectInfo(object)` | Log basic object details |
| `tgl.util.printColors16(nextLine?)` | Draw the named palette |
| `tgl.util.clear()` | Immediate `term.clear()` |

`cwrite`, `cprint`, cursor/color helpers and `clear` act immediately. They are not
renderer composition commands; flush queued work before mixing them with UI
drawing.

`tgl.sys.markDirty(rect)` appends to `.dirtyRegions`; `clearDirty()` empties that
list. The renderer does not consume this list automatically. A compositor must
choose what to redraw.

Frame's recursive dispatch uses `tgl.sys.enableTypes`, `.enableAllTypes` and
`.openTypes`, keyed by each object's `.type`. A custom control can register its
type there when it implements the corresponding methods. That registration is
shared with other code using this TGL instance.
