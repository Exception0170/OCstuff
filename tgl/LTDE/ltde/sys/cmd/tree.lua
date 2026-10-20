return {
  usage="tree [-a|--all] [-d|--dirs-only] [-L|--depth 0..16] [path]",
  run=function(ctx,args)
    local fs=require("filesystem")
    local depth=3
    local all,dirs=false,false
    local path=nil
    local i=1
    while i<=#args do
      local arg=args[i]
      if arg=="-a" or arg=="--all" then all=true
      elseif arg=="-d" or arg=="--dirs-only" then dirs=true
      elseif arg=="-L" or arg=="--depth" then
        i=i+1 depth=tonumber(args[i])
        if not depth or depth%1~=0 or depth<0 or depth>16 then return 1,"Depth must be an integer from 0 to 16." end
      elseif arg:sub(1,1)=="-" then return 1,"Unknown option: "..arg
      elseif path then return 1,ctx:getUsage("tree")
      else path=arg end
      i=i+1
    end
    path=ctx:resolve(path or ".")
    if not fs.isDirectory(path) then return 1,"Not a directory: "..path end
    ctx:print(path)
    local count=0
    local function walk(folder,prefix,level)
      if level>=depth or count>=1000 then return end
      local iter,err=fs.list(folder)
      if not iter then error(err or "Cannot list "..folder,0) end
      local names={}
      for name in iter do
        local full=fs.concat(folder,name)
        if (all or name:sub(1,1)~=".") and (not dirs or fs.isDirectory(full)) then table.insert(names,name) end
      end
      table.sort(names)
      for n,name in ipairs(names) do
        if count>=1000 then break end
        count=count+1
        local last=n==#names
        ctx:print(prefix..(last and "`-- " or "|-- ")..name)
        local full=fs.concat(folder,name)
        if fs.isDirectory(full) and not (fs.isLink and fs.isLink(full)) then
          walk(full,prefix..(last and "    " or "|   "),level+1)
        end
      end
    end
    walk(path,"",0)
    if count>=1000 then ctx:print("Listing stopped at 1000 entries.") end
  end
}
