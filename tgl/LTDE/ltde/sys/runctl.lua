--env: slog
local fs=require("filesystem")
local thread=require("thread")
local event=require("event")
local computer=require("computer")
local tgl=require("tgl")
local prmgr=loadfile("/ltde/sys/slib/prmgr.lua")()

local runctl={}
---@type table<integer,runctl.Program>
runctl.programs={}
runctl.nextID=0

function runctl.getNextID()
  runctl.nextID=runctl.nextID+1
  return runctl.nextID
end

local fsaccess=assert(loadfile("/ltde/sys/slib/fsaccess.lua"))()
local appconfig=assert(loadfile("/ltde/sys/slib/appconfig.lua"))()

---Generate sandbox environment for a sandboxed app
---@param id integer program id
---@param appRoot string
---@param perms integer
---@return table
function runctl.genEnv(id,appRoot,perms)
  local env={}
  env.table=table
  env.string=string
  env.math=math
  env.pairs=pairs
  env.ipairs=ipairs
  env.next=next
  env.select=select
  env.type=type
  env.tostring=tostring
  env.tonumber=tonumber
  env.unpack=table.unpack
  env.error=error
  env.pcall=pcall
  env.xpcall=xpcall
  env.os={time=os.time,clock=os.clock,sleep=os.sleep}
  env.print=function(...) slog.log(table.concat({...}," "),"app("..tostring(id)..")") end
  env.prmgr=prmgr
  env.ltwapi=nil --Phase 2
  --event: Phase 2 will replace with per-app sandboxed queue
  env.event=event
  local restricted,resolve=fsaccess(appRoot,prmgr.get(perms,"fullDiskIO"))
  env.filesystem=restricted
  env.cfglib=appconfig(restricted,resolve)
  env.require=function(name)
    error("module not available in sandbox: "..tostring(name),2)
  end
  if prmgr.get(perms,"componentAccess") then
    local component=require("component")
    local function allowed(address)
      if component.type(address)=="filesystem" then
        error("use the restricted filesystem API",3)
      end
    end
    local access={list=component.list,type=component.type,slot=component.slot}
    for _,method in ipairs({"invoke","proxy","methods","doc","fields"}) do
      local name=method
      access[name]=function(address,...)
        allowed(address)
        return component[name](address,...)
      end
    end
    env.component=access
  end
  setmetatable(env,{
    __index=function(_,key) error("'"..key.."' not available in sandbox",2) end
  })
  return env
end

---@class runctl.Program
---@field id integer
---@field file string path to main.lua
---@field appRoot string path to .app folder
---@field name string display name
---@field mode string "system"|"sandboxed"
---@field perms integer
---@field running boolean
---@field exitCode integer
---@field thread table|nil
---@field func function|nil loaded function for system mode
runctl.Program={}
runctl.Program.__index=runctl.Program

---@param appRoot string path to .app folder
---@param perms? integer initial permissions (default 0)
---@param args? any[] arguments passed to the app as varargs (...)
---@return runctl.Program
function runctl.Program:new(appRoot,perms,args)
  local obj=setmetatable({},self)
  obj.id=runctl.getNextID()
  obj.appRoot=fs.canonical(appRoot)
  obj.file=fs.concat(obj.appRoot,"main.lua")
  obj.name=obj.appRoot
  obj.mode="sandboxed"
  obj.kind="application"
  obj.perms=perms or 0
  obj.args=args or {}
  obj.running=false
  obj.exitCode=-1
  obj.thread=nil
  obj.func=nil
  return obj
end

---Read manifest.lua and configure program. System apps get full perms silently.
---@return boolean
function runctl.Program:load()
  if not fs.exists(self.file) then
    slog.log("main.lua not found: "..self.file,"runctl",2)
    return false,"main.lua not found"
  end
  local manifestPath=fs.concat(self.appRoot,"manifest.lua")
  if fs.exists(manifestPath) then
    local mf=loadfile(manifestPath)
    if mf then
      local ok,manifest=pcall(mf)
      if ok and type(manifest)=="table" then
        self.name=manifest.name or self.name
        self.kind=manifest.kind=="service" and "service" or "application"
        if manifest.mode then self.mode=manifest.mode end
        if type(manifest.perms)=="table" then
          for _,p in ipairs(manifest.perms) do
            self.perms=prmgr.grant(self.perms,p)
          end
        end
      else
        slog.log("Bad manifest: "..self.appRoot,"runctl",1)
      end
    end
  end
  if self.mode=="system" then
    self.perms=prmgr.grant(self.perms,"noSandbox")
    self.perms=prmgr.grant(self.perms,"rootAccess")
    self.perms=prmgr.grant(self.perms,"fullDiskIO")
    self.perms=prmgr.grant(self.perms,"componentAccess")
    local f,err=loadfile(self.file)
    if not f then
      slog.log("Load failed("..self.id.."): "..tostring(err),"runctl",2)
      return false,tostring(err)
    end
    self.func=f
  end
  slog.log("Loaded: "..self.name.." mode="..self.mode,"runctl")
  return true
end

---Launch program in a new thread
---@return boolean
function runctl.Program:run()
  if self.running then return false end
  self._finished=false
  self.failed=false
  local id=self.id
  local progName=self.name
  local args=self.args
  local function regCo()
    if not _G._ltde_co_pid then _G._ltde_co_pid={} end
    _G._ltde_co_pid[coroutine.running()]=id
  end
  local function unregCo()
    if _G._ltde_co_pid then _G._ltde_co_pid[coroutine.running()]=nil end
  end
  if self.mode=="system" then
    if not self.func then return false,"no func loaded" end
    self.running=true
    runctl.programs[id]=self
    self.thread=thread.create(function()
      _G._ltde_running_pid=id
      regCo()
      local ok,tb=xpcall(self.func,debug.traceback,table.unpack(args))
      unregCo()
      _G._ltde_running_pid=nil
      if not ok then
        self.failed=true
        slog.log("Crash("..id.."): "..tostring(tb),"runctl",2)
        event.push("ltde_app_crash",progName,id,tostring(tb))
      end
      self:finish()
    end)
  else
    local env=runctl.genEnv(id,self.appRoot,self.perms)
    local f,loadErr=loadfile(self.file,"t",env)
    if not f then
      slog.log("Sandbox load fail("..id.."): "..tostring(loadErr),"runctl",2)
      return false,tostring(loadErr)
    end
    self.running=true
    runctl.programs[id]=self
    self.thread=thread.create(function()
      regCo()
      local ok,tb=xpcall(f,debug.traceback,table.unpack(args))
      unregCo()
      if not ok then
        self.failed=true
        slog.log("Crash("..id.."): "..tostring(tb),"runctl",2)
        event.push("ltde_app_crash",progName,id,tostring(tb))
      end
      self:finish()
    end)
  end
  self.thread:detach()
  slog.log("Running: "..self.name.."("..id..")","runctl")
  return true
end

---Push an event to the program (system mode: real bus; sandboxed: Phase 2 will route to app queue)
---@param evname string
function runctl.Program:signal(evname,...)
  event.push(evname,self.id,...)
end

---Release desktop state on both normal exit and forced termination.
function runctl.Program:finish()
  if self._finished then return end
  self._finished=true
  self.running=false
  runctl.programs[self.id]=nil
  if _G._ltde_running_pid==self.id then _G._ltde_running_pid=nil end
  if _G._ltde_co_pid then
    for co,pid in pairs(_G._ltde_co_pid) do
      if pid==self.id then _G._ltde_co_pid[co]=nil end
    end
  end
  local wm=tgl.sys.wm
  local wins=wm and wm.pidWindows[self.id]
  if wins then
    local copy={}
    for _,mwin in ipairs(wins) do copy[#copy+1]=mwin end
    for _,mwin in ipairs(copy) do wm:closeWindow(mwin) end
  end
  event.push("ltde_app_exit",self.id)
end

---Kill the program immediately
function runctl.Program:terminate()
  if not self.running then return end
  if self.thread then self.thread:kill() end
  self.exitCode=-1
  self:finish()
  slog.log("Terminated: "..self.name.."("..self.id..")","runctl",1)
end

---Convenience: create, load and run a program from .app folder path
---@param appRoot string
---@param perms? integer
---@param args? any[] arguments passed to the app as varargs (...)
---@return runctl.Program|nil
function runctl.launch(appRoot,perms,args)
  local prog=runctl.Program:new(appRoot,perms,args)
  local lok,lerr=prog:load()
  if not lok then return nil,lerr end
  if prog.kind=="service" then return nil,"Start services through Task Manager." end
  local rok,rerr=prog:run()
  if not rok then return nil,rerr end
  return prog
end

---Graceful shutdown: signal all programs, wait for exit, force-kill remainder
---@param timeout? number seconds (default 5)
function runctl.shutdown(timeout)
  if not timeout then timeout=5 end
  local started=computer.uptime()
  local count=0
  for _,prog in pairs(runctl.programs) do if prog.running then count=count+1 end end
  slog.log("Shutdown: signaling "..count.." programs","runctl")
  for _,prog in pairs(runctl.programs) do
    prog:signal("ltde_shutdown")
  end
  local deadline=computer.uptime()+timeout
  while computer.uptime()<deadline do
    local allDone=true
    for _,prog in pairs(runctl.programs) do
      if prog.running then allDone=false break end
    end
    if allDone then break end
    os.sleep(0.1)
  end
  for _,prog in pairs(runctl.programs) do
    if prog.running then
      slog.log("Force-kill: "..prog.name.."("..prog.id..")","runctl",1)
      prog:terminate()
    end
  end
  slog.log(string.format("All programs stopped after %.2fs",computer.uptime()-started),"runctl")
end

return runctl
