# Writing an LTDE app

An app is a folder under `/ltde/apps`, ending in `.app`. Start discovers its
manifest automatically. A minimal bundle looks like this:

```
/ltde/apps/example.app/
  manifest.lua
  main.lua
```

## Manifest

```lua
return {
  name="Example",
  mode="system",
  opens={"example"}, -- optional file extensions, without the dot
}
```

`name` is the Start-menu label. `opens` registers file types with Explorer;
`opens={"*"}` declares a fallback handler. Users can override associations in
`/ltde/cfg/associations.conf`.

Use system mode for v1 windowed apps. It gives the app access to OpenOS and
LTDE's APIs. This is trusted code with full filesystem/component access; v1's
sandbox scaffolding is not a complete isolation boundary.

## A small window

Put this in `main.lua`:

```lua
local tgl=require("tgl")
local done="example_close_"..tostring(math.random(1,1000000))
local frame,area=ltwapi.addWindow(32,10,"Example",{
  onClose=function() ltevent.push(done) end
})
if not frame then return 1 end

local firstArgument=...
local col=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
frame:add(tgl.Text:new(firstArgument or "Hello!",col,
  tgl.Pos2:new(area.x1+1,area.y1+1)),"message")

local ok,err=pcall(function()
  frame:enableAll()
  local wm=tgl.sys.wm
  local managed=wm:getManagedWindow(frame)
  wm:renderRegions({wm:getWindowBounds(managed)})
  while true do
    local event=ltevent.pull()
    if event==done or event=="ltde_shutdown" then break end
  end
end)
frame:disableAll()
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
```

Run it from Start or CMD:

```
run example.app "Hello from CMD"
```

Arguments arrive as positional Lua varargs (`...`). File associations pass the
opened file path as the first argument.

## Coordinates and drawing

TGL works on a character grid. Controls added to a Frame use coordinates relative
to that frame. `ltwapi.addWindow` returns the window and its content area; use that
area so the title bar or toolbar does not overlap your controls.

Add controls with `frame:add(control, name)` before enabling them. After changing
text or other state, ask the window manager to redraw the window's bounds, as in
the example. This keeps overlapping windows in the correct order. Do not clear
the whole screen to update an app.

TGL provides Text, Button, EventButton, InputField, Frame and ScrollFrame.
`tgl-ui` adds controls such as Progressbar. The bundled apps are larger examples.

## Available APIs

- `ltwapi`: create/close windows, set titles, focus/minimize, menus and file opening.
- `ltevent`: pull events with keyboard/clipboard focus filtering. Use it instead
  of raw OpenOS event pulls for interactive windowed apps.
- `ltnotify`: notifications, warnings, errors, dialogs and text prompts.
- `cfglib`: load and save configs; no `require("cfglib")` is needed.
- `ltcmd`: execute LTDE commands from trusted system apps.
- `ltproc`: process snapshots and lifecycle actions for trusted system apps.
- `ltfiletypes`: optional shared foreground colors for file entries.

`ltcfg` contains the loaded system configs. Prefer an app-owned config file for
app settings. See [Windows](WINDOWS.md), [Processes and permissions](PROCESSES.md),
[Events](EVENTS.md), [Configuration](CONFIG.md) and [CMD](CMD.md) for details.

Use unique event names for each window or app instance. On exit, cancel your
timers, remove your listeners, disable controls and close your windows. Handle
`ltde_shutdown` so shutdown can finish without force-stopping your app.
