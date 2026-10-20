# How LTDE works

LTDE runs inside OpenOS. Its core, apps and background programs share the same
Lua machine. Apps run in OpenOS threads; a separate operating system process is
not created for each window.

## Files

| Path | Purpose |
| --- | --- |
| `/usr/bin/ltde.lua` | Checks the graphics libraries and starts LTDE |
| `/usr/lib/tgl/` | TGL objects, renderer, defaults and helpers |
| `/usr/lib/tgl-ui.lua` | Additional UI controls |
| `/usr/lib/tgl-img.lua` | Image support |
| `/ltde/sys/init.lua` | Startup checks and top-level crash handling |
| `/ltde/sys/core.lua` | Initializes the desktop and handles system events |
| `/ltde/sys/ltwm.lua` | Window records, focus, stacking and composition |
| `/ltde/sys/runctl.lua` | App loading, threads and process cleanup |
| `/ltde/sys/slib/` | App APIs and shared helpers |
| `/ltde/sys/settings/` | Control Panel page definitions |
| `/ltde/sys/cmd/` | Native CMD command modules |
| `/ltde/apps/` | Application bundles |
| `/ltde/services/` | Background service bundles |
| `/ltde/cfg/` | System settings |
| `/ltde/logs/` | Session and crash logs |

## Startup

`ltde` loads TGL and tgl-ui, then runs `init.lua`. Init starts the log, optionally
checks required system files, checks for at least 1 MB RAM, and loads the core.
A failed core load or an unhandled core error goes through the crash handler.

The core creates runctl and the permission helpers, loads the `.conf` files into
`ltcfg`, and starts the renderer. It sets the desktop background, creates the
window manager, and builds the file-association table from app manifests and
configuration overrides.

Next it exposes the app APIs, initializes the service manager and command
processor, and creates the taskbar and Start menu. Configured services start
before the startup splash closes. The desktop is then composed on screen.

## Who owns what

TGL owns UI objects and GPU drawing. The window manager owns placement, focus and
the order in which windows are drawn. `ltwapi` builds the title bar and other
window controls around a TGL Frame. Apps keep their content objects and update
them as events arrive.

Runctl owns each app's thread and PID. The core exposes an app-launch function;
Start and CMD use it rather than creating application threads themselves. The
window API looks up the current coroutine's PID and attaches new windows to it.
That lets runctl close all remaining windows when an app exits or crashes.

The taskbar, Start menu, notification expiry and service polling belong to the
core. They do not depend on a particular app remaining alive.

## Core events

| Event | Core action |
| --- | --- |
| `ltde_open_app, path` | Launch the app bundle |
| `ltde_app_exit, pid` | Log the app's exit |
| `ltde_app_crash, name, pid, traceback` | Save a crash report and show a dialog |
| `ltde_shutdown_request` | Exit to OpenOS |
| `ltde_restart_ltde` | Shut down this session, then run init again |
| `ltde_computer_poweroff` | Shut down LTDE, then power off |
| `ltde_computer_restart` | Shut down LTDE, then reboot the computer |

These are shared OpenOS events, not private messages with enforced senders.
The core also checks free memory periodically when memory monitoring is enabled.

## Shutdown

The core cancels its service/notification timers and removes the Start menu and
taskbar. It detaches managed windows and shows the shutdown screen. Runctl sends
`ltde_shutdown` to programs, waits up to five seconds, and terminates any that
remain.

The renderer then stops, allocated GPU buffers are released, LTDE's globals and
cached TGL modules are cleared, and the log closes. The screen is cleared before
returning to OpenOS or performing the selected power action.

Errors in an app normally end that app and produce a report in
`/ltde/logs/crashlogs`. Errors in the core end the desktop session. Ordinary logs
and error reports remain available even though debug logging is disabled.
