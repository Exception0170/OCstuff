-- System-mode process API. Return snapshots, never live runctl objects.
return function(runctl,permissions,services)
  local ltproc={}
  local function caller()
    local pid=_G._ltde_co_pid and _G._ltde_co_pid[coroutine.running()]
    local prog=pid and runctl.programs[pid]
    if not prog or prog.mode~="system" or not permissions.get(prog.perms,"rootAccess") then
      return nil,"Process access requires a trusted system application."
    end
    return pid
  end
  function ltproc.list()
    local pid,err=caller()
    if not pid then return nil,err end
    local list={}
    for _,prog in pairs(runctl.programs) do
      if prog.kind~="service" then
        list[#list+1]={id=prog.id,pid=prog.id,name=prog.name,kind="application",running=prog.running,self=prog.id==pid}
      end
    end
    table.sort(list,function(a,b)return a.id<b.id end)
    return list
  end
  function ltproc.terminate(id)
    local pid,err=caller()
    if not pid then return nil,err end
    if id==pid then return nil,"Cannot terminate the calling application. Use its Close or Exit action." end
    local prog=runctl.programs[id]
    if not prog or not prog.running then return nil,"The application has already exited." end
    if prog.kind=="service" then return nil,"Use Stop or Restart for services." end
    prog:terminate()
    return true
  end
  function ltproc.service(action,id)
    local pid,err=caller()
    if not pid then return nil,err end
    if not services then return nil,"Service manager unavailable." end
    if action=="start" then return services.start(id)
    elseif action=="stop" then return services.stop(id,false)
    elseif action=="restart" then return services.stop(id,true) end
    return nil,"Unknown service action."
  end
  return ltproc
end
