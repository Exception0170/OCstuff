return {
  usage="kill <pid>",
  validate=function(ctx,args)
    local pid=tonumber(args[1])
    if #args~=1 or not args[1]:match("^%d+$") or not pid or pid<1 or pid==math.huge then
      return nil,ctx:getUsage("kill")
    end
    return true
  end,
  run=function(ctx,args)
    if not ctx.services.terminate then return 1,"Process service unavailable. Restart LTDE." end
    local pid=tonumber(args[1])
    local ok,err=ctx.services.terminate(pid)
    if not ok then return 1,err end
    ctx:print("Terminated PID "..pid..".")
  end
}
