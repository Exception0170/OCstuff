return {
  usage="cmd",
  run=function(ctx,args)
    if #args>0 then return 1,ctx:getUsage("cmd") end
    local prog,err=ctx.services.launch("/ltde/apps/cmd.app",{})
    if not prog then return 1,err or "Cannot launch Command Prompt." end
  end
}
