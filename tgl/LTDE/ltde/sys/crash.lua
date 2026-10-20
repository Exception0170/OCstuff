--render BSOD on system fatal exit
local computer=require("computer")
local term=require("term")
local c={}
c.err={}
c.err.null={stopcode=0x0000,name="ERR_NULL",msg="Unknown error occured!"}
c.err.generic={stopcode=0x0001,name="ERR_GENERIC",msg="Generic error occured"}
c.err.loadfail={stopcode=0x0002,name="LOAD_ERROR",msg="Failed to load critical components"}
c.err.cfgfail={stopcode=0x0003,name="INVALID_SYSTEM_CONFIG",msg="Failed to load critical configuration files"}
c.err.lowmem={stopcode=0x000C,name="NOT_ENOUGH_MEMORY",msg="System has not enough memory for startup. 1MB minimum required."}
c.err.lowenergy={stopcode=0x000D,name="NOT_ENOUGH_ENERGY",msg="System had not enough energy to continue."}
c.err.manual={stopcode=0x000E,name="MANUALLY_INITIATED_CRASH",msg="User manually initiated crashdump"}
c.err.debug={stopcode=0x000F,name="DEBUG_ERROR",msg="Debug error message"}
c.err.ltwm_fail={stopcode=0xB000,name="LTWM_UNKNOWN_ERROR",msg="Unknown fatal LTWM error occured"}
c.err.ltwm_exit={stopcode=0xB001,name="LTWM_EXIT",msg="Lightweigh TGL Window Manager exited with code 1"}
c.err.ltwm_crash={stopcode=0xB00F,name="LTWM_CRASH",msg="LTWM has crashed with unknown error: see logs"}
c.err.core_fail={stopcode=0xC000,name="UNKNOWN_CORE_ERROR",msg="Unknown core error occured"}
c.err.core_exit={stopcode=0xC001,name="CORE_EXIT",msg="Core exited with code 1"}
c.err.core_load_fail={stopcode=0xC002,name="CORE_LOAD_FAILED",msg="Core couldn't load"}
c.err.core_low_mem={stopcode=0xC00C,name="CORE_LOW_MEMORY",msg="Core has not enough memory to continue operating"}
c.err.core_crash={stopcode=0xC00F,name="CORE_CRASH",msg="Core crashed with unknown error"}
function c.bsod(err,message,trace,debugenv)
  if computer.freeMemory()<40*1024 then c.lbsod(err,message,trace,debugenv) return end
  if type(err)~="table" then err=c.err.generic end
  if not message then message=err.msg end
  if not trace then trace="no trace given" end
  if not stopcode then stopcode=0 end
  if not debugenv then debugenv="none" end
  if type(debugenv)=="table" then debugenv=require("serialization").serialize(debugenv,true)
  elseif type(debugenv)~="string" then debugenv=tostring(debugenv) end
  local lineCount=0
  for _ in (debugenv.."\n"):gmatch("[^\n]*\n") do lineCount=lineCount+1 end

  local tgl=require("tgl")
  local sx=tgl.defaults.screenSizeX
  local sy=tgl.defaults.screenSizeY
  local textColor=tgl.Color2:new(0xFFFFFF,0x0000FF)

  local frame=tgl.Frame:new({
    tgl.Text:new("   LTDE   ",tgl.invertColor2(textColor),tgl.Pos2:new(3,1)),
    tgl.Text:new("LTDE ver: "..tostring(_G._ltde_version),textColor,tgl.Pos2:new(40,5)),
    tgl.Text:new(" TGL ver: "..tostring(tgl.version),textColor,tgl.Pos2:new(40,6)),
    tgl.Text:new("  OS ver: "..tostring(_G._OSVERSION),textColor,tgl.Pos2:new(40,7)),
    tgl.Text:new("free mem: "..tostring(computer.freeMemory()/1024).." KB",textColor,tgl.Pos2:new(40,8)),
    tgl.Text:new("total mem: "..tostring(computer.totalMemory()/1024).." KB",textColor,tgl.Pos2:new(39,9)),
    tgl.Text:new("A problem has occured and your session had to be shutdown.",textColor,tgl.Pos2:new(1,2)),
    tgl.Text:new(message,textColor,tgl.Pos2:new(1,3)),
    tgl.Text:new(err.name,textColor,tgl.Pos2:new(1,5)),
    tgl.Text:new("STOPCODE: "..string.format("0x%04X",err.stopcode),textColor,tgl.Pos2:new(1,6)),
    tgl.Text:new("Debug: ",textColor,tgl.Pos2:new(1,9)),
    tgl.TextBox:new(debugenv,tgl.Size2:new(1,10,sx,lineCount),textColor),
    tgl.TextBox:new(trace,tgl.Size2:new(1,11+lineCount,sx,20),textColor),
    tgl.Text:new("Press enter to exit to shell...",textColor,tgl.Pos2:new(1,sy-1)),
    tgl.Text:new("Press any key to restart computer...",textColor,tgl.Pos2:new(1,sy))
  },tgl.Size2:new(1,1,sx,sy),textColor)
  frame:render()
  if tgl.sys.renderer then tgl.sys.renderer:flush() end
  os.sleep(.5)
  local _,_,key=require("event").pull("key_down")
  if tgl.sys.renderer then tgl.sys.renderer:finish() end
  if key==13 then
    term.clear()
    os.exit(err.stopcode)
  else
    computer.shutdown(true)
  end
end
---low memory version
function c.lbsod(err,message,trace,debugenv)
  if type(err)~="table" then err=c.err.generic end
  if not message then message=err.msg end
  if not trace then trace="no trace given" end
  if not stopcode then stopcode=0 end
  if not debugenv then debugenv="none" end
  if type(debugenv)=="table" then debugenv=require("serialization").serialize(debugenv,true)
  elseif type(debugenv)~="string" then debugenv=tostring(debugenv) end
  local lineCount=0
  for _ in (debugenv.."\n"):gmatch("[^\n]*\n") do lineCount=lineCount+1 end

  local gpu=require("component").gpu
  gpu.setForeground(0xFFFFFF) gpu.setBackground(0x0000FF)
  local w,h=gpu.getResolution()
  gpu.fill(1,1,w,h," ")
  term.setCursor(1,1)
  print("<<LTDE>>",tostring(_G._ltde_version))
  print("A problem has occured and your session had to be shutdown.")
  print("This is a low-memory version of error screen; perhaps system memory is low.")
  print("Free memory: "..tostring(computer.freeMemory()/1024).." KB")
  print("Total memory: "..tostring(computer.totalMemory()/1024).." KB")
  print("")
  print(message)
  print(err.name)
  print("STOPCODE: "..string.format("0x%04X",err.stopcode))
  print("")
  print(debugenv)
  print(trace)
  print("")
  print("Press enter to exit to shell...")
  print("Press any key to restart computer...")
  os.sleep(.5)
  local _,_,key=require("event").pull("key_down")
  if key==13 then
    term.clear()
    os.exit(err.stopcode)
  else
    computer.shutdown(true)
  end
end
return c
