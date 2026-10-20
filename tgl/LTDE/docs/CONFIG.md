# Configuration API

LTDE supplies `cfglib` directly to app environments, like `ltwapi`.
The implementation stays at `/ltde/sys/cfglib.lua`; no OpenOS library
installation or `require` call is needed. Restart LTDE after updating.

## App configuration

In a sandboxed app, relative paths resolve inside that app's bundle:

```lua
local cfg,err=cfglib.load("prefs.conf")
if not cfg then error(err) end
local width=cfg:get("editor","width",40)
cfg:set("editor","width",60)
local ok,err=cfg:save()
if not ok then error(err) end
```

To create a new configuration:

```lua
local cfg=cfglib.new()
cfg:set("editor","width",40)
local ok,err=cfg:save("prefs.conf")
```

Creating a new object does not create directories. Use the app's `filesystem`
API to create a config subdirectory if needed. A newly created object has no
remembered path; pass the path on each save, or load the saved file afterward.

## Access rules

- **System mode:** full config access, including `/ltde/cfg` and shared `ltcfg`.
  Relative paths follow OpenOS's working directory; use an absolute app path
  when loading app-owned settings from system-mode code.
- **Sandboxed:** private config-library instance and filesystem policy. Paths
  normally stay inside the app folder. `fullDiskIO` permits other locations,
  but does not grant access to `/ltde/cfg`.
- System-config read/write access is checked again for each load/save, including
  an explicit save destination or an altered object's `_path`.
- Symbolic-link paths are rejected. Alternate mounts of the system config tree
  are also blocked, as are mutations of parent directories that contain it.
- Sandboxed component access cannot directly invoke/proxy filesystem components;
  use the restricted filesystem API. Other exposed component methods remain
  available according to `componentAccess`.
- `noSandbox` alone no longer selects global execution: the manifest must declare
  `mode="system"`. The system-app trust model and the broader sandbox/event bus
  still need the planned LTDEv2 work; this is not a claim of a fully secure sandbox.

Sandboxed apps receive a private `cfglib` global. System-mode apps receive
the full library. The system `ltcfg` cache is not injected into sandboxed
environments.

## API reference

- `cfglib.new()` -> empty config object.
- `cfglib.load(path)` -> object or `nil,error`.
- `cfglib.loadDir(path)` -> table keyed by `.conf` filename without extension.
  Access violations from directory operations can raise errors; use `pcall`.
- `cfg:get(section,key,default)` -> value or fallback.
- `cfg:set(section,key,value)` -> update in memory.
- `cfg:save(path?)` -> true or `false,error`; flushes and checks write errors.
- `cfg:sections()` -> named sections (excluding the root section).
- `cfg:keys(section)` -> keys in file/insertion order.
- `cfg:meta(section,key)` -> `{display,desc}` or nil.

Use `""` for the root section. Values parse as booleans, decimal/hex numbers, or
strings. `#` comments and `#: Label | Description` metadata are supported.
Ordinary comments are not preserved when saving. These direct saves do not use
the Control Panel's temporary-file replacement mechanism.

Configurations loaded by apps are independent objects. There is no file watcher
or automatic merge into `ltcfg`; saving a file does not automatically update its
running consumers. Shared system files remain loaded at startup into `ltcfg`.

### Shared file colors

`/ltde/cfg/filetypes.conf` supplies optional foreground overrides for Explorer
and CMD `dir` (including `ls` and bare listings):

```ini
[types]
directory=darkblue
app=gold

[extensions]
lua=darkgreen
tmg=purple
```

Use `tgl.defaults.colors16` names or RGB numbers such as `0xFFCC33`.
Extension matching is case insensitive. `.app` entries take precedence over
normal directories. Unlisted or invalid values leave the app's default color;
selection colors still take priority. CMD colors only names and writes plain
text when redirected.

System-mode apps can call `ltfiletypes.color(path, isDir)` for an RGB value or
`nil`. The optional directory flag avoids a filesystem lookup when the caller
already knows the entry type. Apps choose their own background and fallback.
`ltfiletypes.reload()` rereads the file and updates the shared config cache;
it returns `true` or `nil, error`, retaining the old config on failure.
Control Panel edits update that cache directly. Changes appear on the next
Explorer refresh or directory listing. This global does not grant sandboxed
apps access to system config files.
