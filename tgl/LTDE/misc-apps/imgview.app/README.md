# Image Viewer

A small TMG viewer for LTDEv1. Requires TGLv9 and tgl-img 1.6 or later.

Copy `imgview.app` into `/ltde/apps` and restart LTDE to register its `.tmg`
association. Then double-click an image in Explorer, open Image Viewer from
Start, or run `run imgview.app /home/picture.tmg` in CMD.

File > Open accepts an image path. View > Image info shows its dimensions,
color depth and character mode. Images are displayed at actual size.

The footer uses two rows: image size and viewport position in pixels, followed
by the navigation buttons. Color depth, character mode and transparency status
are shown in Image info. With tgl-img 1.7, transparent areas show the canvas
background.

Edit > Rename changes the picture name stored inside the TMG file and saves
it immediately. The filename stays the same.

View offers 16x16, 32x32, 64x32 and 180x80 image-area presets, in pixels.
Each character cell is two pixels tall, so 32x32 uses 32 columns and 16 rows.
The window stays inside the desktop; on smaller screens the image area is
capped to fit. Changing the preset keeps your scroll position where possible.
Opening a file selects the smallest preset that fits it, or the largest one
if the image exceeds every preset.

View > Custom size accepts `WIDTHxHEIGHT`, such as `40x24`. Width must be at
least 16 pixels and height at least 2; both must be whole numbers within the
screen limits shown in the prompt. Odd heights round up to a full character
row. Empty input keeps the current size. Opening another file selects a
preset again.

- Arrow keys move by one cell; Page Up/Down move by a viewport height.
- Mouse wheel scrolls vertically over the image; Shift+wheel scrolls horizontally.
- Bottom buttons also scroll. Home or Top left returns to the start.
- The vertical scrollbar can be dragged.

The app draws only the visible region and disables automatic full-image
preloading to keep memory use down on 1 MB machines. Presets resize the window,
not the image. There is no zoom or pixel editing in this first version.
