local fs=require("filesystem")
local event=require("event")
local computer=require("computer")

return function(runctl,cfg)
  local services={entries={},timer=nil}
  function services.scan()
    local iter=fs.list("/ltde/services")
    if not iter then return end
    for file in iter do
      local id=file:gsub("/+$",""):match("^([%w_%-]+)%.service$")
      if id and not services.entries[id] then
        local path=fs.concat("/ltde/services",id..".service")
        local chunk=loadfile(fs.concat(path,"manifest.lua"),"t",{})
        local ok,manifest=false,nil
        if chunk then ok,manifest=pcall(chunk) end
        if ok and type(manifest)=="table" and manifest.kind=="service" then
          services.entries[id]={id=id,path=path,name=manifest.name or id,
            protected=manifest.protected==true,state="Stopped"}
        end
      end
    end
  end
  function services.start(id)
    local entry=services.entries[id]
    if not entry then return nil,"Unknown service." end
    if entry.prog and entry.prog.running then return nil,"Service is already running." end
    local prog=runctl.Program:new(entry.path)
    local ok,err=prog:load()
    if ok and prog.kind~="service" then ok=false err="Manifest must declare kind=service." end
    if not ok then entry.prog=nil entry.state="Failed" entry.error=tostring(err) return nil,err end
    prog.serviceId=id
    entry.prog=prog
    entry.error=nil
    entry.restart=false
    entry.deadline=nil
    local started,reason=prog:run()
    if not started then entry.state="Failed" entry.error=tostring(reason) return nil,reason end
    entry.state=prog.running and "Running" or "Stopped"
    return true
  end
  function services.stop(id,restart)
    local entry=services.entries[id]
    if not entry then return nil,"Unknown service." end
    if entry.protected then return nil,"This service is protected; restart LTDE instead." end
    if entry.state=="Stopping" then return nil,"Service is already stopping." end
    if not entry.prog or not entry.prog.running then
      if restart then return services.start(id) end
      return nil,"Service is not running."
    end
    entry.restart=restart==true
    entry.deadline=computer.uptime()+5
    entry.state="Stopping"
    entry.prog:signal("ltde_service_stop")
    return true
  end
  function services.update()
    for id,entry in pairs(services.entries) do
      local prog=entry.prog
      if prog then
        if entry.deadline and prog.running and computer.uptime()>=entry.deadline then prog:terminate() end
        if not prog.running then
          local restart=entry.restart
          entry.restart=false entry.deadline=nil
          entry.state=prog.failed and "Failed" or "Stopped"
          if restart then services.start(id) end
        elseif entry.state~="Stopping" then entry.state="Running" end
      end
    end
  end
  function services.list()
    local result={}
    for id,entry in pairs(services.entries) do
      local prog=entry.prog
      local running=prog and prog.running or false
      result[#result+1]={id="service:"..id,serviceId=id,pid=running and prog.id or nil,
        name=entry.name,kind="service",running=running,protected=entry.protected,
        state=running and entry.state or (prog and prog.failed and "Failed" or entry.state=="Failed" and "Failed" or "Stopped")}
    end
    return result
  end
  function services.init()
    services.scan()
    if not services.timer then services.timer=event.timer(0.25,services.update,math.huge) end
    local ids={}
    for id in pairs(services.entries) do ids[#ids+1]=id end
    table.sort(ids)
    local errors={}
    for _,id in ipairs(ids) do
      if cfg and cfg:get("startup",id,false)==true then
        local ok,err=services.start(id)
        if not ok then errors[#errors+1]=id..": "..tostring(err) end
      end
    end
    return errors
  end
  function services.cleanup()
    if services.timer then event.cancel(services.timer) services.timer=nil end
    for _,entry in pairs(services.entries) do entry.restart=false end
  end
  return services
end
