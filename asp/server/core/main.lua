--main server
local settings=dofile("settings.lua")
local urls=dofile("urls.lua")
local respond=dofile("core/respond.lua")
if not settings then error("Couldn't load settings!") end
if not urls then error("Couldn't load urls!") end
if not respond then error("Couldn't load respond!") end
local mnp=require("cmnp")
local asp=require("asp")
local gpu=require("component").gpu
local thread=require("thread")
local main={}
function main.log(msg,err)
  if err~=2 and settings.log==false then return end
  local res = "["..require("computer").uptime() .. "]"
  if err==2 then
    error(debug.traceback(res.."[Webserver/ERROR]"..msg))
  elseif err==1 then
    gpu.setForeground(0xFFFF33)
    print(res.."[Webserver/WARN]"..msg)
    gpu.setForeground(0xFFFFFF)
  else
    print(res.."[Webserver/INFO]"..msg)
  end
end
function main.webserver()
  local function handleErr(err)
    main.log("Error while processing request!",1)
    main.log("Error: "..err,1)
    main.log("Stack trace:",1)
    main.log(debug.traceback(),1)
    return err
  end
  if not mnp.isConnected(true) then
    main.log("Not connected",2)
  end
  if settings.log then
    mnp.toggleLog(true)
  end
  if settings.domain~="" then
    main.log("Setting domain: "..settings.domain)
    if not mnp.setDomain(settings.domain) then
      main.log("Couldn't set domain!",1)
    end
  end
  thread.create(mnp.mncp.c2cPingService):detach()
  main.log("Server started!")
  while true do
    local request,np=mnp.receive("broadcast","asp")
    if not request then goto continue end
    main.log("Connection!")
    request.ip=np.route[0] --ip
    local success,err=xpcall(urls.resolve,handleErr,request) --use threads?
    if not success then
      if settings.debug then
        asp.sendResponse(np.route[0],AspResponse.simple(500,"Error: "..err,{}))
      else
        asp.sendResponse(np.route[0],AspResponse.simple(500))
      end
    end
    ::continue::
  end
end
return main