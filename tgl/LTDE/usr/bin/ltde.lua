--CLI command to run LTDE

local fs=require("filesystem")
local function checklib(str,crash,info)
  local function t(str)
    local lib=require(str)
  end
  local success,err=pcall(t,str)
  if not success then
    print("Couldn't load lib "..str..": "..err)
    if info then print(info) end
    if crash then error("Couldn't start LTDE: "..err) end
    os.sleep(0.5)
  end
end

--1. check libs
checklib("tgl",true)
checklib("tgl-ui",true)
checklib("tgl-img",false,"Image module is recommended!")
if not fs.exists("/ltde") then error("LTDE directory not found, check your install") end
--2. run init
loadfile("/ltde/sys/init.lua")()
