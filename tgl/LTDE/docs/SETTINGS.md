# Settings pages

Control Panel uses registered page definitions and the `ltsettings` library.
For the controls visible in the app, see [Using the apps](USING_APPS.md#control-panel).

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
