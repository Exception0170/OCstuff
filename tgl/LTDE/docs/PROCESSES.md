# Processes and permissions

`/ltde/sys/runctl.lua` manages app and service threads. It is created by the core,
not loaded separately by each app. Runctl's registry is an internal object;
apps use `ltde_launch`, `ltcmd` or `ltproc` where appropriate.

## Launching

```lua
local program,err=ltde_launch("/ltde/apps/notepad.app",nil,{"/home/notes.txt"})
if not program then ltnotify.error("Open failed",err) end
```

The optional second argument is an initial permission bitmask; the third is an
argument array. Apps receive those arguments as `...`. `ltwapi.openFile(path)`
chooses a handler instead of requiring an app path. CMD's `run` command resolves
short app names and forwards its remaining arguments.

Internally, `runctl.launch` creates a Program, loads it and starts it. It returns
the Program or `nil,error`. Service manifests are rejected here: they go through
the service manager so instance and stop/restart tracking apply.

## Program lifecycle

`Program:new(appRoot,perms?,args?)` allocates a monotonically increasing numeric
PID, records the canonical app path and defaults to sandboxed application mode.
It does not start a thread.

`Program:load()` requires `main.lua`, reads `manifest.lua` if present, and applies
`name`, `mode`, `kind` and the named permissions in `perms`. A system app's code
is loaded into the shared global environment. A non-system app's environment is
created at run time.

`Program:run()` registers the program before starting its detached OpenOS thread.
It records `_ltde_co_pid[coroutine.running()]=pid` inside that thread, then calls
the entry point under `xpcall`. An error marks the program failed and emits
`ltde_app_crash`. Returning normally or after an error calls `finish()`.

`finish()` is idempotent. It marks the program stopped, removes it from
`runctl.programs`, clears its coroutine/PID mappings, closes its remaining owned
windows and emits one `ltde_app_exit,pid`. `terminate()` kills its thread and runs
the same cleanup. It cannot promise app save prompts or custom cleanup code.

`Program:signal(name,...)` pushes `name,pid,...` onto the shared event bus. The
PID is a value the receiving code must check; it is not private event delivery.
Runctl shutdown signals all programs, waits for their exit, then force-stops any
still running at the deadline (five seconds by default).

## Window ownership

`ltwapi.addWindow` looks up the calling coroutine in `_ltde_co_pid` and associates
that PID with the window. This supports several windows per app and cleanup on
crash or forced termination.

That mapping is made for the entry thread. A manually created child coroutine
is not automatically registered. Creating windows or calling protected APIs from
an unmapped coroutine can lose ownership or fail caller checks. Keep those calls
in the app entry thread. `_ltde_running_pid` is a shared compatibility global;
it should not be used to determine the caller.

## Permission flags

The bitmask helpers are in `/ltde/sys/slib/prmgr.lua`:

| Name | Bit | Use |
| --- | --- | --- |
| `fullDiskIO` | `0x1` | Broaden restricted filesystem access outside the bundle |
| `runPrograms` | `0x10` | Available for command permission declarations and checks |
| `componentAccess` | `0x100` | Expose a component wrapper in a restricted environment |
| `noSandbox` | `0x1000` | A permission flag; does not select execution mode by itself |
| `rootAccess` | `0x10000` | Required by trusted command/process APIs |

For example:

```lua
local prmgr=assert(loadfile("/ltde/sys/slib/prmgr.lua"))()
local mask=prmgr.grant(0,"runPrograms")
if prmgr.get(mask,"runPrograms") then
  -- The bit is set; the caller still has to enforce its policy.
end
```

`check(mask)` rejects unknown bits. `get(mask,name)` returns a boolean, or nil
for an unknown name. `grant(mask,name)` and `revoke(mask,name)` return a new mask;
they do not change an existing process object by themselves. These are bitmask
utilities, not a central access-control service. Each consumer must make its
own check.

An app declaring `mode="system"` receives `noSandbox`, `rootAccess`,
`fullDiskIO` and `componentAccess` automatically. There is no user approval step
or signed system-app registry. A manifest chooses this mode, so installing a
system app means trusting its Lua code with the machine.

Non-system environments expose a limited set of globals, restricted filesystem
operations, and a private `cfglib`. `fullDiskIO` does not unlock `/ltde/cfg`;
filesystem component calls and link/mount aliases are checked too. Their event
bus is still shared, and they do not have a working isolated window API. Treat
this as limited API scaffolding, not a complete security sandbox.

## Process API for apps

Core exposes `ltproc`:

```lua
local programs,err=ltproc.list()
local ok,err=ltproc.terminate(pid)
local ok,err=ltproc.service("start","heartbeat")
```

Each call resolves the current coroutine's registered Program and requires
system mode plus `rootAccess`. Passing a claimed PID or a fabricated session
table does not establish caller identity.

`list()` returns independent, PID-sorted application snapshots:
`{id,pid,name,kind,running,self}`. It currently excludes service processes;
stopped services are not returned either. Service records are maintained by the
internal service manager; see [Services](SERVICES.md).

`terminate(pid)` returns true or `nil,error`. It refuses the caller's own PID,
missing/stopped programs and services. Confirmation belongs to the calling UI.
Task Manager and CMD's `kill` use this API.

`service(action,id)` accepts `start`, `stop` or `restart` and a service identifier.
It returns true or `nil,error`. Stop/restart can still be in progress when it
returns.
