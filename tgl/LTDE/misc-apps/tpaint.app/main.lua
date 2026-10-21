--LTDE TMG paint app
local version="1.0"
local tgl=require("tgl")
local tmg=require("tgl-img")
if type(tmg.Image.setMask)~="function" then ltnotify.error("TPaint","This app needs tgl-img 1.7 or later.") return 1 end
local fs=require("filesystem")
local keyboard=require("keyboard")
local document=assert(loadfile("/ltde/apps/tpaint.app/document.lua"))()(tmg)
local path=...
local uid=tostring(math.random(1,1000000))
local events={}
for _,name in ipairs({"close","new","open","save","saveAs","undo","rename","clear","clearBackground","transparency","depth","extended","tool","color","custom","swatch","swap","defaults","home","left","right","help","keys","tmg","about"}) do
  events[name]="tpaint_"..name.."_"..uid
end
local gray=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
local background=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkgray)
local closing=false
local w=math.min(76,tgl.defaults.screenSizeX)
local h=math.min(24,tgl.defaults.screenSizeY-1)
local formatItems={
  {label="Force transparency",eventName=events.transparency},
  {label="Force 8-bit",eventName=events.depth},
  {label="Force extended",eventName=events.extended}
}
local frame=ltwapi.addWindow(w,h,"TPaint",{
  toolbar=true,onClose=function() closing=true ltevent.push(events.close) end,
  menuItems={
    {label="File",items={{label="New...      Ctrl+N",eventName=events.new},{label="Open...     Ctrl+O",eventName=events.open},
      {label="Save        Ctrl+S",eventName=events.save},{label="Save as...  Ctrl+Shift+S",eventName=events.saveAs},
      {label="Close       Ctrl+W",eventName=events.close}}},
    {label="Edit",items={{label="Undo  Ctrl+Z",eventName=events.undo},{label="Rename...",eventName=events.rename},
      formatItems[1],formatItems[2],formatItems[3],{label="Clear all",eventName=events.clear},
      {label="Clear background",eventName=events.clearBackground}}},
    {label="View",items={{label="Top left  Home",eventName=events.home}}},
    {label="Help",items={{label="Help",eventName=events.help},{label="Keybindings   F1",eventName=events.keys},
      {label="About .tmg",eventName=events.tmg},{label="About",eventName=events.about}}}
  }
})
if not frame then return 1 end
-- Ask about unsaved work before the title-bar button removes the window.
frame.objects.titlebar.objects.close.callback=function() ltevent.push(events.close) end
local wm=tgl.sys.wm
local doc=document:new(32,32)
local filename=""
local offsetX,offsetY=0,0
local tool="Pencil"
local primary,secondary=tmg.palette4bitToColor(0),tmg.palette4bitToColor(15)
local customColors={}
local nextCustom=1
local stroke=nil
local canvas=setmetatable({type="BoxObject",z_index=0,size2=tgl.Size2:new(2,5,w-4,h-5),col2=background},
  {__index=tgl.BoxObject})
local displayColors={[4]={},[8]={}}
function canvas:render()
  if self.hidden then return end
  local r=tgl.sys.renderer
  r:fill(self.size2," ",self.col2,self.z_index)
  local clip=r:getClipRegion() or self.size2
  local left=math.max(self.size2.x1,clip.x1)
  local top=math.max(self.size2.y1,clip.y1)
  local right=math.min(self.size2.x2,clip.x2,self.size2.x1+(doc.width-offsetX)*2-1)
  local bottom=math.min(self.size2.y2,clip.y2,self.size2.y1+doc.height-offsetY-1)
  local colors=displayColors[doc.image.depth]
  local active={}
  local function paint(rect)
    r:fill(tgl.Size2:newFromPoint(rect.x1,rect.y1,rect.x2,rect.y2),rect.color==-1 and "░" or " ",colors[rect.color],self.z_index)
  end
  for y=top,bottom do
    local py=offsetY+y-self.size2.y1+1
    local x=left
    local row={}
    while x<=right do
      local first=x
      local color=doc:get(offsetX+(x-self.size2.x1)//2+1,py)
      repeat x=x+1 until x>right or doc:get(offsetX+(x-self.size2.x1)//2+1,py)~=color
      if not colors[color] then
        if color==-1 then colors[color]=tgl.Color2:new(0xCCCCCC,0x888888)
        else
          local rgb=doc.image.depth==4 and tmg.palette4bitToColor(color) or tmg.indexToRgb(color)
          colors[color]=tgl.Color2:new(rgb,rgb)
        end
      end
      -- Equal runs on adjacent rows form a single GPU fill.
      local key=first..":"..x..":"..color
      local rect=active[key]
      if rect then rect.y2=y active[key]=nil
      else rect={x1=first,y1=y,x2=x-1,y2=y,color=color} end
      row[key]=rect
    end
    for _,rect in pairs(active) do paint(rect) end
    active=row
  end
  for _,rect in pairs(active) do paint(rect) end
end
frame:add(canvas,"canvas")
local scrollbar=tgl.Scrollbar:new(tgl.Size2:new(w-1,5,1,h-5),gray)
frame:add(scrollbar,"scrollbar")
local status=tgl.Text:new("",gray,tgl.Pos2:new(15,h)) status.maxLength=w-16
frame:add(status,"status")
local tools={
  {"[Pen]","Pencil",2,3},{"[L]","Line",8,3},{"[R]","Rectangle",12,3},{"[Pick]","Picker",17,3},
  {"[Erase]","Eraser",2,4},{"[Circle]","Circle",10,4},{"[Fill]","Fill",19,4}
}
for _,item in ipairs(tools) do
  local button=tgl.EventButton(item[1],events.tool,item[2],tgl.Pos2:new(item[3],item[4]),gray)
  button.onClick=nil frame:add(button,item[2])
end
for _,item in ipairs({{"leftColor",0,3},{"rightColor",1,4}}) do
  local button=tgl.EventButton("",events.custom,item[2],tgl.Pos2:new(56,item[3]),gray)
  button.onClick=nil frame:add(button,item[1])
end
for i=0,15 do
  local color=tmg.palette4bitToColor(i)
  local button=tgl.Button:new("  ",function(which) ltevent.push(events.color,color,which) end,
    tgl.Pos2:new(27+(i%8)*2,3+i//8),tgl.Color2:new(0,color))
  button.onClick=nil frame:add(button,"color"..i)
end
for i=1,6 do
  local slot=i
  local button=tgl.Button:new("..",function(which) ltevent.push(events.swatch,slot,which) end,
    tgl.Pos2:new(45+((i-1)%3)*2,3+(i-1)//3),gray)
  button.onClick=nil frame:add(button,"custom"..i)
end
local addColor=tgl.Button:new("[+]",function(which) ltevent.push(events.custom,which) end,tgl.Pos2:new(52,3),gray)
addColor.onClick=nil frame:add(addColor,"addColor")
for _,item in ipairs({{"[<]","left",2},{"[>]","right",6},{"[0]","home",10}}) do
  local button=tgl.EventButton(item[1],events[item[2]],nil,tgl.Pos2:new(item[3],h),gray)
  button.onClick=nil frame:add(button,item[2])
end
local function limits()
  return math.max(0,doc.width-math.floor(canvas.size2.sizeX/2)),math.max(0,doc.height-canvas.size2.sizeY)
end
local lastTitle,lastStatus
local function redraw(regions)
  local maxX,maxY=limits()
  offsetX=math.max(0,math.min(offsetX,maxX)) offsetY=math.max(0,math.min(offsetY,maxY))
  scrollbar.maxScroll=maxY scrollbar.visibleSize=canvas.size2.sizeY scrollbar.scroll=offsetY
  status.text=string.format("%s | %dx%d | %d-bit | %s | %d,%d",tool,doc.width,doc.height,
    doc.image.depth,doc:changed() and "Modified" or "Saved",offsetX+1,offsetY+1)
  formatItems[1].label="Force transparency"..(doc.image.mask and " [x]" or "")
  formatItems[2].label="Force 8-bit"..(doc.image.depth==8 and " [x]" or "")
  formatItems[3].label="Force extended"..(doc.image.extended and " [x]" or "")
  frame.objects.leftColor.text=string.format("[L:#%06X]",primary)
  frame.objects.rightColor.text=string.format("[R:#%06X]",secondary)
  for _,item in ipairs(tools) do
    frame.objects[item[2]].col2=tool==item[2] and tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue) or gray
  end
  for i=1,6 do
    local button=frame.objects["custom"..i]
    button.text=customColors[i] and "  " or ".."
    button.col2=customColors[i] and tgl.Color2:new(0,customColors[i]) or gray
  end
  local title=frame.objects.titlebar.objects.title
  title.maxLength=w-10
  title.text="TPaint - "..(doc:changed() and "*" or "")..(filename~="" and fs.name(filename) or "Untitled")
  if regions then
    if lastTitle~=title.text then table.insert(regions,frame.objects.titlebar.size2) end
    if lastStatus~=status.text then table.insert(regions,tgl.Size2:new(frame.size2.x1,frame.size2.y2,w,1)) end
  end
  lastTitle,lastStatus=title.text,status.text
  if not closing and not frame.hidden then
    local managed=wm:getManagedWindow(frame)
    if managed and (not regions or #regions>0) then wm:renderRegions(regions or {wm:getWindowBounds(managed)}) end
  end
end
local function scroll(x,y)
  local maxX,maxY=limits()
  x=math.max(0,math.min(x,maxX)) y=math.max(0,math.min(y,maxY))
  if x==offsetX and y==offsetY then return end
  stroke=nil offsetX,offsetY=x,y redraw()
end
scrollbar.onChange=function(value) scroll(offsetX,value) end
local function save(as)
  local value=filename
  if as or value=="" then
    value=ltnotify.prompt("Save image","Path to a .tmg file:")
    if not value or value:match("^%s*$") then return false end
    value=fs.canonical(value)
    if fs.exists(value) and (as or value~=filename) then
      if ltnotify.dialog("Replace file?",value,{"Replace","Cancel"})~="Replace" then return false end
    end
  end
  local ok,err=doc.image:save(value)
  if not ok then ltnotify.error("Save image",tostring(err)) return false end
  filename=value doc:markSaved() redraw()
  return true
end
local function discard()
  if not doc:changed() then return true end
  local answer=ltnotify.dialog("Unsaved image","Save changes before continuing?",{"Save","Discard","Cancel"})
  if answer=="Save" then return save(false) end
  return answer=="Discard"
end
local function replace(nextDoc,value)
  doc.image:unload() doc=nextDoc filename=value or ""
  offsetX,offsetY=0,0 stroke=nil redraw()
end
local function open(value)
  if not value or value:match("^%s*$") then return end
  local image,err=tmg.Image:load(fs.canonical(value))
  if not image then ltnotify.error("Open image",tostring(err)) return end
  local nextDoc,why=document:fromImage(image)
  if not nextDoc then image:unload() ltnotify.error("Open image",why) return end
  replace(nextDoc,fs.canonical(value))
end
local function new()
  local value=ltnotify.prompt("New image","Size in pixels (WIDTHxHEIGHT):\n1-256 wide, 2-256 high; height must be even.")
  if not value or value:match("^%s*$") then return end
  local width,height=value:match("^%s*(%d+)%s*[xX]%s*(%d+)%s*$")
  width,height=tonumber(width),tonumber(height)
  if not width or not height or width<1 or width>256 or height<2 or height>256 or height%2~=0 then
    ltnotify.error("New image","Use whole numbers: width 1-256, even height 2-256.") return
  end
  replace(document:new(width,height))
end
local function point(x,y)
  if not tgl.util.pointInSize2(x,y,canvas.size2) or not tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then return end
  if wm:getWindowAt(x,y)~=wm:getManagedWindow(frame) then return end
  local px=offsetX+math.floor((x-canvas.size2.x1)/2)+1
  local py=offsetY+y-canvas.size2.y1+1
  if px<=doc.width and py<=doc.height then return px,py end
end
local function chooseColor(color,which)
  if which==1 then secondary=color else primary=color end
  redraw()
end
local function customColor(which,slot)
  local value=ltnotify.prompt("Custom color","Hex RGB color, for example #FF8800:\nColors use the nearest GPU 256-color value.")
  if not value or value:match("^%s*$") then return end
  value=value:match("^%s*(.-)%s*$"):gsub("^#",""):gsub("^0[xX]","")
  if #value~=6 or not value:match("^%x+$") then
    ltnotify.error("Custom color","Enter exactly six hex digits, optionally prefixed with # or 0x.") return
  end
  local color=tmg.indexToRgb(tmg.rgbToIndex(tonumber(value,16)))
  slot=slot or nextCustom
  customColors[slot]=color
  nextCustom=slot%6+1
  chooseColor(color,which)
end
local function ink(which)
  if tool=="Eraser" and doc.image.mask then return -1 end
  local color=tool=="Eraser" and secondary or (which==1 and secondary or primary)
  if doc.image.depth==4 then
    for i=0,15 do if tmg.palette4bitToColor(i)==color then return i end end
    doc:to8bit()
  end
  return tmg.rgbToIndex(color)
end
local function damage(x1,y1,x2,y2)
  local left=math.max(canvas.size2.x1,canvas.size2.x1+(math.min(x1,x2)-offsetX-1)*2)
  local right=math.min(canvas.size2.x2,canvas.size2.x1+(math.max(x1,x2)-offsetX)*2-1)
  local top=math.max(canvas.size2.y1,canvas.size2.y1+math.min(y1,y2)-offsetY-1)
  local bottom=math.min(canvas.size2.y2,canvas.size2.y1+math.max(y1,y2)-offsetY-1)
  if left<=right and top<=bottom then return tgl.Size2:newFromPoint(left,top,right,bottom) end
end
local function drawTo(x,y)
  local before=doc.image.rawdata
  local beforeMask=doc.image.mask
  local previousX,previousY=stroke.x,stroke.y
  if (tool=="Rectangle" or tool=="Circle") and keyboard.isControlDown() then
    local dx,dy=x-stroke.startX,y-stroke.startY
    local sx,sy=dx<0 and -1 or 1,dy<0 and -1 or 1
    local side=math.min(math.max(math.abs(dx),math.abs(dy)),
      sx<0 and stroke.startX-1 or doc.width-stroke.startX,
      sy<0 and stroke.startY-1 or doc.height-stroke.startY)
    x,y=stroke.startX+sx*side,stroke.startY+sy*side
  end
  if tool=="Pencil" or tool=="Eraser" then doc:line(previousX,previousY,x,y,stroke.color) end
  stroke.x,stroke.y=x,y
  if before~=doc.image.rawdata or beforeMask~=doc.image.mask then return damage(previousX,previousY,x,y) end
end
local function keybind(char,code)
  local shift=keyboard.isShiftDown()
  local ctrl=keyboard.isControlDown()
  if keyboard.isAltDown() then
    if code==62 then return events.close end
    return
  end
  if code==1 or char==27 then
    if stroke then doc:cancel() stroke=nil redraw() end
    return
  end
  local control={[14]=events.new,[15]=events.open,[19]=events.save,[26]=events.undo,[23]=events.close}
  if ctrl or control[char] then
    local action=control[char]
    if ctrl then
      action=({[49]=events.new,[24]=events.open,[31]=events.save,[44]=events.undo,[17]=events.close})[code] or action
      if code==199 then return events.home end
    end
    if action==events.save and shift then action=events.saveAs end
    return action
  end
  local selected=({[25]="Pencil",[18]="Eraser",[38]="Line",[19]="Rectangle",[46]="Circle",[33]="Fill",[23]="Picker"})[code]
  if selected then return events.tool,selected end
  if code==45 then return events.swap
  elseif code==32 then return events.defaults
  elseif code==37 then return events.custom,shift and 1 or 0
  elseif code==59 then return events.keys
  elseif code==199 then return events.home
  elseif code==201 then scroll(offsetX,offsetY-canvas.size2.sizeY)
  elseif code==209 then scroll(offsetX,offsetY+canvas.size2.sizeY)
  else
    local step=shift and 8 or 1
    if code==203 then scroll(offsetX-step,offsetY)
    elseif code==205 then scroll(offsetX+step,offsetY)
    elseif code==200 then scroll(offsetX,offsetY-step)
    elseif code==208 then scroll(offsetX,offsetY+step) end
  end
end
local ok,err=pcall(function()
  if path then open(path) else redraw() end
  if not closing then frame:enableAll() end
  while not closing do
    local ev,a,b,c,d=ltevent.pull()
    if ev=="key_down" then ev,a=keybind(b,c) end
    if ev=="ltde_shutdown" then break end
    if ev==events.close then if closing or discard() then break end
    elseif ev==events.new then stroke=nil if discard() then new() end
    elseif ev==events.open then stroke=nil if discard() then open(ltnotify.prompt("Open image","Path to a .tmg file:")) end
    elseif ev==events.save then stroke=nil save(false)
    elseif ev==events.saveAs then stroke=nil save(true)
    elseif ev==events.undo then stroke=nil doc:undo() redraw()
    elseif ev==events.clear then
      stroke=nil doc:begin()
      doc:clear(doc.image.mask and -1 or ink(1))
      doc:commit() redraw()
    elseif ev==events.clearBackground then
      stroke=nil doc:begin()
      local removed=doc:clearBackground()
      doc:commit()
      if removed>0 then redraw() end
    elseif ev==events.transparency or ev==events.depth or ev==events.extended then
      stroke=nil
      doc:begin()
      if ev==events.transparency then doc:enableTransparency()
      elseif ev==events.depth then doc:to8bit()
      else doc:toExtended() end
      doc:commit() redraw()
    elseif ev==events.rename then
      stroke=nil
      local value=ltnotify.prompt("Rename image","Current name: "..doc.image.name.."\nNew picture name:")
      if value and not value:match("^%s*$") and value~=doc.image.name then
        if value:find("[\r\n]") then ltnotify.error("Rename image","Image name must fit on one line.")
        else doc:begin() doc.image.name=value doc:commit() redraw() end
      end
    elseif ev==events.tool then stroke=nil tool=a redraw()
    elseif ev==events.color then chooseColor(a,b)
    elseif ev==events.swap then stroke=nil primary,secondary=secondary,primary redraw()
    elseif ev==events.defaults then
      stroke=nil primary,secondary=tmg.palette4bitToColor(0),tmg.palette4bitToColor(15) redraw()
    elseif ev==events.custom then stroke=nil customColor(a)
    elseif ev==events.swatch then
      stroke=nil
      if customColors[a] then chooseColor(customColors[a],b) else customColor(b,a) end
    elseif ev==events.home then scroll(0,0)
    elseif ev==events.left then scroll(offsetX-4,offsetY)
    elseif ev==events.right then scroll(offsetX+4,offsetY)
    elseif ev==events.help then
      ltnotify.dialog("TPaint help","Click and drag to draw. Line, rectangle and circle finish on release.\n"..
        "Hold Ctrl while dragging for squares and round circles.\n"..
        "Eraser clears pixels when transparency is enabled; otherwise it uses the right color.\n"..
        "Pick (I) samples a pixel: left/right click sets the left/right color.\n"..
        "Edit can force transparency, 8-bit colors or extended half-block mode.\n"..
        "Click L/R hex fields or [+] to add a custom color. Empty swatches can be set too.\n"..
        "Wheel scrolls; Shift+wheel scrolls sideways. Arrow keys pan.\n"..
        "Ctrl+N/O/S/Z: new, open, save, undo. Up to 16 undo steps are kept within 128 KiB.\n"..
        "Each image pixel uses two columns and one row. Custom character editing is not supported yet.",{"OK"})
    elseif ev==events.keys then
      ltnotify.dialog("TPaint keybindings","P/E/L/R/C/F: pen, eraser, line, rect, circle, fill\n"..
        "I: color picker (left/right click chooses that color)\n"..
        "Ctrl+drag: square / round circle\n"..
        "X: swap colors   D: black/white colors\nK / Shift+K: set left/right color\n"..
        "Ctrl+N/O: new/open   Ctrl+S: save\nCtrl+Shift+S: save as   Ctrl+Z: undo\n"..
        "Ctrl+W / Alt+F4: close (asks before discarding)\n"..
        "Arrows: pan   Shift+arrows: pan 8 pixels\nPage Up/Down: pan one canvas height\n"..
        "Home: top left   Esc: cancel current stroke\nF1: show keybindings",{"OK"})
    elseif ev==events.tmg then
      ltnotify.dialog("About .tmg","TMG uses fixed palettes: 4-bit=16, 8-bit=256.\n"..
        "8-bit: 240 RGB combinations + 16 extra grays.\n"..
        "Channel values in hex (#RRGGBB):\n"..
        "R: 00 33 66 99 CC FF\n"..
        "G: 00 24 49 6D 92 B6 DB FF\n"..
        "B: 00 40 80 BF FF\n"..
        "Extra grays (R=G=B):\n"..
        "0F 1E 2D 3C 4B 5A 69 78\n"..
        "87 96 A5 B4 C3 D2 E1 F0\n\n"..
        "TMG header: tmg, flags, name, width, height.\n"..
        "Dimensions are in character cells; each normally\nholds two vertical pixels.\n"..
        "An optional transparency mask precedes color data.\n"..
        "Flags also select compression and extended mode\n(which stores a character for each cell).",{"OK"})
    elseif ev==events.about then ltnotify.dialog("TPaint","TPaint "..version.."\nTMG painting for LTDEv1",{"OK"})
    elseif ev=="touch" and not frame.hidden then
      stroke=nil
      local x,y=point(b,c)
      if x and tool=="Picker" then
        local color=doc:get(x,y)
        if color~=-1 then
          chooseColor(doc.image.depth==4 and tmg.palette4bitToColor(color) or tmg.indexToRgb(color),d)
        end
      elseif x then
        local depth=doc.image.depth
        local before=doc.image.rawdata
        local beforeMask=doc.image.mask
        doc:begin() stroke={x=x,y=y,startX=x,startY=y,color=ink(d)}
        local area
        if tool=="Fill" then
          doc:fill(x,y,stroke.color) doc:commit() stroke=nil
          if before~=doc.image.rawdata or beforeMask~=doc.image.mask then area=canvas.size2 end
        else area=drawTo(x,y) end
        if depth~=doc.image.depth then area=canvas.size2 end
        if area then redraw({area}) end
      end
    elseif ev=="drag" and stroke and not frame.hidden then
      local x,y=point(b,c)
      if x then
        local area=drawTo(x,y)
        if area then redraw({area}) end
      end
    elseif ev=="drop" and stroke then
      local x,y=point(b,c)
      local area=x and drawTo(x,y)
      local before=doc.image.rawdata
      local beforeMask=doc.image.mask
      if tool=="Line" then doc:line(stroke.startX,stroke.startY,stroke.x,stroke.y,stroke.color)
      elseif tool=="Rectangle" then doc:rectangle(stroke.startX,stroke.startY,stroke.x,stroke.y,stroke.color)
      elseif tool=="Circle" then doc:circle(stroke.startX,stroke.startY,stroke.x,stroke.y,stroke.color) end
      if before~=doc.image.rawdata or beforeMask~=doc.image.mask then area=damage(stroke.startX,stroke.startY,stroke.x,stroke.y) end
      doc:commit()
      stroke=nil
      if area then redraw({area}) end
    elseif ev=="scroll" and not frame.hidden and point(b,c) then
      if keyboard.isShiftDown() then scroll(offsetX-d*3,offsetY) else scroll(offsetX,offsetY-d*3) end
    end
  end
end)
frame:disableAll() doc.image:unload() ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
