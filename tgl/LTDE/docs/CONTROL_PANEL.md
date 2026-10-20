# Control Panel

Open **Control Panel** from Start, or run `run control.app` in CMD.
The window is 60x20, intended for Tier 2 graphics and LTDE's 1 MB RAM minimum.

Select a category on the left, then click a setting to select it and read its
description. Click the selected setting again to edit: checkboxes toggle, while
numbers, paths, and text open an input dialog. Wallpaper colors open a palette of
16 swatches. The selected setting's description appears below the controls.
Only the active page's controls exist at a time.

- **Apply** validates and saves pending changes on all pages, leaving the window open.
- **OK** applies changes and closes the window if saving succeeds.
- **Cancel** and the title-bar close button discard changes since the last Apply.
- A `*` marks settings requiring an LTDE restart. Saving does not restart LTDE.

Appearance includes wallpaper color and the drag cursor (one character cell, or
empty to disable). Both take effect on Apply. Choosing a swatch alone does not
change the desktop.

System includes the default text editor, startup file checks, memory monitoring
and warning/critical thresholds, renderer FPS, log history, and startup splash
settings. The default editor applies immediately; other System settings require
restarting LTDE. The warning threshold must exceed the critical threshold.
The startup splash includes a progress bar driven by completed startup stages;
Startup pause controls one pause at completion; zero adds no startup pause.

## Configuration and page definitions

Values remain in `/ltde/cfg/*.conf`. Display labels and descriptions come from
existing `#: Label | Description` metadata. Internal keys are not automatically
exposed: `/ltde/sys/settings/*.lua` registers the editable pages.

Each file returns a table, for example:

```lua
return {
  id="example",title="Example",config="example",
  fields={
    {section="",key="enabled",label="Enabled",kind="boolean",default=true,restart=true},
    {section="",key="interval",label="Interval",kind="number",default=10,
      min=1,max=60,integer=true,unit="seconds",restart=true}
  }
}
```

The matching configuration file must exist. Pages load in filename order.
Definitions are read in an empty environment and should contain plain data.
The current layout supports up to nine ordinary fields per page and fourteen
categories. Color palettes need their own short page, as in Appearance.

Field kinds:

| Kind | Control and validation |
| --- | --- |
| `boolean` | Checkbox; true/false |
| `number` | Numeric prompt; required `min`/`max`, optional `integer` and `unit` |
| `text` | Single-line prompt; optional `maxWidth` measured in character cells |
| `app` | Absolute application folder containing `manifest.lua` and `main.lua` |
| `color` | Palette from `choices`, using TGL `colors16` names |

`restart=true` displays a restart marker. Built-in `live` actions are `wallpaper`,
`drag_cursor`, and `config` (update the shared loaded configuration). A new setting
that needs a different runtime action also needs an application-side handler;
writing its value alone does not reconfigure a running service.

## Settings library

Load `/ltde/sys/slib/ltsettings.lua` with `loadfile(...)()` in system-mode code.

- `pages()` returns registered definitions, or `nil,error`.
- `new()` returns a session with independent pending values, or `nil,error`.
- `session.pages`, `.values`, and `.original` use one-based page/field indexes.
- `session:set(page,field,value)` validates and stages a value; returns true or `nil,error`.
- `session:dirty()` reports whether there are pending changes.
- `session:apply()` returns `success,error,applied`. Each applied entry contains
  `field` and `value`; the caller performs the corresponding runtime action.

Apply re-reads each changed configuration, preserves unrelated edits, and refuses
to overwrite a changed setting from another session. Saving uses a temporary
file and a backup so failed replacement can restore the original. Write/close
errors are reported. Saving several configuration files is not a single
transaction: if a later file fails, earlier saved changes stay applied and the
error identifies the failure. Cancel does not undo earlier successful Apply calls.

## Ocelot checks

Verify all color swatches, Apply versus Cancel, empty drag cursor, switching pages,
numeric validation, restart reminders, and closing the window with unsaved edits.
Open two Control Panels and try changing the same setting to check conflict
reporting. Check rendering with overlapping windows and listener cleanup on exit.
