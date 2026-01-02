local tgl=require("tgl")
local component=require("component")
local blue=tgl.Color2:new(tgl.defaults.colors16.lightgray,tgl.defaults.colors16.darkblue)
local gold=tgl.Color2:new(tgl.defaults.colors16.gold,tgl.defaults.colors16.darkblue)
local gray=tgl.invertColor2(blue)
local side_y=side_y
if tgl.defaults.screenSizeX>80 then side_y=50 end
local main=tgl.Frame:new({},tgl.Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY),blue)
main:add(tgl.Text:new("   DeviceInfo86    ",tgl.Color2:new(tgl.defaults.colors16.lightgray,tgl.defaults.colors16.red),tgl.Pos2:new(1,1)),"memtest")
main:add(tgl.Frame:new({},tgl.Size2:new(1,main.size2.y2,main.size2.sizeX,1),gray),"bottom")
main.objects.bottom:add(tgl.Text:new("(exc)Exit  (enter)Exit",gray,tgl.Pos2:new(1,1)))
local function text(str,x,y,col2)
  if not col2 then col2=blue end
  main:add(tgl.Text:new(str,col2,tgl.Pos2:new(x,y)))
end
local function textAddress(address,x,y)
  text("Address:",x,y) text(address,x+9,y,gold)
end
local function tokb(n) return tostring(math.floor(n/1024)).."kB" end
text("Device information     "..os.date(),22,1 )
local t=component.computer.getDeviceInfo()
local nulluuid="00000000-0000-0000-0000-000000000000"
--necessary
local computer=require("computer")
local display
local gpu
local memory1
local memory2={nulluuid,{clock=0,product="N/A"}}
local memory3={nulluuid,{clock=0,product="N/A"}}
local memory4={nulluuid,{clock=0,product="N/A"}}
local cpu
local eeprom
--peripherals
local redstone
local netcard
local internet
local sound
local camera

local lastmemfound=0
for uuid,obj in pairs(t) do
  if obj.description=="CPU" then cpu={uuid,obj}
  elseif obj.description=="Graphics controller" then gpu={uuid,obj}
  elseif obj.class=="display" then display={uuid,obj}
  elseif obj.description=="EEPROM" then eeprom={uuid,obj}
  elseif obj.class=="memory" then
    if lastmemfound==0 then memory1={uuid,obj} lastmemfound=1
    elseif lastmemfound==1 then memory2={uuid,obj} lastmemfound=2
    elseif lastmemfound==2 then memory3={uuid,obj} lastmemfound=3
    else memory4={uuid,obj} end
  elseif obj.class=="network" then netcard={uuid,obj}
  elseif obj.class=="communication" then
  	if obj.description=="Redstone controller" or obj.description=="Advanced redstone controller" then redstone={uuid,obj}
  	elseif obj.description=="Internet modem" then internet={uuid,obj} end
  elseif obj.class=="multimedia" then
  	if obj.description=="Dungeon Scanner 2.5D" then camera={uuid,obj}
  	elseif obj.description=="Audio interface" then sound={uuid,obj} end
  end
end

text("CPU: "..cpu[2].product,1,2) text("Architecture: "..computer.getArchitecture(),side_y,2)
text("CPU Clock: "..cpu[2].clock.."hz",1,3) text("EEPROM: "..eeprom[2].product.." "..tokb(eeprom[2].capacity),side_y,3)
text("Screen: "..display[2].product,1,4)
text("Screen depth: "..component.gpu.getDepth().."bit",1,5)
text("TGL version: "..tgl.version,1,6) text("Screen UUID:",side_y,6) text(display[1],side_y+13,6,gold)
text("GPU: "..gpu[2].product,side_y,4)
text("GPU Clock: "..gpu[2].clock.." hz",side_y,5)
text("Total memory: "..tokb(computer.totalMemory()),1,7)
text("Mem1: "..memory1[2].product.." Clock: "..memory1[2].clock.."hz",1,8) textAddress(memory1[1],side_y,8)
text("Mem2: "..memory2[2].product.." Clock: "..memory2[2].clock.."hz",1,9) textAddress(memory2[1],side_y,9)
text("Mem3: "..memory3[2].product.." Clock: "..memory3[2].clock.."hz",1,10) textAddress(memory3[1],side_y,10)
text("Mem4: "..memory4[2].product.." Clock: "..memory4[2].clock.."hz",1,11) textAddress(memory4[1],side_y,11)
text("OS: ".._G._OSVERSION,1,12) text("Boot Address:",side_y,12) text(computer.getBootAddress(),side_y+14,12,gold)
text("Peripherals:",1,13)
local y=14
if netcard then
local wireless=true
if netcard[2].version=="4.0" then wireless=false end
text("Network card: "..netcard[2].product,1,y) textAddress(netcard[1],side_y,y)
text("  Max distance: "..netcard[2].width.."   Max ports: "..netcard[2].size.."   Max packet size: "..tokb(netcard[2].capacity).."   Wireless: "..tostring(wireless),1,y+1)
y=y+2
end
if internet then
text("Internet: "..internet[2].product,1,y) textAddress(internet[1],side_y,y)
text("  TCP enabled: "..tostring(component.internet.isTcpEnabled()).."   HTTP enabled: "..tostring(component.internet.isHttpEnabled()),1,y+1)
y=y+2
end
if redstone then
text("Redstone card: "..redstone[2].product,1,y) textAddress(redstone[1],side_y,y)
text("  Channels: "..redstone[2].width,1,y+1)
y=y+2
end
if sound then
text("Sound card: "..sound[2].product,1,y) textAddress(sound[1],side_y,y)
text("  Channels: "..component.sound.channel_count,1,y+1)
y=y+2
end
if camera then
text("Camera: "..camera[2].description,1,y) textAddress(camera[1],side_y,y)
text(camera[2].product,1,y+1)
y=y+2
end

main:render()
while true do
  local _,_,key1,key2=require("event").pull("key_down")
  if key1==tgl.defaults.keys.esc then break end
  if key1==tgl.defaults.keys.enter then break end
end
main=nil
require("term").clear()