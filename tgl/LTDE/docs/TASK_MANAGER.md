# Task Manager

Open **Task Manager** from Start, or use `run taskmgr.app` in CMD.
Restart LTDE after installing this update so core loads the new process service.

The 60x20 window lists applications and installed services managed by `runctl`, with their PID, name,
running state, and type (App, Service, or Protected). It includes applications without windows
and Task Manager itself. The list scrolls when more than ten applications run.

- Click a row to select an application.
- **Switch To** focuses its first ordinary window, restoring it if minimized.
- **End Task** asks for confirmation, then forcibly terminates the selected
  application. Unsaved work is lost. Cancel is the default confirmation choice.
- **Refresh** updates the list and memory figures immediately.
- **Close** exits Task Manager. End Task cannot target the calling Task Manager.

Normal exits and forced termination share runctl cleanup: remove the process
entry and coroutine ownership mappings, close its remaining managed windows,
and emit one `ltde_app_exit` event. Forced termination does not run application
save prompts or promise that arbitrary application shutdown code will execute.

RAM reports total computer memory used/free in KB. GPU-buffer memory reports
used/free character cells from the GPU API; unavailable metrics show as such.
These are system totals, not per-application accounting. Running indicates the
runctl state, not a responsiveness test.

Refresh uses the existing event loop with a one-second timeout, without extra
listeners or timers. Selection and scroll position survive automatic refresh.
Unchanged views are not redrawn; memory-only changes redraw the footer. Window
manager composition preserves overlapping windows.

## Process API

Core provides `ltproc` to trusted system applications with `rootAccess`:

```lua
local programs,err=ltproc.list()
local ok,err=ltproc.terminate(pid)
```

`list()` returns a PID-sorted array of independent snapshots:
`{id,pid,name,kind,running,self}` for applications. `self` identifies the calling
application. Services use the extended snapshot described in SERVICES.md.

`terminate(pid)` returns true or `nil,error`. It rejects unauthorized callers,
the caller's own PID, and processes that have already exited. It does not display
a confirmation dialog; the calling UI is responsible for confirmation.

## Ocelot checks

Open several apps, including two instances of the same app. Verify selection,
scrolling, Switch To, and minimized-window restoration. Cancel an End Task prompt,
then terminate an app with disposable unsaved content and check that its windows
and taskbar entries disappear. Close Task Manager and verify event cleanup and
that no button animation remains on the desktop.

Service support: stopped services remain selectable, with Start/Stop/Restart
buttons. See [SERVICES.md](SERVICES.md) for installation, boot configuration,
protected services, graceful stopping, and the extended process snapshot API.
