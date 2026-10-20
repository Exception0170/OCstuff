return {
  usage="dir [-a|--all] [-b|--bare] [-d|--dirs-only] [-f|--files-only]\n    [-r|--reverse] [--sort name|size|date] [--] [path]",
  run=function(ctx,args)
    local fs=require("filesystem")
    local opts={}
    local path=nil
    local sort="name"
    local flags={a="all",b="bare",d="dirs-only",f="files-only",r="reverse"}
    local stop=false
    local i=1
    while i<=#args do
      local arg=args[i]
      if not stop and arg=="--" then stop=true
      elseif not stop and arg=="--sort" then
        i=i+1 sort=args[i]
        if sort~="name" and sort~="size" and sort~="date" then return 1,"Sort must be name, size, or date." end
      elseif not stop and arg:sub(1,2)=="--" then
        local name=arg:sub(3)
        if name~="all" and name~="bare" and name~="dirs-only" and name~="files-only" and name~="reverse" then
          return 1,"Unknown option: "..arg
        end
        opts[name]=true
      elseif not stop and arg:sub(1,1)=="-" and #arg>1 then
        for n=2,#arg do
          local flag=flags[arg:sub(n,n)]
          if not flag then return 1,"Unknown option: -"..arg:sub(n,n) end
          opts[flag]=true
        end
      else
        if path then return 1,"Specify one directory." end
        path=arg
      end
      i=i+1
    end
    if opts["dirs-only"] and opts["files-only"] then return 1,"Choose files-only or dirs-only." end
    path=ctx:resolve(path or ".")
    if not fs.isDirectory(path) then return 1,"Not a directory: "..path end
    local iter,err=fs.list(path)
    if not iter then return 1,err end
    local items={}
    for name in iter do
      name=name:gsub("/$","")
      if opts.all or name:sub(1,1)~="." then
        local full=fs.concat(path,name)
        local dir=fs.isDirectory(full)
        if (not opts["dirs-only"] or dir) and (not opts["files-only"] or not dir) then
          local ok,size=pcall(fs.size,full)
          local dt,date=pcall(fs.lastModified,full)
          table.insert(items,{name=name,dir=dir,size=ok and type(size)=="number" and size or 0,
            date=dt and type(date)=="number" and date or 0})
        end
      end
    end
    table.sort(items,function(a,b)
      if a.dir~=b.dir then return a.dir end
      local av,bv=a.name:lower(),b.name:lower()
      if sort~="name" and a[sort]~=b[sort] then av,bv=a[sort],b[sort] end
      if av==bv then av,bv=a.name,b.name end
      if opts.reverse then return av>bv end
      return av<bv
    end)
    local files,dirs,bytes=0,0,0
    if not opts.bare then ctx:print("\n Directory of "..path.."\n") end
    for _,item in ipairs(items) do
      if item.dir then dirs=dirs+1 else files=files+1 bytes=bytes+item.size end
      if not opts.bare then
        local timestamp=item.date
        if timestamp>100000000000 then timestamp=math.floor(timestamp/1000) end
        local ok,date=pcall(os.date,"%d/%m/%Y %H:%M",timestamp)
        if not ok or timestamp<=0 then date="                " end
        ctx:write(date.."  "..ctx:column(item.dir and "<DIR>" or string.format("%.0f",item.size),12,true).."  ")
      end
      local fg,bg=ctx.term:getColors()
      local color=ltfiletypes.color(item.name,item.dir)
      if color and not ctx.redirectPath then ctx.term:setColors(color,bg) end
      local ok,err=pcall(function() ctx:print(item.name) end)
      ctx.term:setColors(fg,bg)
      if not ok then error(err,0) end
    end
    if not opts.bare then
      ctx:print(string.format(" %d File(s)  %.0f bytes",files,bytes))
      local free=""
      local proxy=fs.get(path)
      if proxy then
        local ok,value=pcall(function() return proxy.spaceTotal()-proxy.spaceUsed() end)
        if ok and type(value)=="number" and value>=0 and value<math.huge then free=string.format("  %.0f bytes free",value) end
      end
      ctx:print(" "..dirs.." Dir(s)"..free)
    end
  end
}
