--LTDE TMG viewer
local tgl=require("tgl")
local tmg=require("tgl-img")
local fs=require("filesystem")
local unicode=require("unicode")
local keyboard=require("keyboard")
local version="1.0.1"
if type(tmg.Image.renderRegion)~="function" then
  ltnotify.error("Image Viewer","This app needs tgl-img 1.6 or later.") return 1
end
local path=...
local uid=tostring(math.random(1,1000000))
local events={}
for _,name in ipairs({"close","open","rename","info","home","left","right","up","down","size","custom","help","about"}) do
  events[name]="imgview_"..name.."_"..uid
end
local gray=tgl.Color2:new(0,0xD2D2D2)
local background=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkgray)
local presets={{16,16},{32,32},{64,32},{180,80}}
local viewItems={}
for _,size in ipairs(presets) do
  table.insert(viewItems,{label=size[1].."x"..size[2].." pixels",eventName=events.size,value=size})
end
table.insert(viewItems,{label="Custom size...",eventName=events.custom})
table.insert(viewItems,{label="Top left",eventName=events.home})
table.insert(viewItems,{label="Image info",eventName=events.info})
local closing=false
local frame=ltwapi.addWindow(60,18,"Image Viewer",{
  onClose=function() closing=true ltevent.push(events.close) end,
  toolbar=true,
  menuItems={
    {label="File",items={{label="Open...",eventName=events.open},{label="Close",eventName=events.close}}},
    {label="Edit",items={{label="Rename...",eventName=events.rename}}},
    {label="View",items=viewItems},
    {label="Help",items={{label="Help",eventName=events.help},{label="About",eventName=events.about}}}
  }
})
if not frame then return 1 end
local wm=tgl.sys.wm
local image=nil
local filename=nil
local windowTitle="Image Viewer"
local offsetX,offsetY=0,0
local canvas=setmetatable({type="BoxObject",z_index=0,size2=tgl.Size2:new(2,4,56,12),col2=background},
  {__index=tgl.BoxObject})
function canvas:render()
  if self.hidden then return end
  local r=tgl.sys.renderer
  r:fill(self.size2," ",self.col2,self.z_index)
  if image then
    image.z_index=self.z_index
    image:renderRegion({x1=offsetX+1,y1=offsetY+1,
      x2=offsetX+self.size2.sizeX,y2=offsetY+self.size2.sizeY},self.size2.pos1)
  else
    r:set(tgl.Pos2:new(self.size2.x1+2,self.size2.y1+1),
      unicode.sub("File > Open to view a TMG image.",1,self.size2.sizeX-2),self.col2,self.z_index)
  end
end
frame:add(canvas,"canvas")
local scrollbar=tgl.Scrollbar:new(tgl.Size2:new(58,4,1,12),gray)
frame:add(scrollbar,"scrollbar")
local details=tgl.Text:new("No image open",gray,tgl.Pos2:new(2,16)) details.maxLength=57
frame:add(details,"details")
for _,button in ipairs({{"[<]","left",2},{"[>]","right",7},{"[Up]","up",12},{"[Down]","down",19},{"[Top left]","home",28}}) do
  local control=tgl.EventButton(button[1],events[button[2]],nil,tgl.Pos2:new(button[3],17),gray)
  control.onClick=nil frame:add(control,button[2])
end
local function limits()
  return image and math.max(0,image.size2.sizeX-canvas.size2.sizeX) or 0,
    image and math.max(0,image.size2.sizeY-canvas.size2.sizeY) or 0
end
local function redraw(regions)
  local maxX,maxY=limits()
  scrollbar.maxScroll=maxY scrollbar.visibleSize=canvas.size2.sizeY scrollbar.scroll=offsetY
  if image then
    details.text=string.format("%dx%dpx | %d,%d",image.size2.sizeX,image.size2.sizeY*2,offsetX+1,offsetY*2+1)
  else details.text="No image open" end
  local managed=wm and wm:getManagedWindow(frame)
  if managed and not frame.hidden then wm:renderRegions(regions or {wm:getWindowBounds(managed)}) end
end
local function resize(width,height)
  width=math.min(width,tgl.defaults.screenSizeX-4)
  height=math.min(math.ceil(height/2),tgl.defaults.screenSizeY-7)
  local w,h=width+4,height+6
  if frame.size2.sizeX==w and frame.size2.sizeY==h then return false end
  local managed=wm:getManagedWindow(frame)
  local oldBounds=wm:getWindowBounds(managed)
  frame:disableAll()
  local x=math.max(1,math.min(frame.size2.x1,tgl.defaults.screenSizeX-w+1))
  local y=math.max(1,math.min(frame.size2.y1,tgl.defaults.screenSizeY-h))
  frame.size2=tgl.Size2:new(x,y,w,h)
  local function box(object,bx,by,bw,bh)
    object.relsize2=tgl.Size2:new(bx,by,bw,bh)
    object.size2=tgl.Size2:new(bx,by,bw,bh)
  end
  box(canvas,2,4,width,height)
  box(scrollbar,width+2,4,1,height)
  scrollbar.hitArea=scrollbar.size2
  details.relpos2=tgl.Pos2:new(2,h-2) details.maxLength=w-3
  for _,button in ipairs({{"left","[<]",2},{"right","[>]",6},{"up","[^]",10},
    {"down","[v]",14},{"home","[Top left]",18}}) do
    local control=frame.objects[button[1]]
    control.text=button[2] control.relpos2=tgl.Pos2:new(button[3],h-1)
    control.hidden=button[1]=="home" and w<28
  end
  local bar=frame.objects.titlebar
  box(bar,1,1,w,1)
  bar.objects.close.relpos2=tgl.Pos2:new(w-2,1)
  bar.objects.min.relpos2=tgl.Pos2:new(w-6,1)
  bar.objects.title.maxLength=w-10
  bar.objects.title.text=windowTitle
  box(frame.objects.toolbar,1,2,w,1)
  frame:translate()
  local maxX,maxY=limits()
  offsetX=math.min(offsetX,maxX) offsetY=math.min(offsetY,maxY)
  if not closing then frame:enableAll() end
  redraw({oldBounds,wm:getWindowBounds(managed)})
  return true
end
local function customSize()
  local maxWidth=tgl.defaults.screenSizeX-4
  local maxHeight=(tgl.defaults.screenSizeY-7)*2
  local value=ltnotify.prompt("Custom size","Size in pixels (WIDTHxHEIGHT):\n"..
    "Width: 16-"..maxWidth.."  Height: 2-"..maxHeight.."\nOdd heights round up to a full row.")
  if not value or value:match("^%s*$") then return end
  local width,height=value:match("^%s*(%d+)%s*[xX]%s*(%d+)%s*$")
  width,height=tonumber(width),tonumber(height)
  if not width or not height or width<16 or width>maxWidth or height<2 or height>maxHeight then
    ltnotify.error("Custom size","Enter WIDTHxHEIGHT using whole numbers.\n"..
      "Width: 16-"..maxWidth.." pixels\nHeight: 2-"..maxHeight.." pixels")
    return
  end
  resize(width,height)
end
local function scroll(x,y)
  local maxX,maxY=limits()
  x=math.max(0,math.min(maxX,x)) y=math.max(0,math.min(maxY,y))
  if x==offsetX and y==offsetY then return end
  offsetX,offsetY=x,y
  redraw()
end
scrollbar.onChange=function(value) scroll(offsetX,value) end
local function openImage(value)
  if not value or value=="" then return end
  value=fs.canonical(value)
  local loaded,err=tmg.Image:load(value)
  if not loaded then ltnotify.error("Open image",tostring(err or "Could not load image.")) return end
  if image then image:unload() end
  image=loaded filename=value offsetX,offsetY=0,0
  image.autoPreload=false
  image.z_index=frame.z_index
  local title=fs.name(value)
  while unicode.wlen(title)>36 do title=unicode.sub(title,1,unicode.len(title)-1) end
  windowTitle="Image Viewer - "..title
  frame.objects.titlebar.objects.title.maxLength=frame.size2.sizeX-10
  frame.objects.titlebar.objects.title.text=windowTitle
  local selected=presets[#presets]
  for _,size in ipairs(presets) do
    if image.size2.sizeX<=size[1] and image.size2.sizeY*2<=size[2] then selected=size break end
  end
  if not resize(selected[1],selected[2]) then redraw() end
end
local function info()
  if not image then return end
  local name=unicode.sub(image.name,1,36)
  ltnotify.dialog("Image info","Name: "..name.."\n"..
    string.format("Size: %d x %d character cells\nColors: %d-bit\n",image.size2.sizeX,image.size2.sizeY,image.depth)..
    string.format("Pixels: %d x %d\n",image.size2.sizeX,image.size2.sizeY*2)..
    (image.extended and "Extended characters" or "Half-block pixels")..
    "\nTransparency: "..(image.mask and "Yes" or "No"),{"OK"})
end
local function rename()
  if not image then return end
  local value=ltnotify.prompt("Rename image","Current name: "..image.name.."\nNew picture name:")
  if not value or value:match("^%s*$") or value==image.name then return end
  if value:find("[\r\n]") then ltnotify.error("Rename image","Image name must fit on one line.") return end
  local previous=image.name
  image.name=value
  local saved,err=image:save(filename)
  if not saved then image.name=previous ltnotify.error("Rename image",tostring(err)) end
end
local ok,err=pcall(function()
  if path then openImage(path) else redraw() end
  if not closing then frame:enableAll() end
  while not closing do
    local ev,a,b,c,d=ltevent.pull()
    if ev==events.close or ev=="ltde_shutdown" then break end
    if ev==events.open then
      local value=ltnotify.prompt("Open image","Path to a .tmg file:")
      if value then openImage(value) end
    elseif ev==events.rename then rename()
    elseif ev==events.help then 
      ltnotify.dialog("Image Viewer Help","Pan image with buttons,\n"..
      "scrolling(shift-scroll for horizontal),\n"..
      "or arrow keys.\n"..
      "You can change app size in the View tab",{"OK"})
    elseif ev==events.about then
      ltnotify.dialog("Image Viewer","TMG Image viewer v"..version.."\ntgl-img version "..tmg.ver,{"OK"})
    elseif ev==events.custom then customSize()
    elseif ev==events.size then resize(a[1],a[2])
    elseif ev==events.info then info()
    elseif ev==events.home then scroll(0,0)
    elseif ev==events.left then scroll(offsetX-4,offsetY)
    elseif ev==events.right then scroll(offsetX+4,offsetY)
    elseif ev==events.up then scroll(offsetX,offsetY-1)
    elseif ev==events.down then scroll(offsetX,offsetY+1)
    elseif ev=="key_down" then
      if c==203 then scroll(offsetX-1,offsetY)
      elseif c==205 then scroll(offsetX+1,offsetY)
      elseif c==200 then scroll(offsetX,offsetY-1)
      elseif c==208 then scroll(offsetX,offsetY+1)
      elseif c==201 then scroll(offsetX,offsetY-canvas.size2.sizeY)
      elseif c==209 then scroll(offsetX,offsetY+canvas.size2.sizeY)
      elseif c==199 then scroll(0,0) end
    elseif ev=="scroll" and not frame.hidden and wm:getWindowAt(b,c)==wm:getManagedWindow(frame)
    and tgl.util.pointInSize2(b,c,canvas.size2) and tgl.util.pointInSize2(b,c,tgl.sys.activeArea) then
      if keyboard.isShiftDown() then scroll(offsetX-d*3,offsetY)
      else scroll(offsetX,offsetY-d*3) end
    end
  end
end)
frame:disableAll()
if image then image:unload() end
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
