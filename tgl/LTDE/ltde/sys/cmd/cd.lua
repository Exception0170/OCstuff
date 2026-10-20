return {
  usage="cd [path]",
  run=function(ctx,args)
    if not args[1] then args[1]="/home" end
    local path=ctx:resolve(args[1])
    if not require("filesystem").isDirectory(path) then return 1,"Not a directory: "..path end
    ctx.cwd=path
  end
}
