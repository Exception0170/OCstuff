return {
  usage="time",
  run=function(ctx,args)
    ctx:print(os.date("%H:%M:%S"))
  end
}
