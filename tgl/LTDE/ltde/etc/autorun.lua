--Runs LTDE
local term=require("term")
term.clear()
print("LTDE loader")
print("Press ENTER to exit to OpenOS shell...")
local _,_,key=require("event").pull(.5,"key_down")
if key and key==13 then
  print("exiting..")
  os.exit(0)
else
  print("Starting LTDE...")
  require("shell").execute("ltde")
end