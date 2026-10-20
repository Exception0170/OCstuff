return {
  usage="del <file> [file ...]",
  run=function(ctx,args)
    if #args==0 then return 1,ctx:getUsage("del") end
    local fs=require("filesystem")
    local paths={}
    for _,name in ipairs(args) do
      local path=ctx:resolve(name)
      if not fs.exists(path) then return 1,"File not found: "..path end
      if fs.isDirectory(path) then return 1,"Use rmdir for empty directories: "..path end
      table.insert(paths,path)
    end
    local seen={}
    for _,path in ipairs(paths) do
      if not seen[path] then
        seen[path]=true
        if fs.isDirectory(path) then return 1,"Path became a directory: "..path end
        local ok,err=fs.remove(path)
        if not ok then return 1,"Cannot delete "..path..": "..tostring(err or "unknown error") end
        ctx:print("Deleted "..path)
      end
    end
  end
}
