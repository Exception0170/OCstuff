# LTDE services

Services are background programs managed by `runctl`. They use the same process
execution and cleanup as apps, with a service manager for discovery, startup,
single instances, and stop/restart transitions. Existing core components remain
core-owned; installing this feature does not move the renderer or window manager
into service processes.

## Create a service

Create `/ltde/services/heartbeat.service/manifest.lua`:

```lua
return {
  name="Heartbeat",
  kind="service",
  mode="system",
  protected=false,
}
```

Then create `main.lua`:

```lua
local event=require("event")
local computer=require("computer")
local pid=_G._ltde_co_pid[coroutine.running()]
local nextBeat=computer.uptime()+30
while true do
  local ev,target=event.pull(math.max(0,nextBeat-computer.uptime()))
  if ev=="ltde_shutdown" or (ev=="ltde_service_stop" and target==pid) then break end
  if computer.uptime()>=nextBeat then
    event.push("heartbeat",pid)
    nextBeat=computer.uptime()+30
  end
end
-- Release any listeners, timers, or handles registered by this service here.
```

Restart LTDE to discover newly installed services. They appear in Task Manager
while stopped and can be started manually. The service identifier is the folder
name without `.service`; use letters, digits, underscores, or hyphens.

For automatic startup, edit `/ltde/cfg/services.conf`:

```ini
[startup]
heartbeat=true
```

Only explicitly enabled services start at boot, in identifier order. No optional
services are enabled by default. Failed startup is logged; Task Manager shows
Failed. Automatic crash-restart loops are not enabled.

## Lifecycle

Task Manager provides **Start Service**, **Stop Service**, and **Restart Service**.
Start refuses a duplicate running instance. Stop emits `ltde_service_stop,pid`;
the service must check that the PID matches its own, release resources, and return.
After five seconds, a service that has not returned is forcibly terminated.
Restart uses the same stop path and starts a new instance only after the previous
one exits. LTDE shutdown emits `ltde_shutdown` and stops all processes.

`protected=true` prevents user Stop/Restart operations. Protected services still
stop when LTDE shuts down. This protects desktop operation from accidental clicks;
it is not a security boundary against trusted system-mode Lua code.

Applications cannot use ordinary `run`/`ltde_launch` to start a service manifest;
use Task Manager or the service API so singleton and lifecycle tracking apply.

## API

Trusted system apps with `rootAccess` can call:

```lua
local ok,err=ltproc.service("start","heartbeat")
local ok,err=ltproc.service("stop","heartbeat")
local ok,err=ltproc.service("restart","heartbeat")
```

Stop/Restart return after requesting the transition. Poll `ltproc.list()` to
observe completion. Snapshots now include `kind="application"` or `"service"`.
A service has a stable `id="service:<name>"`, a `serviceId`, a current numeric `pid`
when running, `state`, and `protected`. Stopped services remain in the list.
Application IDs remain numeric. `ltproc.terminate()` refuses services; use their
lifecycle API instead. `ps` includes running services, but not stopped ones.

## Ocelot checks

Install the example, restart LTDE, and test manual Start, Stop, Restart, and boot
startup. Verify duplicate Start is rejected and stopped entries remain visible.
Test an uncooperative service with disposable state to check the five-second
forced-stop fallback. Confirm protected services reject Stop/Restart and that
LTDE shutdown still stops them. Recheck app-crash dialogs and View log.
