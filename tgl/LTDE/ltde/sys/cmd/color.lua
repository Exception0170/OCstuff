return {
  usage="color [background+foreground hex | foreground hex]",
  run=function(ctx,args)
    if #args>1 then return 1,ctx:getUsage("color") end
    local ok,err=ctx.term:setColor(args[1] or "07",true)
    if not ok then return 1,err end
  end
}
