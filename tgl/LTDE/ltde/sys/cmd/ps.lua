return {
  usage="ps",
  run=function(ctx,args)
    local programs=ctx.services.programs()
    table.sort(programs,function(a,b) return a.id<b.id end)
    local pidW=4
    for _,prog in ipairs(programs) do pidW=math.max(pidW,#tostring(prog.id)) end
    local nameW=math.max(8,(ctx.term.width or 60)-pidW-11)
    local function row(pid,state,name)
      return ctx:column(pid,pidW).." "..ctx:column(state,9).." "..ctx:column(name,nameW)
    end
    ctx:print(row("PID","STATE","NAME"))
    for _,prog in ipairs(programs) do
      ctx:print(row(prog.id,prog.running and "running" or "stopped",prog.name))
    end
  end
}
