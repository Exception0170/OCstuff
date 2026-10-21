--env: crash slog
slog.log("Core starting..","core")
local computer=require("computer")
local event=require("event")
local thread=require("thread")
local tgl=require("tgl")
local fs=require("filesystem")

_G._ltde_version="release build v1.0.2110"

---Load a system file, BSOD on failure
local function loadsys(path)
  os.sleep(0)
  local f,err=loadfile(path)
  if not f then crash.bsod(crash.err.loadfail,"failed to load "..path,debug.traceback(),err) end
  return f
end

local prmgr=loadsys("/ltde/sys/slib/prmgr.lua")()
---give runctl access to slog
local renv=setmetatable({slog=slog},{__index=_G})
local runctl=loadfile("/ltde/sys/runctl.lua","t",renv)()
if not runctl then crash.bsod(crash.err.loadfail,"runctl returned nil",debug.traceback(),nil) end
slog.log("prmgr + runctl loaded","core")

local cfglib=loadsys("/ltde/sys/cfglib.lua")()
_G.cfglib=cfglib
_G.ltcfg=cfglib.loadDir("/ltde/cfg")
_G.ltfiletypes=loadsys("/ltde/sys/slib/ltfiletypes.lua")()
slog.log("Config loaded","core")

local _corecfg=_G.ltcfg.core
local _fps          =(_corecfg and _corecfg:get("system","renderer_fps",20))    or 20
local _splashOn     =(_corecfg and _corecfg:get("splash","enabled",true))
local _splashDelay  =(_corecfg and _corecfg:get("splash","delay",0.25))         or 0.25
local _memCheck     =(_corecfg and _corecfg:get("system","memory_check",true))
local _memWarnBytes =((_corecfg and _corecfg:get("system","memory_warn_kb",48)) or 48)*1024
local _memCritBytes =((_corecfg and _corecfg:get("system","memory_critical_kb",16)) or 16)*1024
if _splashOn==nil then _splashOn=true end
if _memCheck==nil then _memCheck=true end

tgl.Renderer:init(1/_fps)
tgl.sys.renderer:start()
slog.log("Renderer started","core")

local wallCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.cyan)
do
  local display=_G.ltcfg.display
  if display then
    local name=display:get("","wallpaper","cyan")
    local col=tgl.defaults.colors16[name]
    if col then wallCol=tgl.Color2:new(0xFFFFFF,col) end
  end
end

local splashLib=loadsys("/ltde/sys/splash.lua")()
if _splashOn then splashLib.showStartup(wallCol,_splashDelay) end
splashLib.setStatus("Renderer ready",0.15)
slog.log("Splash shown","core")

local ltwmLib=loadsys("/ltde/sys/ltwm.lua")()
ltwmLib.WindowManager:new()
do
  local display=_G.ltcfg.display
  if display then
    tgl.sys.wm._dragCursor=display:get("","drag_cursor","+")
  end
end
splashLib.setStatus("Window manager ready",0.35)
slog.log("LTWM initialized","core")

local ltassoc=loadsys("/ltde/sys/slib/ltassoc.lua")()
_G._ltde_associations=ltassoc.scan(_G.ltcfg.associations)
splashLib.setStatus("File associations loaded",0.50)

local ltwapi=loadsys("/ltde/sys/slib/ltwapi.lua")()
local ltnotify=loadsys("/ltde/sys/ltnotify.lua")()
ltnotify.start()
local ltevent=loadsys("/ltde/sys/slib/ltevent.lua")()
_G.ltwapi=ltwapi
_G.ltnotify=ltnotify
_G.ltevent=ltevent
_G.ltde_launch=function(appRoot,perms,args) return runctl.launch(appRoot,perms,args) end
local services=loadsys("/ltde/sys/services.lua")()(runctl,_G.ltcfg.services)
_G.ltproc=loadsys("/ltde/sys/slib/ltproc.lua")()(runctl,prmgr,services)
local cmdProcessor=loadsys("/ltde/sys/cmd.lua")()
_G.ltcmd=loadsys("/ltde/sys/slib/ltcmd.lua")()(cmdProcessor,{
  permissions=prmgr,
  terminate=_G.ltproc.terminate,
  caller=function()
    local pid=_G._ltde_co_pid and _G._ltde_co_pid[coroutine.running()]
    return pid and runctl.programs[pid] or nil
  end,
  launch=function(path,args) return runctl.launch(path,nil,args) end,
  programs=function()
    local list={}
    for _,prog in pairs(runctl.programs) do
      table.insert(list,{id=prog.id,name=prog.name,running=prog.running})
    end
    return list
  end,
  dialog=ltnotify.dialog,
  notify=ltnotify.notify,
  warn=ltnotify.warn,
  error=ltnotify.error
})
local ltuiLib=require("tgl-ui")
_G.ltui=ltuiLib
splashLib.setStatus("System services loaded",0.70)
slog.log("ltwapi + ltnotify + ltevent + ltui loaded","core")

-- Keep the startup screen until all desktop services are ready.
local sw,sh=tgl.defaults.screenSizeX,tgl.defaults.screenSizeY
tgl.sys.wm:setBackground(wallCol)

--taskbar
local taskbarLib=loadsys("/ltde/sys/taskbar.lua")()
taskbarLib.init(tgl.sys.wm)
_G.ltde_taskbar=taskbarLib
slog.log("Taskbar initialized","core")
splashLib.setStatus("Taskbar ready",0.85)

--start menu
local startmenuLib=loadsys("/ltde/sys/startmenu.lua")()
startmenuLib.init(tgl.sys.wm)
slog.log("Start menu initialized","core")
local serviceErrors=services.init()
for _,err in ipairs(serviceErrors) do slog.log("Service startup: "..err,"core",2) end
splashLib.setStatus("Desktop ready",1)
splashLib.finishStartup()
tgl.sys.wm:renderRegions({tgl.Size2:new(1,1,sw,sh)})

local running=true
local coreError=nil
local _memCritStamp=-1
local _shutdownMode="exit"

local function onAppExit(id)
  slog.log("App exited: "..tostring(id),"core")
end

local function writeCrashLog(name,pid,traceback)
  local dir="/ltde/logs/crashlogs"
  if not fs.isDirectory(dir) then fs.makeDirectory(dir) end
  local stamp=os.date("%d-%m-%y_%H-%M-%S")
  local safeName=tostring(name):gsub("[^%w%-]","_")
  local path=dir.."/"..stamp.."_"..safeName..".log"
  local f=io.open(path,"w")
  if f then
    f:write("LTDE App Crash Report\n")
    f:write("App:  "..tostring(name).."\n")
    f:write("PID:  "..tostring(pid).."\n")
    f:write("Time: "..os.date("%d-%m-%Y %H:%M:%S").."\n")
    f:write("\n")
    f:write(tostring(traceback).."\n")
    f:close()
  end
  return path
end

local function onAppCrash(name,pid,traceback)
  slog.log("App crash: "..tostring(name).."("..tostring(pid)..") - "..tostring(traceback),"core",2)
  local logPath=writeCrashLog(name,pid,traceback)
  local errLine=tostring(traceback or "unknown error"):match("([^\n]+)") or "unknown error"
  computer.beep(1500,0.08) computer.beep(1500,0.08)
  local chosen=ltnotify.dialog(
    tostring(name or "Application").." crashed",
    errLine,
    {"OK","View log"},nil,
    {text="⛔",color=tgl.defaults.colors16.red}
  )
  if chosen=="View log" and logPath then
    runctl.launch("/ltde/apps/notepad.app",nil,{logPath})
  end
end

local function onShutdownRequest()
  slog.log("Shutdown requested","core")
  _shutdownMode="exit"
  running=false
end

local function onComputerPoweroff()
  slog.log("Computer poweroff requested","core")
  _shutdownMode="poweroff"
  running=false
end

local function onComputerRestart()
  slog.log("Computer restart requested","core")
  _shutdownMode="restart_pc"
  running=false
end

local function onRestartLtde()
  slog.log("LTDE restart requested","core")
  _shutdownMode="restart_ltde"
  running=false
end

local function shutdown()
  slog.log("Shutdown sequence","core")
  -- Cancel all timer-based renders FIRST so nothing overwrites the shutdown screen
  services.cleanup()
  ltnotify.cleanup()
  startmenuLib.cleanup()
  taskbarLib.cleanup()
  -- Detach windows before drawing the final screen; keep GPU resources alive
  -- until programs have finished their shutdown work.
  tgl.sys.wm:cleanup()
  splashLib.showShutdown()
  runctl.shutdown(5)
  tgl.sys.renderer:finish()
  -- Clear all globals LTDE injected so the shell gets a clean environment
  _G._ltde_version=nil
  _G.ltwapi=nil
  _G._ltde_associations=nil
  _G._ltde_fileClipboard=nil
  _G.ltnotify=nil
  _G.ltevent=nil
  _G.ltui=nil
  _G.ltde_launch=nil
  _G.ltcmd=nil
  _G.ltproc=nil
  _G.ltde_taskbar=nil
  _G.ltfiletypes=nil
  _G.ltcfg=nil
  _G.cfglib=nil
  _G._ltde_running_pid=nil
  _G._ltde_co_pid=nil
  -- Graphics add-ons capture the TGL instance, including its renderer.
  package.loaded["tgl-img"]=nil
  package.loaded["tgl-ui"]=nil
  package.loaded["tgl"]=nil
  slog.log("Done","core")
  slog.exit()
  -- Log flushing can take time on disk; clear only when ready to return.
  require("term").clear()
end

local function onOpenApp(appPath)
  if not appPath then return end
  slog.log("Opening: "..tostring(appPath),"core")
  local prog,err=runctl.launch(appPath)
  if not prog then
    slog.log("Launch failed: "..tostring(appPath),"core",2)
    local appName=tostring(appPath):match("([^/]+)%.app$") or tostring(appPath)
    ltnotify.error("Failed to launch "..appName, tostring(err or "unknown error"))
  end
end

local function coreLoop()
  slog.log("Started core loop","core_thread")
  local success,err=pcall(function()
    local _lastMemCheck=0
    while running do
      local id,a,b,c=event.pull(1)
      if _memCheck then
        local now=computer.uptime()
        if now-_lastMemCheck>=10 then
          _lastMemCheck=now
          local free=computer.freeMemory()
          if free<_memCritBytes then
            coreError="low_memory"
            _memCritStamp=free
            running=false
          elseif free<_memWarnBytes then
            ltnotify.warn("Low Memory",math.floor(free/1024).."KB free")
          end
        end
      end
      if id=="ltde_app_exit" then onAppExit(a)
      elseif id=="ltde_app_crash" then onAppCrash(a,b,c)
      elseif id=="ltde_shutdown_request" then onShutdownRequest()
      elseif id=="ltde_computer_poweroff" then onComputerPoweroff()
      elseif id=="ltde_computer_restart" then onComputerRestart()
      elseif id=="ltde_restart_ltde" then onRestartLtde()
      elseif id=="ltde_open_app" then onOpenApp(a)
      end
    end
  end)
  if not success then
    slog.log("Core error caught: "..tostring(err),"core_thread",1)
    if err=="interrupted" then
      slog.log("CTRL+ALT+C handled","core")
      return coreLoop()
    else
      slog.log("panic: unhandled core error","core_thread",2)
      coreError=err
    end
  end
end

slog.log("Started core","core")
local core_thread=thread.create(coreLoop)
while core_thread:status()~="dead" do
  os.sleep(0.05)
end

if coreError then
  slog.log(coreError,2)
  shutdown()
  if coreError=="low_memory" then
    crash.bsod(crash.err.core_low_mem,nil,debug.traceback(),
      "Free Mempry at the time of crash: "..math.floor(_memCritStamp/1024).."KB")
  else
    crash.bsod(crash.err.core_crash,"Core process crashed",debug.traceback(),coreError)
  end
  return
end

shutdown()

if _shutdownMode=="poweroff" then
  computer.shutdown(false)
elseif _shutdownMode=="restart_pc" then
  computer.shutdown(true)
elseif _shutdownMode=="restart_ltde" then
  tgl.sys.renderer=nil  -- force Renderer:init() to create a fresh instance
  loadfile("/ltde/sys/init.lua")()
end
--returns to init.lua, which returns to shell
