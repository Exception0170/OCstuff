return {
  usage="uptime",
  run=function(ctx,args)
    local seconds=math.floor(require("computer").uptime())
    ctx:print(string.format("%d days %02d:%02d:%02d",math.floor(seconds/86400),math.floor(seconds/3600)%24,math.floor(seconds/60)%60,seconds%60))
  end
}
