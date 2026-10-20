local slog=loadfile("/ltde/sys/slog.lua")()
if not slog then error("Couldn't start! /ltde/sys/slog.lua not found") end
slog.log("LTDE system start!","INIT")
local env=setmetatable({},{__index=_G})
env.slog=slog

-- read chksys flag from core.conf; crash.lua isn't loaded yet so fail silently
local _chksys=true
do
  local fn=loadfile("/ltde/sys/cfglib.lua")
  if fn then
    local ok,lib=pcall(fn)
    if ok and lib then
      local cfg=lib.load("/ltde/cfg/core.conf")
      if cfg then _chksys=cfg:get("system","chksys",true) end
    end
  end
end

if _chksys then
  local c,err=loadfile("/ltde/sys/chksys.lua","t",env)
  if not c then
    slog.log("Couldn't load chksys.lua - exiting!","INIT",2)
    error("chksys not found!")
  end
  local success,err=pcall(c)
  if not success then
    slog.log("chksys check failed: "..tostring(err),"INIT",1)
    error("chksys check failed: "..tostring(err),0)
  end
else
  slog.log("chksys skipped (disabled in config)","INIT",1)
end
--load
local crash=loadfile("/ltde/sys/crash.lua")()
env.crash=crash

local computer=require("computer")
if computer.totalMemory()<1024*1024 then
  crash.bsod(crash.err.lowmem,nil,nil,
    "Total RAM: "..math.floor(computer.totalMemory()/1024).."KB (1MB minimum)")
end

local core=loadfile("/ltde/sys/core.lua","t",env)
if not core then
  crash.bsod(crash.err.core_load_fail,nil,debug.traceback(),"Check good, core load returned nil")
end
local success,err=xpcall(core,debug.traceback)
if not success then
  if type(err)=="table" then
    if err["reason"] and err["reason"]=="terminated" then
      slog.exit()
      os.exit(err["code"])
    end
  elseif string.find(tostring(err),"memory") then
    crash.bsod(crash.err.core_low_mem,"Not enough memory",tostring(err),nil)
  else
    crash.bsod(crash.err.core_crash,"panic: core process exited with error",tostring(err),nil)
  end
end
slog.exit()