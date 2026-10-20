return {
  usage="ren <path> <new-name>",
  run=function(ctx,args)
    if #args~=2 then return 1,ctx:getUsage("ren") end
    local fs=require("filesystem")
    local name=args[2]
    if name=="" or name=="." or name==".." or name:find("/",1,true) then return 1,"Use a name, not a destination path." end
    local src=ctx:resolve(args[1])
    if src=="/" or not fs.exists(src) then return 1,"Invalid source: "..src end
    for _,mount in fs.mounts() do
      if fs.canonical(mount)==src then return 1,"Cannot rename a mounted device." end
    end
    local dst=fs.concat(fs.path(src),name)
    if fs.exists(dst) then return 1,"Destination exists: "..dst end
    local ok,err=fs.rename(src,dst)
    if not ok then return 1,err or "Rename failed." end
  end
}
