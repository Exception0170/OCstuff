return {
  usage="mkdir <path>",
  run=function(ctx,args)
    if #args~=1 then return 1,ctx:getUsage("mkdir") end
    local fs=require("filesystem")
    local path=ctx:resolve(args[1])
    if fs.exists(path) then return 1,"Already exists: "..path end
    local ok,err=fs.makeDirectory(path)
    if not ok then return 1,err or "Cannot create directory." end
  end
}
