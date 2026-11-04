# TGLv10 installation and migration

The current version is `0.10.0`. Development continues alongside LTDEv2;
this version number does not mark a published release. The version comes from `usr/lib/tgl/init.lua`.

## Installation

TGL needs OpenOS, a Lua 5.3 CPU architecture, a GPU and a bound screen. The GPU
must provide the VRAM buffer methods used by the renderer. New graphics features
target Tier 3. A Tier 3 GPU/screen and 2 MB RAM are the emulator test profile;
this is not a measured minimum RAM requirement.

Copy the archive's `usr/lib/tgl/` directory into `/usr/lib/tgl/`. Install
`usr/lib/tgl-ui.lua` and `usr/lib/tgl-img.lua` alongside it for existing programs.
Install the optional `etc/tgl/theme.st` as `/etc/tgl/theme.st` if desired.
Do not mix individual v9 and v10 library files. Restart programs that already
loaded TGL after replacing an installation.

```lua
local tgl=require("tgl")
local theme,err=tgl.sys.loadTheme() -- optional; does not apply automatically
if theme then tgl.theme=theme end
```

This archive contains the library, compatibility modules, optional theme and
documentation. It does not contain LTDE, misc apps or standalone programs.

## Moving from TGLv9

- Coordinates remain character cells, with relative coordinates inside frames.
- CheckBox, RadioButton, Progressbar and DropdownMenu are available on `tgl`.
  The `tgl-ui` names refer to the same classes. Its dialogs, windows and file
  pickers remain separate helpers.
- `tgl.Image` and `tgl.img` load image support on first access. `require("tgl-img")`
  returns `tgl.img`. The TMG format and existing image methods are unchanged.
- Use `tgl.sys.loadTheme(path)` to read a theme and assign the result to
  `tgl.theme` before constructing widgets. Explicit widget colors still win.
- CheckBox defaults to `🗹`/`🗷`. Explicit legacy checked glyphs keep a blank
  unchecked state unless a second glyph is supplied. Progress bars support `▌`.
- Wrong argument types now raise OpenOS `checkArg` errors. Existing range and
  file-error returns remain separate. Repair invalid calls instead of relying
  on silently substituted arguments.
- Frames own their children. `remove()` detaches a child for reuse; `destroy()`
  permanently disposes of it. Use owned `events` scopes for registrations.
- Keyboard/pointer routing is opt-in through `tgl.Input`. Do not add Escape
  actions: Minecraft captures that key. Existing direct input remains available.
- A standalone program should call `tgl.finish()` when exiting. Programs sharing
  an LTDE instance must dispose of their own resources rather than finish TGL.

`tgl_old.lua` was an unused historical implementation and is no longer included.
The v9 branch and Git history retain the older code.

The complete v10 API changes and examples are in `docs/TGLv10.md`; image details
are in `docs/TGL-IMG.md`. The v9 guides remain as historical references.

## Building an archive

From the source tree:

```sh
python3 tools/build-tgl-release.py --output /tmp/tgl-0.10.0.zip
```

The builder reads the source version, writes a zip and adjacent SHA-256 file,
and excludes tests, test reports, `tgl_old`, standalone programs and LTDE.
Lua comments are stripped from the archive by default. Quoted strings, long
strings, token boundaries and line numbers are preserved. Source files remain
unchanged. Use `--keep-comments` for a readable development archive:

```sh
python3 tools/build-tgl-release.py --output /tmp/tgl-readable.zip --keep-comments
```

Stripping reduces installed source size and loading work. Comments are not
retained in compiled Lua code, so it is not a general runtime RAM optimization.
The builder does not change the version, commit files or publish a release.
The LTDEv1 release builder is for LTDEv1; do not use it to package this v10 tree
under an existing LTDEv1 release name.
