local tgl=require("tgl")
local tui=require("tgl-ui")
local tmg=require("tgl-img")
local event=require("event")
local r=tgl.sys.renderer
local version="0.1 dev"
if r.gpu.maxResolution()<81 then error("You should use Tier3 gpu and screen.") end
r.gpu.setResolution(160,50)
---colors
local topbarBlue=tgl.Color2:new(0xFFFFFF,0x0000FF)
local lightgray=tgl.Color2:new(0,0xC3C3C3)
local toolbarGray=tgl.Color2:new(0,0xE1E1E1)
local toolbarDrop=tgl.Color2:new(0,0xD2D2D2)
---events
local menubarEvent="MenuBarEvent"
local toolSelectEvent="toolSelect"
local modeSelectEvent="modeSelect"
local areaSelectEvent="areaSelect"
local charChangeEvent="charChange"
local closeEvent="paintClose"
local resetEvent="paintResetScreen"
local customColorEvent="CustomColorOpen"
local changeColor1Event="color1Change"
local changeColor2Event="color2Change"

---vars
local canExit=true
local currentTool="Pencil"
local unsavedChanges=false
local currentColor2=tgl.Color2:new(0,0xFFFFFF)
local tools={"Pencil","Eraser","Brush","Rect","Line","Text"}
local modes={"pixel","normal"}
local areas={"1x1","2x2","3x3","star3"}
local palette = {
  0xFF0000, 0x990000,  -- red
  0xFF6D40, 0xCC0000,  -- light red, dark red
  0xFFB6FF, 0xCC6DBF,  -- pink
  0xFFDB40, 0xCC9240,  -- orange
  0xFFFF40, 0xCCB600,  -- yellow
  0x66FF80, 0x009240,  -- green
  0x99FF40, 0x339200,  -- lime
  0x666DFF, 0x0000BF,  -- blue
  0x66B6FF, 0x006DBF,  -- sky blue
  0x66FFFF, 0x00B6BF,  -- cyan
  0xCC6DFF, 0x6600BF,  -- purple
  0xCCB6FF, 0x6649BF,  -- violet
  0xCC9240, 0x996D00,  -- brown
  0xFFDB80, 0xCC4900,  -- tan
  0xFFFFFF, 0xC3C3C3,  -- white, light gray
  0x787878, 0x2D2D2D,  -- medium gray, dark gray
  0x1E1E1E, 0x000000,  -- charcoal, black
}
---util
local function rgbToHex(col)
  return string.format("0x%06X",col)
end
---objects
local fullscreen=tgl.Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY)
--For now, app is fullscreen
local appSizeX=fullscreen.sizeX
local appSizeY=fullscreen.sizeY
local topbar=tgl.Frame:new({
  title=tgl.Text:new("TGL Paint  version "..version,topbarBlue,tgl.Pos2:new(1,1)),
  exit=tgl.EventButton(" X ",closeEvent,nil,tgl.Pos2:new(appSizeX-2,1),tgl.defaults.colors2.close)
},tgl.Size2:new(1,1,appSizeX,1),topbarBlue)
local menubar=tgl.Frame:new({
  file=tui.DropdownMenu:new(tgl.Pos2:new(1,1),6,lightgray,{"New","Open","Save","SaveAs","Exit"},menubarEvent),
  edit=tui.DropdownMenu:new(tgl.Pos2:new(7,1),6,lightgray,{"Undo","Copy","Paste"},menubarEvent),
  image=tui.DropdownMenu:new(tgl.Pos2:new(13,1),6,lightgray,{"Flip |","Flip -","Empty"},menubarEvent),
  help=tui.DropdownMenu:new(tgl.Pos2:new(19,1),6,lightgray,{"Help","About"},menubarEvent),
  redraw=tgl.EventButton("reset",resetEvent,nil,tgl.Pos2:new(appSizeX-10,1),lightgray)
},tgl.Size2:new(1,2,tgl.defaults.screenSizeX,1),lightgray)
for k,v in pairs({file=" File ",edit=" Edit ",image="Image ",help="Help"}) do menubar.objects[k].defaultText=v end
local toolbar=tgl.Frame:new({
  toolLabel=tgl.Text:new("Tool:",toolbarGray,tgl.Pos2:new(1,1)),
  toolSelect=tui.DropdownMenu:new(tgl.Pos2:new(7,1),7,toolbarGray,tools,toolSelectEvent,toolbarDrop),
  modeLabel=tgl.Text:new("Mode:",toolbarGray,tgl.Pos2:new(1,2)),
  modeSelect=tui.DropdownMenu:new(tgl.Pos2:new(7,2),8,toolbarGray,modes,modeSelectEvent,toolbarDrop),
  areaLabel=tgl.Text:new("Area:",toolbarGray,tgl.Pos2:new(16,1)),
  areaSelect=tui.DropdownMenu:new(tgl.Pos2:new(22,1),6,toolbarGray,areas,areaSelectEvent,toolbarDrop),
  charLabel=tgl.Text:new("Char:",toolbarGray,tgl.Pos2:new(16,2)),
  charInput=tgl.InputField:new(tmg.char,tgl.Pos2:new(22,2),toolbarGray), --?
  color1Label=tgl.Text:new("Color 1: ",toolbarGray,tgl.Pos2:new(40,1)),
  color1Text=tgl.Text:new(rgbToHex(currentColor2[1]),tgl.Color2:new(currentColor2[1],toolbarGray[2]),tgl.Pos2:new(49,1)),
  color2Label=tgl.Text:new("Color 2: ",toolbarGray,tgl.Pos2:new(40,2)),
  color2Text=tgl.Text:new(rgbToHex(currentColor2[2]),tgl.Color2:new(currentColor2[2],toolbarGray[2]),tgl.Pos2:new(49,2)),
  customColorButton=tgl.EventButton("Custom Color",customColorEvent,nil,tgl.Pos2:new(110,1),toolbarGray)
},tgl.Size2:new(1,3,tgl.defaults.screenSizeX,2),toolbarGray)
toolbar.objects.charInput.eventName=charChangeEvent
local function getColorButton(col,pos2)
  local obj=tgl.Button:new("  ",function(button)
    if button==0 then event.push(changeColor1Event,col)
    else event.push(changeColor2Event,col) end
  end,pos2,tgl.Color2:new(0,col))
  obj.onClick=nil
  return obj
end
for y=1,2 do
  for x=1,(#palette/2) do
    local color=palette[((x-1)*2)+y]
    toolbar:add(getColorButton(color,tgl.Pos2:new(60+(x-1)*2,y)))
  end
end
local footer=tgl.Frame:new({
  tooltipLabel=tgl.Text:new("Tooltip:",lightgray,tgl.Pos2:new(1,1)),
  tooltipText=tgl.Text:new("Testing.",lightgray,tgl.Pos2:new(10,1)),
  nameLabel=tgl.Text:new("Name:",lightgray,tgl.Pos2:new(100,1)),
  nameText=tgl.Text:new("Unnamed",lightgray,tgl.Pos2:new(106,1)),
  resolutionText=tgl.Text:new("16x16",lightgray,tgl.Pos2:new(120,1)),
  extendedText=tgl.Text:new("Extended:false",lightgray,tgl.Pos2:new(130,1)),
  memLabel=tgl.Text:new("Mem:",lightgray,tgl.Pos2:new(145,1)),
  memText=tgl.Text:new("?%",lightgray,tgl.Pos2:new(150,1))
},tgl.Size2:new(1,appSizeY,appSizeX,1),lightgray)
footer.objects.nameText.maxLength=15
footer.objects.resolutionText.maxLength=6
footer.objects.tooltipText.maxLength=30
---
local function updateColorHex()
  toolbar.objects.color1Text.col2[1]=currentColor2[1]
  toolbar.objects.color2Text.col2[1]=currentColor2[2]
  toolbar.objects.color1Text:updateText(rgbToHex(currentColor2[1]))
  toolbar.objects.color2Text:updateText(rgbToHex(currentColor2[2]))
end
---
tgl.util.clear()
local test=tgl.Frame:new({topbar,menubar,toolbar,footer},fullscreen,tgl.defaults.colors2.white)
test:add(tgl.Text:new(""))
test:render()
test:enableAll()
while true do
  local id,value=event.pullMultiple(closeEvent,resetEvent,menubarEvent,areaSelectEvent,charChangeEvent,
  modeSelectEvent,toolSelectEvent,customColorEvent,changeColor1Event,changeColor2Event)
  if id==closeEvent and canExit==true then break
  elseif id==resetEvent then
    test:render()
  elseif id==changeColor1Event then
    currentColor2[1]=value
    updateColorHex()
  elseif id==changeColor2Event then
    currentColor2[2]=value
    updateColorHex()
  elseif id==menubarEvent then
    if value=="Exit" and canExit==true then break
    end
  end
  footer.objects.tooltipText:updateText(id..","..tostring(value))
end
test:disableAll()
os.sleep(.11)
tgl.util.clear()
--[[
TGL Paint ver 0.1 dev   [X]
File Edit Image Help
Tool: Brush     Area: 1x1----    Color 1: 0xFFFFFF                    [RGB chooser]
Mode: lmb/rmb   Char: ?          Color 2: 0x000000   <palette>        


   <image>



Tooltip: lmb                      Stats: "Untitled" 16x16  Extended: false  Mem: 60%


File: new, open, save, saveas, exit
Edit: undo, copy, paste
Image: flip |, flip -, empty
Help: Help, About

tools: Pencil, Brush, Fill(?), Rect, Circle, Line
]]