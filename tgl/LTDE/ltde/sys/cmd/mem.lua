return {
  usage="mem",
  run=function(ctx,args)
    local computer=require("computer")
    local total,free=computer.totalMemory(),computer.freeMemory()
    ctx:print(string.format("Total: %.1f KB\nUsed:  %.1f KB\nFree:  %.1f KB",total/1024,(total-free)/1024,free/1024))
  end
}
