return {
  usage="run <app> [arguments...]",
  run=function(ctx,args)
    if not args[1] then return 1,ctx:getUsage("run") end
    local fs=require("filesystem")
    local app=table.remove(args,1)
    local path
    if app:find("/",1,true) then path=ctx:resolve(app)
    else path="/ltde/apps/"..app end
    if path:sub(-4)~=".app" then path=path..".app" end
    if not fs.isDirectory(path) then return 1,"Application not found: "..path end

    local prog,err=ctx.services.launch(path,args)
    if not prog then return 1,err or "Launch failed." end
    ctx:print("Started "..prog.name.." ("..prog.id..")")
  end
}
