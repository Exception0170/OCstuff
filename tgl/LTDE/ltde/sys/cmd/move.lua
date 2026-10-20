return {
  usage="move [-f|--force] [--] <source-file> <destination>",
  run=function(ctx,args)
    return loadfile("/ltde/sys/slib/cmdfiles.lua")().transfer(ctx,args,true)
  end
}
