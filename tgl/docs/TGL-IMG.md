# tgl-img 1.7

`tgl-img` loads, saves and draws TMG images. It is a separate module used with
TGLv9 (`0.9.6`):

```lua
local tgl=require("tgl")
local tmg=require("tgl-img")
local image,err=tmg.Image:load("/home/picture.tmg",tgl.Pos2:new(3,3))
if not image then error(err) end
image:render()
tgl.sys.renderer:flush(true)
```

An Image stores its cell dimensions and position in `size2`, its color depth in
`depth`, and decoded file payload in `rawdata`. `extended` indicates that cells
also store characters; otherwise they use the module's half-block character.
An ordinary cell represents two vertical color pixels. All coordinates in this
API are character cells, not those individual pixels.

## Partial drawing

`image:renderRegion(source,destination)` draws part of the image without changing
its data, dimensions or stored position. `source` is a rectangle in image-local,
1-based coordinates. `destination` is the screen position where the requested
rectangle's top-left would appear.

```lua
-- Draw columns 5..24 and rows 3..10 at screen position (2,4).
local ok,err=image:renderRegion(
  {x1=5,y1=3,x2=24,y2=10},
  tgl.Pos2:new(2,4)
)
if not ok then error(err) end
tgl.sys.renderer:flush(true)
```

A source can be a Size2 or a plain bounds table. Plain tables are useful for
large images: TGL's Pos2/Size2 constructors restrict some x coordinates to the
screen width, whereas image-local coordinates can extend beyond it.

Omitting the source means the whole image. Omitting the destination uses the
Image's stored position. `image:render()` retains its existing full-image
behavior and now respects clipping too.

With the current v9 renderer, image pixels are decoded while a compact image
command executes, rather than retained as one queued command per cell. Update
`usr/lib/tgl/renderer.lua` together with `tgl-img.lua` for that memory-saving path.
Older v9 renderers use the original per-cell fallback.

Both paths intersect the request with the image bounds, screen bounds and current
renderer clip. Trimming an edge preserves source-to-destination alignment. An
entirely invisible request succeeds without drawing or allocating a buffer.
Coordinates must be finite integers. Invalid input returns `false,error`.

For a viewport, use `renderRegion` with the scroll offsets and visible dimensions;
set the renderer clip to the viewport when other content may overlap it. Restore
the previous clip afterward. Rendering queues work; it does not flush for you.
Neither zoom nor image resizing is implemented. Changing `size2` dimensions does
not resample the image.

## Buffers

`tmg.autoPreload` defaults true. Rendering tries to decode the image into a GPU
buffer, copies the visible rectangle, then queues release of that temporary
buffer. If there is not enough GPU memory, it draws visible cells directly.
Images wider than TGL's screen-coordinate limit also use direct regional drawing.
Set `image.autoPreload=false` to disable automatic buffering for one image,
without changing the module-wide setting. Explicit `image:preload()` still works.

For repeated drawing, explicitly preload and retain the buffer:

```lua
local cached,err=image:preload()
-- If caching fails, rendering can still use the direct path.
image:renderRegion({x1=1,y1=1,x2=20,y2=8},tgl.Pos2:new(2,2))
tgl.sys.renderer:flush(true)
image:unload()
tgl.sys.renderer:flush()
```

`preload()` returns true or `false,error`; calling it again with a valid buffer
does not allocate another. `unload()` queues release and clears the preload state.
The buffer ID is checked as a GPU ID, not an index in the GPU's buffer list.
Preload fills the full buffer independently of the caller's viewport clip, then
restores that clip. Masked images use direct compositing instead; `preload()`
returns `false,error` because a reusable image buffer cannot preserve holes.

After editing `rawdata`, depth, extended mode or dimensions, unload the old buffer
before rendering again. The direct path keeps row offsets for extended data;
those are rebuilt when its payload or dimensions/depth change. Buffer release
commands use the image's z so they execute after its queued drawing/copy.

## Loading and saving

`Image:load(filename,pos?)` returns a new Image or `false,error`. It reads the raw
flag byte separately from the line-based header, decompresses the payload and
checks dimensions and data length. Extended rows are checked while indexing
character/color boundaries. Color bytes are binary and are not Unicode text.

`image:save(filename?)` returns true or `false,error`. With no filename it uses
`image.name..".tmg"`. Names must fit on one line. Compression is controlled by
`tmg.enableCompressing`, which defaults true.

Load/save close their file handles on success and failure. Saving checks write,
flush and close errors, including OpenOS's nil-without-error close result. Saving
directly replaces the target file; it is not an atomic temporary-file save.

Version 1.7 adds an optional transparency mask. Images without a mask retain
their previous file layout and color encodings. The new loader reads older
images; older loaders cannot read files with the transparency flag.

## Transparency

`image.mask` is either nil (fully opaque, no mask stored) or a packed byte string.
It is independent of color depth and extended mode. It stores two bits per
character cell, ordered left to right, then top to bottom. Each byte holds four
cells, starting at its lowest two bits; unused high bits in the last byte are zero.

| Value | Meaning |
| --- | --- |
| 0 | Both halves opaque |
| 1 | Upper half transparent |
| 2 | Lower half transparent |
| 3 | Whole cell transparent |

Use cell coordinates with `image:getMask(x,y)` and
`image:setMask(x,y,value)`. The setter returns true or `false,error`; the getter
returns the value or `nil,error` for invalid coordinates. Setting a nonzero value
creates an opaque mask for the other cells and unloads any preloaded buffer.
Setting zero restores opacity without changing the stored colors. Set
`image.mask=nil` to remove the whole mask and save in the older layout again.

```lua
assert(image:setMask(1,1,3)) -- leave the destination cell untouched
assert(image:setMask(2,1,1)) -- show only this cell's lower pixel
assert(image:save("/home/sprite.tmg"))
```

Fully transparent cells issue no pixel writes or destination reads. Half-transparent
cells read the destination while rendering, including changes queued earlier in
the same frame. Half-blocks, full blocks and spaces supply exact background
halves. Over other destination characters, the preserved half uses that cell's
background color; arbitrary text cannot be preserved as independent half-pixels.

Extended images support whole-cell transparency for any character. Half-cell
transparency requires the source character to be `▀`, `▄`, `█` or a space;
other source characters with mask values 1/2 are rejected. Transparent images
require TGL's renderer with custom command support; older renderer fallback
remains available for opaque images.

Draw the background before a transparent image. Making a previously visible pixel
transparent does not erase its old drawing; the area needs to be repainted from
the background, as LTDE's compositor does.

The binary file layout is:

```text
tmg\n
<flags byte>\n
<name>\n
<width in cells>\n
<height in cells>\n
<optional mask><image payload>
```

Flag `0x10` indicates a mask of exactly `(width*height+3)//4` bytes. There is no
separator after the mask: it may contain any byte, including NUL and newline.
The mask is uncompressed. Existing RLE/Diff flags apply only to the image payload.
Malformed mask lengths and nonzero padding bits are rejected.

`tmg.collectFlags(depth,rle,diff,extended,transparency?)` accepts the new optional
flag. `tmg.getFlags(byte)` returns `depth,rle,diff,extended,transparency`, keeping
its original first four return values.

## Python converter

Colors are matched against the entire selected palette using Oklab perceptual
distance. In 8-bit mode, gray shades are considered for all input colors,
including beige and near-neutral tones. Exact palette colors retain their indices.
This changes color selection without changing TMG's palette or file format.
Palette conversions are precomputed and repeated source-color matches are cached.
The conversion follows [Bjorn Ottosson's Oklab equations](https://bottosson.github.io/posts/oklab/).

`--color-mode faithful` is the default. `--color-mode legacy` restores the old
independent channel rounding for 8-bit colors and RGB distance for 4-bit colors.
`--color-mode vivid` adds penalties for
losing chroma or shifting hue, so subtle warm colors are less likely to become
gray. The effect fades for near-neutral colors, dark outlines and near-white
highlights. Exact palette colors remain unchanged. Vivid is automatic and uses
no image-specific regions or hand-picked colors; it may choose a brighter or
more saturated match than Faithful.

```sh
python3 misc/tgl-img-converter.py input.png output.tmg --color-mode vivid
python3 misc/tgl-img-converter.py batch input_dir output_dir --color-mode vivid
```

`--vivid-strength` accepts 0-3, default 1. Zero gives Faithful matching; larger
values favor retaining color more strongly. Both named options can accompany
the existing positional settings. The Python API selects them when constructing
`TMGConverter(color_mode="vivid", vivid_strength=1.0)`; use a separate converter
instance for each configuration. Dithering is selected independently of the mode.

The converter reads source alpha and writes the 1.7 mask automatically when a
pixel has alpha below 128. Alpha is reduced to opaque/transparent; there is no
partial blending. Opaque images keep the older layout. Extended mode is optional
and is not needed for transparency.

```sh
python3 misc/tgl-img-converter.py input.png output.tmg
```

The full argument order is:

```text
input output [depth] [name] [rle] [diff] [extended] [transparency] [alpha_threshold]
batch input_dir output_dir [depth] [rle] [diff] [extended] [transparency] [alpha_threshold]
```

When both compression settings are omitted, the converter compares uncompressed,
RLE, Diff, and Diff followed by RLE, then writes the smallest payload. It keeps
uncompressed data when compression would not save space. This is lossless and
applies to single-file and batch conversion.

Explicit `rle`/`diff` settings override the default; an omitted partner is treated
as `0`. Use `0 0` to disable compression or `1 0` for RLE alone. Setting either
one to `auto` requests automatic selection across all methods. In the Python API,
both default to `None` for automatic selection; explicit booleans select methods.

`transparency` is `auto` (default), `1` to force a mask, or `0` to ignore alpha.
`alpha_threshold` is an integer from 0 to 255, default 128; alpha below it is
transparent, and alpha equal to it is opaque. The mask remains uncompressed
regardless of the selected image compression.

With a mask, an odd image height gets a transparent lower half in the final row.
Without a mask, the existing black padding is kept. Both single-file and batch
conversion accept the same transparency settings. The Python API exposes them as
the optional `transparency="auto"` and `alpha_threshold=128` arguments to
`process_image` and `batch_convert`.

Add `--dither` for serpentine Floyd-Steinberg error diffusion in linear RGB.
It works with any color mode and depth. Transparent pixels do not contribute
color errors to their neighbors. Dithering is off by default.

Add `--preview` to save `output.preview.png` beside the TMG. The preview compares
Original, Legacy, Faithful and Vivid, using the same depth, Vivid strength,
transparency settings and dithering option. An asterisk marks the mode used for
the TMG output. Batch conversion creates a preview beside each converted file.
Transparent areas appear over white; the preview uses palette colors rather
than simulating the GPU's final color reduction on a lower-tier display.

```sh
python3 misc/tgl-img-converter.py input.png output.tmg --preview
python3 misc/tgl-img-converter.py input.png output.tmg --color-mode vivid --vivid-strength 0.5 --dither --preview
```

The Python API accepts `dither=False, preview=False` in `process_image` and
`batch_convert`. Preview generation leaves the selected TMG pixels unchanged.

## Console viewer

For a small Python desktop viewer, run:

```sh
python3 misc/tgl-img-viewer.py picture.tmg
```

It needs Pillow and Tkinter. Open also works without a filename; Ctrl+O opens
another file. The zoom selector and keys 1/2/4/8 change the display scale, and
scrollbars let you pan larger images. Transparent pixels show a checkerboard.
Escape closes the window.

It reads older images and 1.7 masks, both color depths and all compression modes.
Extended cells use an 8x16 desktop font approximation; block shapes are drawn
directly. Ordinary images retain their original pixel dimensions. The 4-bit
palette matches the converter's Tier 2 palette.

To export a PNG without a desktop session or Tkinter:

```sh
python3 misc/tgl-img-viewer.py picture.tmg --export picture.png
```

PNG export preserves transparency and does not include the checkerboard or GUI zoom.

`/usr/bin/tmgview.lua` displays a file until a key is pressed. It flushes image
drawing before waiting, unloads the image afterward, and stops its standalone
renderer timer. Repeated runs restart that renderer as needed. It does not open
a second file handle just to check whether the path exists.

With tgl-img 1.7, masked images render in both normal and inline modes. Normal
mode shows transparency over the cleared terminal background; inline mode
composites over the existing screen content, subject to the half-cell limits above.

Use `tmgview --inline /home/picture.tmg` (or `-i`) to draw at the current
cursor without clearing the screen or waiting for a key. It leaves the cursor
below the image and prints no image stats. Output scrolls up when needed;
images wider or taller than the screen are clipped, leaving a row for the
shell prompt. Terminal colors are restored after drawing.

When LTDE shuts down, it removes the cached `tgl-img` module along with TGL and
tgl-ui. These add-ons hold their TGL instance; retaining an old one would send
later console drawing to the renderer that LTDE already stopped.
