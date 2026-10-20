# Events and cleanup

LTDE uses the OpenOS event bus. Each app waits for events in its own thread.
Event names and payloads are shared conventions; they are not isolated channels
or permission-checked messages.

## ltevent

Core exposes `ltevent` to system-mode apps. `pull(...)` and `pullMultiple(...)`
wrap OpenOS waits with focus filtering. Keyboard down/up and clipboard events
are discarded by that app's wait when the active window belongs to another PID.

Focus is checked per app, not per window. If an app has several windows, it must
decide which of its own controls handles a key. Unmapped coroutines bypass this
focus check, so use the registered app entry thread for keyboard handling.

```lua
while true do
  local ev,a,b,c=ltevent.pull(1)
  if ev==closeEvent or ev=="ltde_shutdown" then break end
  if ev=="key_down" then
    -- a = keyboard address, b = character code, c = scan code
  elseif ev=="clipboard" then
    -- a = keyboard address, b = pasted text
  elseif ev==nil then
    -- Timed out; update periodic state if needed.
  end
end
```

`pullMultiple(name,...)` applies the same focus filter. Prefer an unfiltered
`pull(timeout)` followed by explicit checks when the loop needs several event
types and a timeout. Non-keyboard events such as touch and scroll are not filtered
by ltevent; controls and app code must check bounds, visibility and overlap.

`listen`, `ignore`, `timer`, `cancel` and `push` are direct OpenOS pass-throughs.
In particular, `ltevent.listen("key_down",handler)` does not gain the focus filter
of `ltevent.pull`.

## Custom events

Give each app instance a unique event prefix:

```lua
local done="example_close_"..tostring(math.random(1,1000000))
local save="example_save_"..tostring(math.random(1,1000000))
```

`tgl.EventButton(label,eventName,value,pos,col)` pushes its event and value when
clicked. The event loop can handle that alongside keyboard input and shutdown.
A window's `onClose` callback should push its close event, allowing the loop to
return rather than leaving a thread waiting for a window that is already gone.

`Program:signal` adds its PID after the event name. Services must compare that
value to their own PID before acting on `ltde_service_stop`. Ordinary shutdown
handlers can simply stop on `ltde_shutdown`.

## Cleanup

Use `frame:disableAll()` and `ltwapi.removeWindow(frame)` when returning from an
app. Pair manual `event.listen` calls with `event.ignore`, timers with
`event.cancel`, and custom modal opens with their closes. Close file handles too.
The app-writing example uses `pcall` so its normal cleanup also runs after an error.

Runctl closes managed windows if an app crashes or is forcibly terminated, but
it does not keep a registry of every arbitrary listener or timer created by app
code. Do not depend on forced termination to perform those app-specific steps.

Keep periodic work in an event-loop timeout when practical. For background
updates, compare state before requesting a redraw. Disabling controls also
cancels their pending click feedback; this prevents a delayed animation from
painting over the window that replaces them.
