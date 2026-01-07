---System library of GDE
local syslib={}
syslib.screenConfig={} --setup during startup
function syslib.safeRequire(modname)
  local success,mod=pcall(function()
    return require(modname)
  end)
  return success, mod
end
function syslib.loadfile(filename)
  local success,mod=pcall(function()
    return loadfile(filename)()
  end)
  return success, mod
end
return syslib