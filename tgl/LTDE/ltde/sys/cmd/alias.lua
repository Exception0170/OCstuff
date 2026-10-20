return {
  usage='alias [name[="command arguments"]] | alias -d name',
  run=function(ctx,args)
    if #args==0 then
      local names={}
      for name in pairs(ctx.aliases) do table.insert(names,name) end
      table.sort(names)
      for _,name in ipairs(names) do ctx:print(name.."="..ctx.aliases[name]) end
      return
    end
    if args[1]=="-d" then
      if #args~=2 then return 1,ctx:getUsage("alias") end
      ctx.aliases[args[2]:lower()]=nil
      return
    end
    local text=table.concat(args," ")
    local name,value=text:match("^([%w_-]+)=(.*)$")
    if name then
      name=name:lower()
      if value:match("^%s*$") then return 1,"Alias cannot be empty." end
      if name=="alias" then return 1,"The alias command cannot be replaced." end
      ctx.aliases[name]=value
    elseif #args==1 and ctx.aliases[args[1]:lower()] then
      ctx:print(args[1]:lower().."="..ctx.aliases[args[1]:lower()])
    else return 1,ctx:getUsage("alias") end
  end
}
