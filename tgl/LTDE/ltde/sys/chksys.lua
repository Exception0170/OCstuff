--checks system files
local fs=require("filesystem")
local files={
  "/ltde/sys/slog.lua",
  "/ltde/sys/cfglib.lua",
  "/ltde/sys/slib/fsaccess.lua",
  "/ltde/sys/slib/appconfig.lua",
  "/ltde/sys/slib/ltfiletypes.lua",
  "/ltde/sys/slib/ltcomplete.lua",
  "/ltde/sys/slib/ltcalc.lua",
  "/ltde/sys/crash.lua",
  "/ltde/sys/core.lua",
  "/ltde/sys/splash.lua",
  "/ltde/sys/ltwm.lua",
  "/ltde/sys/runctl.lua",
  "/ltde/sys/services.lua",
  "/ltde/sys/ltnotify.lua",
  "/ltde/sys/taskbar.lua",
  "/ltde/sys/startmenu.lua",
  "/ltde/sys/slib/ltwapi.lua",
  "/ltde/sys/slib/ltproc.lua",
  "/ltde/sys/slib/prmgr.lua",
  "/ltde/sys/slib/ltevent.lua",
}
if not slog then slog={} slog.log=print end
slog.log("Checking system files!","chksys")
local missing={}
for _,file in ipairs(files) do
  slog.log("Checking "..file,"chksys",-1)
  if not fs.exists(file) then
    slog.log("File not found: "..file,"chksys",2)
    table.insert(missing,file)
  end
end
if #missing>0 then
  error("Missing system files:\n"..table.concat(missing,"\n"),0)
end
slog.log("Checked!","chksys")
return true
