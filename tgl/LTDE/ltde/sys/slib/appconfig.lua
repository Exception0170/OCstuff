-- The parser's io and filesystem are private, bound to this app's policy.
return function(filesystem,resolve)
  local privateIO={open=function(path,mode)
    local ok,full=pcall(resolve,path,mode and mode~="r" and mode~="rb")
    if not ok then return nil,tostring(full) end
    return io.open(full,mode)
  end}
  local env=setmetatable({io=privateIO},{__index=_G})
  env.require=function(name)
    if name=="filesystem" then return filesystem end
    error("unsupported config dependency: "..tostring(name),2)
  end
  return assert(loadfile("/ltde/sys/cfglib.lua","t",env))()
end
