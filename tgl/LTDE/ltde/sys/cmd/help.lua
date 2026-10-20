return {
  usage="help [command]",
  run=function(ctx,args)
    if args[1] then
      local name=args[1]:lower()
      if ctx.aliases[name] then ctx:print(name.."="..ctx.aliases[name]) return end
      local usage=ctx:getUsage(name)
      if not usage then return 1,"Unknown command: "..args[1] end
      ctx:print(usage)
    else
      local names={}
      for name in pairs(ctx.commands) do table.insert(names,name) end
      table.sort(names)
      local row=""
      local cellW=12
      for _,name in ipairs(names) do cellW=math.max(cellW,#name+2) end
      local width=math.max(12,ctx.term.width or 60)
      for _,name in ipairs(names) do
        if row~="" and #row+cellW>width then ctx:print(row) row="" end
        row=row..ctx:column(name,cellW)
      end
      if row~="" then ctx:print(row) end
      ctx:print("Use help <command> for syntax; alias lists shortcuts.")
    end
  end
}
