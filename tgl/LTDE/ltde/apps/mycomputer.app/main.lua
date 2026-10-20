--LTDE My Computer
local tgl=require("tgl")
local computer=require("computer")
local component=require("component")
local unicode=require("unicode")
local uid=tostring(math.random(1,1000000))
local close="mycomputer_close_"..uid
local refresh="mycomputer_refresh_"..uid
local gray=tgl.Color2:new(0,0xD2D2D2)
local white=tgl.Color2:new(0,0xFFFFFF)
local frame=ltwapi.addWindow(44,20,"My Computer",{
  onClose=function() ltevent.push(close) end
})
if not frame then return 1 end
local wm=tgl.sys.wm
local function fit(value,width)
  local text=tostring(value or "Unknown")
  while unicode.wlen(text)>width do text=unicode.sub(text,1,unicode.len(text)-1) end
  return text
end
local function label(key,text,y)
  local obj=tgl.Text:new(fit(text,40),gray,tgl.Pos2:new(2,y))
  frame:add(obj,key)
  return obj
end
label("heading","LTDE "..tostring(_G._ltde_version or ""),3)
label("system",tostring(_OSVERSION or "OpenOS"),4)
local cpu=label("cpu","",6)
local ram=label("ram","",7)
local display=label("display","",8)
local uptime=label("uptime","",9)
local devices=label("devices","",11)
local list=tgl.ScrollFrame:new({},tgl.Size2:new(2,12,40,6),white)
frame:add(list,"components")
frame:add(tgl.EventButton("[Refresh]",refresh,nil,tgl.Pos2:new(2,19),gray),"refresh")
frame:add(tgl.EventButton("[Close]",close,nil,tgl.Pos2:new(35,19),gray),"close")
local function update()
  local ok,arch=pcall(function() return computer.getArchitecture() end)
  cpu.text=fit("Processor: "..(ok and tostring(arch) or "Unknown"),40)
  ram.text=string.format("Memory: %.0f KB, %.0f KB free",computer.totalMemory()/1024,computer.freeMemory()/1024)
  local gpu=tgl.sys.renderer.gpu
  local w,h=gpu.getResolution()
  display.text=string.format("Display: %d x %d, %d-bit color",w,h,gpu.getDepth())
  local seconds=math.floor(computer.uptime())
  uptime.text=string.format("Uptime: %dh %02dm %02ds",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
  local items={}
  for address,kind in component.list() do table.insert(items,{address=address,kind=kind}) end
  table.sort(items,function(a,b)
    if a.kind==b.kind then return a.address<b.address end
    return a.kind<b.kind
  end)
  devices.text="Installed components ("..#items..")"
  list:disableAll()
  list.objects={}
  for i,item in ipairs(items) do
    local name=fit(item.kind,24)
    local text=name..string.rep(" ",25-unicode.wlen(name))..item.address:sub(1,8)
    list.objects[i]=tgl.Text:new(text,white,tgl.Pos2:new(1,i))
  end
  if #items==0 then list.objects[1]=tgl.Text:new("No components found.",white,tgl.Pos2:new(1,1)) end
  list.maxScroll=math.max(0,#items-list.size2.sizeY)
  list.scroll=math.min(list.scroll,list.maxScroll)
  list:translate()
  if not frame.hidden then list:enableAll() end
  local managed=wm and wm:getManagedWindow(frame)
  if managed and not frame.hidden then wm:renderRegions({wm:getWindowBounds(managed)}) end
end
local ok,err=pcall(function()
  update()
  frame:enableAll()
  while true do
    local ev=ltevent.pull()
    if ev==close or ev=="ltde_shutdown" then break end
    if ev==refresh or ev=="component_added" or ev=="component_removed" then update() end
  end
end)
frame:disableAll()
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
