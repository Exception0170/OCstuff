# LTDE services

Services are background programs managed by `runctl`. They use the same process
execution and cleanup as apps, with a service manager for discovery, startup,
single instances, and stop/restart transitions. The renderer, window manager and other desktop
components remain core-owned; they are not service processes.

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

Restart LTDE to discover newly installed services. The service identifier is the folder
name without `.service`; use letters, digits, underscores, or hyphens.

For automatic startup, edit `/ltde/cfg/services.conf`:

```ini
[startup]
heartbeat=true
```

Only explicitly enabled services start at boot, in identifier order. No optional
services are enabled by default. Failed startup is logged and recorded as Failed in the service registry.
Automatic crash-restart loops are not enabled.

## Lifecycle

The service manager provides start, stop and restart operations.
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

Stop/Restart return after requesting the transition, not after the service has
finished stopping. The core's service-manager timer checks for exit or timeout.

Inside the core, `services.list()` returns independent service records with
`id="service:<name>"`, `serviceId`, the current `pid` when running, `name`,
`kind="service"`, `running`, `protected` and `state`. Stopped services remain in
that registry. This manager is a core-local object, not an app global.

The current `ltproc.list()` exposes application snapshots only; it does not
merge these service records. Task Manager has service action controls but its
list receives those application snapshots. To start/stop a known service from
system app code, use `ltproc.service`. CMD `ps` obtains its own running-program
snapshot from the core and includes running services.

`ltproc.terminate()` rejects service processes; use their lifecycle API instead.
