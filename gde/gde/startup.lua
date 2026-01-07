--Glass Desktop Environment startup
--[[
1. check internal components
2. read configs
3. check global libs
4. init processmngr, start desktop
]]
local term=require("term")
local gpu=require("component").gpu

local syslib=loadfile("/gde/sys/syslib.lua")()
if type("syslib")~="table" then
  error("Couldn't load system library /gde/sys/syslib.lua")
end
local success,glog=syslib.loadfile("/gde/lib/glog.lua")
if not success then
  error("Couldn't load system library GLOG /gde/sys/glog.lua : "..tostring(glog))
end
local success,gjson=syslib.loadfile("/gde/lib/gjson.lib")
if not success then
  error("Couldn't load system library GJSON /gde/sys/gjson.lua : "..tostring(gjson))
end
if not glog.newSysLog() then
  --fallback
  glog.syslog="/GDE-log-"..os.date("%H:%M-%d-%b-%Y")..".log"
  glog.syslog("Couldn't open default system log file - falling back to root","sys",1)
end
glog.syslog("System start")
glog.syslog("Checking libraries")

glog.syslog("Reading configs")
local success,config=gjson.loadfile("/gde/etc/cfg/screen.cfg")
if not success then
  glog.syslog("Couldn't read config /gde/etc/cfg/screen.json; making default","sys",1)
  local x,y=gpu.maxResolution()
  local config={screenUUID=gpu.getScreen(),sizeX=x,sizeY=y}
  local success,msg=gjson.dumptofile(config,"/gde/etc/cfg/screen.cfg",true)
  if not success then
    glog.syslog("Couldn't save default screen config: "..msg,"sys",2)
  end
end
if not string.match(config.screenUUID,"^[%x]{8}%-[%x]{4}%-[%x]{4}%-[%x]{4}%-[%x]{12}$") then
  glog.syslog("Unvalid ScreenUUID; defaulting",2)
  config.screenUUID=gpu.getScreen()
end
config.depth=gpu.maxDepth()
gpu.bind(config.screenUUID)
syslib.screenConfig=config
glog.syslog("Screen bound")