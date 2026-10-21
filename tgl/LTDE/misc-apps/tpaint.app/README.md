# TPaint

An optional TMG paint app for LTDEv1. Requires TGLv9 and tgl-img 1.7.
Copy the whole `tpaint.app` folder into `/ltde/apps` and restart LTDE.
Open it from Start, or use `run tpaint.app /home/picture.tmg` in CMD.
Image Viewer keeps the `.tmg` file association.

The window fits a Tier 2 desktop. The canvas shows each image pixel as two
columns and one row, making pixels square and letting you edit the top and
bottom halves of a TMG character cell separately.

- Pen and Eraser draw while dragging. With transparency enabled, Eraser clears
  individual pixels with either mouse button. Otherwise it uses the right color.
- Transparent pixels have a gray stippled preview. Drawing restores opacity;
  Fill treats transparent regions separately from the colors hidden underneath.
- Line, Rect and Circle start on press and finish on release. Rect and Circle
  draw outlines; Circle uses the dragged bounding box and can draw ellipses.
- Hold Ctrl while dragging Rect or Circle for a square or round circle.
  Both dimensions follow the longer drag distance, limited by the image edges.
- Fill replaces the connected area under the pointer with the chosen color.
- Pick (I) samples the clicked pixel. Left/right click sets the left/right color.
  Transparent pixels are ignored. Picking does not modify the image or undo history.
- Click a palette swatch with either mouse button to choose that button's color.
- Tools and the 16-color palette occupy two toolbar rows. The selected tool
  has a blue background.
- Click the L/R hex fields to enter a custom color for that mouse button.
  `[+]` and empty custom swatches also open the color prompt; right-click them
  to set the right color. Six custom swatches are kept for the current session.
  New colors cycle through these slots when they are full.
- Enter six hex digits, optionally prefixed with `#` or `0x`. The displayed
  value is the nearest color in the GPU's 256-color palette.
- Wheel scrolls vertically; Shift+wheel scrolls horizontally. Arrow keys pan.
  The scrollbar and `[<]`, `[>]`, `[0]` buttons also pan or return to the top
  left. These buttons share a one-row footer with the image status.
- File has New, Open, Save and Save as. New images use the 16-color format.
  Width can be 1-256 pixels; height must be an even number from 2 to 256.
- Edit > Undo reverses strokes, fills and shapes. Up to 16 steps are kept,
  limited to 128 KiB of image history. Larger images keep fewer steps.
- Edit > Rename changes the picture name stored inside the TMG file.
  Save to write it to disk. Renaming can be undone and keeps the same filename.
- Edit > Clear all clears the whole image to transparency when enabled,
  otherwise to the right color. It can be undone in one step.
- Edit > Clear background makes exact white (`#FFFFFF`) regions connected to
  any image edge transparent. It follows horizontal/vertical neighbors through
  white or already transparent pixels, leaving enclosed white areas intact.
  Transparency is enabled only if pixels are removed. Undo restores the change.
- Edit > Force transparency adds a mask without clearing existing pixels.
  Force 8-bit converts the colors; Force extended stores a half-block character
  with each cell. Enabled formats have an `[x]` beside their menu entries.
  These actions enable the format; Undo can reverse them. All format and mask
  changes participate in dirty state and undo history. Masks count toward the
  history memory limit too.

Keyboard shortcuts are also listed under Help > Keybindings (F1).

| Keys | Action |
| --- | --- |
| P, E, L, R, C, F | Pen, eraser, line, rectangle, circle, fill |
| I | Color picker |
| X | Swap left and right colors |
| D | Reset colors to black and white |
| K / Shift+K | Enter a left/right custom color |
| Ctrl+N / Ctrl+O | New / open |
| Ctrl+S / Ctrl+Shift+S | Save / save as |
| Ctrl+Z | Undo |
| Ctrl+drag | Square / round circle |
| Ctrl+W / Alt+F4 | Close, checking unsaved work |
| Arrows / Shift+arrows | Pan 1 / 8 pixels |
| Page Up / Page Down | Pan one canvas height |
| Home / Ctrl+Home | Return to top left |
| Esc | Cancel the current stroke |
| F1 | Show keybindings |

Closing, creating or opening an image asks about unsaved work. Saving failures
leave the document modified. Painting a custom color outside the 16-color
palette converts a 4-bit image to 8-bit. Undo restores both the pixels and the
previous depth. Choosing a color alone does not modify the image.
Extended images made of half-blocks, full blocks and spaces can be edited as
pixels. They are normalized to upper half-blocks with the same pixel colors.
Custom character artwork and images larger than 256x256 pixels are rejected
without replacing your work. There is no character brush yet.

There is no text tool, selection or clipboard editing yet.
