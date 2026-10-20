return {
  usage="type <file> [file ...]",
  validate=function(ctx,args)
    if ctx.redirectPath then
      local fs=require("filesystem")
      local identity=loadfile("/ltde/sys/slib/cmdfiles.lua")().identity
      for _,arg in ipairs(args) do
        local src=ctx:resolve(arg)
        if identity(src)==identity(ctx.redirectPath) then return false,"Cannot redirect a file onto itself." end
        for _,path in ipairs({src,ctx.redirectPath}) do
          while path~="/" and path~="" do
            if fs.isLink and fs.isLink(path) then return false,"Redirection through symbolic links is not supported." end
            path=fs.path(path):gsub("/$","")
          end
        end
      end
    end
    return true
  end,
  run=function(ctx,args)
    if #args==0 then return 1,ctx:getUsage("type") end
    local fs=require("filesystem")
    for _,arg in ipairs(args) do
      local path=ctx:resolve(arg)
      if ctx.redirectPath==path then return 1,"Cannot redirect a file onto itself." end
      if fs.isDirectory(path) then return 1,"Not a file: "..path end
      local file,err=io.open(path,"r")
      if not file then return 1,err end
      local ok,readErr=pcall(function()
        while true do
          local text,readError=file:read(4096)
          if not text then
            if readError then error(readError,0) end
            break
          end
          ctx:write(text)
        end
      end)
      file:close()
      if not ok then return 1,tostring(readErr) end
    end
  end
}
