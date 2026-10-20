return {
  usage="rmdir <empty-directory>",
  run=function(ctx,args)
    if #args~=1 then return 1,ctx:getUsage("rmdir") end
    local fs=require("filesystem")
    local path=ctx:resolve(args[1])
    if path=="/" then return 1,"Cannot remove root." end
    if not fs.isDirectory(path) then return 1,"Not a directory: "..path end
    for _,mount in fs.mounts() do
      if fs.canonical(mount)==path then return 1,"Cannot remove a mounted device." end
    end
    local iter,err=fs.list(path)
    if not iter then return 1,err end
    if iter() then return 1,"Directory is not empty: "..path end
    local ok,removeErr=fs.remove(path)
    if not ok then return 1,removeErr or "Cannot remove directory." end
  end
}
