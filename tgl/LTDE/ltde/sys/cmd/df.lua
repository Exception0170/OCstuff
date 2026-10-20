return {
  usage="df",
  run=function(ctx,args)
    local fs=require("filesystem")
    local rows={}
    for proxy,path in fs.mounts() do table.insert(rows,{proxy=proxy,path=path}) end
    table.sort(rows,function(a,b) return a.path<b.path end)
    local function size(n)
      if type(n)~="number" or n<0 then return "?" end
      if n==math.huge then return "Unlimited" end
      if n>=1048576 then return string.format("%.2fMb",n/1048576) end
      return string.format("%.1fKb",n/1024)
    end
    ctx:print(ctx:column("TOTAL",11)..ctx:column("FREE",11)..ctx:column("USED",6).."MOUNT")
    for _,row in ipairs(rows) do
      local ok,total,used=pcall(function() return row.proxy.spaceTotal(),row.proxy.spaceUsed() end)
      local free,percent=nil,"?"
      if ok and type(total)=="number" and type(used)=="number" then
        free=math.max(0,total-used)
        if total>0 and total<math.huge then percent=string.format("%.0f%%",used/total*100) end
      end
      ctx:print(ctx:column(size(ok and total or nil),11)..ctx:column(size(free),11)..ctx:column(percent,6)..row.path)
    end
  end
}
