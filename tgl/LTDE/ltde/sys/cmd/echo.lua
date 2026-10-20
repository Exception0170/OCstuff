return {
  usage="echo [text]",
  run=function(ctx,args)
    ctx:print(table.concat(args," "))
  end
}
