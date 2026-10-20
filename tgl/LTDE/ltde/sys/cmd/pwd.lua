return {
  usage="pwd",
  run=function(ctx,args)
    ctx:print(ctx.cwd)
  end
}
