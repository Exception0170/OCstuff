return {
  usage="date",
  run=function(ctx,args)
    ctx:print(os.date("%Y-%m-%d"))
  end
}
