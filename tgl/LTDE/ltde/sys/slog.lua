--system log library
local fs=require("filesystem")
local computer=require("computer")
local slog={}
---System log
---@param msg Message
---@param module? Module(defaults to `MAIN`)
---@param crit? Log level. -1=debug, 0=info, 1=warn, 2=error
function slog.log(msg,module,crit)
  if not msg or crit==-1 then return end
  if not module then module="MAIN" end
  if type(crit)~="number" then crit=0 end
  local time=computer.uptime()
  local mins=math.floor(time/60)
  local secs=time%60
  local s=string.format("[%d:%05.2f]",mins,secs)
  s=s.."["..module.."]["
  if crit==-1 then s=s.."DEBUG"
  elseif crit==1 then s=s.."WARN"
  elseif crit==2 then s=s.."ERROR"
  else s=s.."INFO" end
  s=s.."]: "..msg.."\n"
  slog.file:write(s)
end

function slog.exit()
  if slog.file then
    slog.file:close()
  end
  slog.file=nil
end

if not fs.exists("/ltde/logs") then fs.makeDirectory("/ltde/logs") end
if fs.exists("/ltde/logs/latest.log") then
  local file=io.open("/ltde/logs/latest.log")
  if not file then error("couldn't open old logfile!") end
  local last=file:read("*l")
  file:close()
  if not last then last="unknown" end
  local name="/ltde/logs/"..last..".log"
  fs.rename("/ltde/logs/latest.log",name)
end

-- prune archived logs; read log_keep from core.conf the same way init.lua reads chksys
do
  local keepN=10
  local fn=loadfile("/ltde/sys/cfglib.lua")
  if fn then
    local ok,lib=pcall(fn)
    if ok and lib then
      local cfg=lib.load("/ltde/cfg/core.conf")
      if cfg then keepN=cfg:get("system","log_keep",10) end
    end
  end
  if keepN>0 then
    local logs={}
    local iter=fs.list("/ltde/logs")
    if iter then
      for name in iter do
        if name:match("%.log$") and name~="latest.log" then
          local p="/ltde/logs/"..name
          logs[#logs+1]={path=p,t=fs.lastModified(p)}
        end
      end
    end
    table.sort(logs,function(a,b) return a.t<b.t end)
    for i=1,math.max(0,#logs-keepN) do
      fs.remove(logs[i].path)
    end
  end
end

slog.file=io.open("/ltde/logs/latest.log","w")
if not slog.file then error("couldn't open logfile!") end
slog.file:write(os.date("%d-%m-%y_%H-%M\n"))
return slog
