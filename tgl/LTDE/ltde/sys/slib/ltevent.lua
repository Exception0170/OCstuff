--focus-aware event wrapper: filters key_down/key_up/clipboard when window is not active
local _ev=require("event")
local computer=require("computer")
local tgl=require("tgl")
local ltevent={}

local _kbd={key_down=true,key_up=true,clipboard=true}

local function focused()
  local wm=tgl.sys.wm
  if not wm then return true end
  local pid=_G._ltde_co_pid and _G._ltde_co_pid[coroutine.running()]
  if not pid then return true end  -- non-app context: don't filter
  local aw=wm.activeWindow
  return aw~=nil and aw.pid==pid
end

---Like event.pull but discards keyboard events when this app's window is not focused.
---Signature mirrors event.pull([timeout,] [filter, ...])
---@return string|nil eventName, ...
function ltevent.pull(...)
  local args={...}
  local deadline=nil
  if type(args[1])=="number" then
    deadline=computer.uptime()+table.remove(args,1)
  end
  while true do
    local rem=deadline and math.max(0,deadline-computer.uptime()) or nil
    if deadline and rem==0 then return nil end
    local res={_ev.pull(rem~=nil and rem or (#args>0 and table.unpack(args) or nil))}
    local evName=res[1]
    if not evName then return nil end
    if _kbd[evName] and not focused() then
      -- discard and loop with remaining time
    else
      return table.unpack(res)
    end
  end
end

---Like event.pullMultiple but discards keyboard events when not focused.
---@return string|nil eventName, ...
function ltevent.pullMultiple(...)
  local filters={...}
  while true do
    local res={_ev.pullMultiple(table.unpack(filters))}
    local evName=res[1]
    if not evName then return nil end
    if _kbd[evName] and not focused() then
      -- discard
    else
      return table.unpack(res)
    end
  end
end

---Pass-throughs for non-keyboard event functions (listen/ignore/timer/cancel).
ltevent.listen=_ev.listen
ltevent.ignore=_ev.ignore
ltevent.timer=_ev.timer
ltevent.cancel=_ev.cancel
ltevent.push=_ev.push

return ltevent
