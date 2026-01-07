--Single library for gde applications
local gdelib={}
gdelib.ver="0.1 indev"
gdelib.tgl=require("tgl")
gdelib.tui=require("tui")

---Loads a GDE system module
---@param filepath string
function gdelib.loadSysModule(filepath)
  local fs=require("filesystem")
  if fs.exists(filepath) then
    local success,mod=pcall(function()
      return loadfile(filepath)()
    end)
    return success, mod
  end
end

function gdelib.getSys()
  local success,lib=gdelib.loadSysModule("/gde/sys/syslib.lua")
  if not success then error("couldn't load system: "..tostring(lib)) end
  return lib
end

--try to load logging
local s,l=gdelib.loadSysModule("/gde/lib/glog.lua")
if s then
  gdelib.log=l
end
return gdelib