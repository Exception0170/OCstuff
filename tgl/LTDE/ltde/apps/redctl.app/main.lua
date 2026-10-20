--LTDE Redstone Control
local tgl=require("tgl")
local component=require("component")
local colors=require("colors")
local uid=tostring(math.random(1,1000000))
local events={}
for _,name in ipairs({"close","normal","bundled","device","side","channel","set","refresh"}) do
  events[name]="redctl_"..name.."_"..uid
end
local gray=tgl.Color2:new(0,0xD2D2D2)
local white=tgl.Color2:new(0,0xFFFFFF)
local blue=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
local frame=ltwapi.addWindow(46,22,"Redstone Control",{
  onClose=function() ltevent.push(events.close) end
})
if not frame then return 1 end
local wm=tgl.sys.wm
local side,channel=0,0
local bundled=false
local addresses={}
local address=nil
local stamp=nil
local sideNames={"Bottom","Top","Back","Front","Right","Left"}
local function button(label,event,x,y,key)
  local b=tgl.EventButton(label,event,nil,tgl.Pos2:new(x,y),gray)
  b.onClick=nil frame:add(b,key) return b
end
local normalTab=button("[ Normal ]",events.normal,2,3,"normal")
local bundledTab=button("[ Bundled ]",events.bundled,14,3,"bundled")
local deviceButton=button("[No redstone card]",events.device,2,5,"device")
local sideButton=button("Side: [Bottom v]",events.side,2,7,"side")
local heading=tgl.Text:new("",gray,tgl.Pos2:new(2,9)) frame:add(heading,"heading")
local list=tgl.ScrollFrame:new({},tgl.Size2:new(2,10,42,8),white) frame:add(list,"list")
button("[Set output]",events.set,2,19,"set")
button("[Refresh]",events.refresh,18,19,"refresh")
button("[Close]",events.close,36,19,"close")
local status=tgl.Text:new("",gray,tgl.Pos2:new(2,21)) status.maxLength=42 frame:add(status,"status")
local function scan()
  addresses={}
  for id in component.list("redstone",true) do addresses[#addresses+1]=id end
  table.sort(addresses)
  local found=false
  for _,id in ipairs(addresses) do if id==address then found=true end end
  if not found then address=addresses[1] end
end
local function read()
  if not address then return nil,"No redstone component available." end
  local ok,result=pcall(function()
    local proxy=component.proxy(address)
    local rows={}
    if bundled then
      if not proxy.getBundledInput or not proxy.getBundledOutput or not proxy.setBundledOutput then
        error("Bundled mode requires supported hardware.",0)
      end
      for color=0,15 do
        rows[#rows+1]={name=colors[color] or tostring(color),input=proxy.getBundledInput(side,color),output=proxy.getBundledOutput(side,color)}
      end
    else rows[1]={name="Signal",input=proxy.getInput(side),output=proxy.getOutput(side)} end
    for _,row in ipairs(rows) do
      if type(row.input)~="number" or type(row.output)~="number" then error("Signal reading unavailable.",0) end
    end
    return rows
  end)
  if not ok then return nil,tostring(result) end
  return result
end
local function redraw(force)
  local rows,err=read()
  local lines={}
  for _,row in ipairs(rows or {}) do
    lines[#lines+1]=string.format("%-12s %10.4g %10.4g",row.name,row.input,row.output)
  end
  local fresh=tostring(address)..":"..side..":"..tostring(bundled)..":"..channel..":"..tostring(err)..table.concat(lines)
  if not force and fresh==stamp then return end
  stamp=fresh
  normalTab.col2=bundled and gray or blue
  bundledTab.col2=bundled and blue or gray
  deviceButton.text=address and "Card: ["..address:sub(1,8).." v]" or "[No redstone card]"
  sideButton.text="Side: ["..sideNames[side+1].." v]"
  heading.text=string.format("%-12s %10s %10s",bundled and "Channel" or "Normal","Input","Output")
  status.text=err and "Unavailable - press Set for details." or (bundled and "Select a channel, then Set output." or "Vanilla: 0-15; modded levels may vary.")
  list:disableAll() list.objects={}
  for i,line in ipairs(lines) do
    local b=tgl.EventButton(line,events.channel,i-1,tgl.Pos2:new(1,i),bundled and channel==i-1 and blue or white)
    b.onClick=nil list.objects[i]=b
  end
  if not rows then list.objects[1]=tgl.Text:new(address and "This mode is unavailable." or "Insert or attach a redstone card.",white,tgl.Pos2:new(1,1)) end
  list.maxScroll=math.max(0,#lines-list.size2.sizeY)
  list.scroll=math.min(list.scroll,list.maxScroll)
  list:translate()
  if not frame.hidden then list:enableAll() end
  local managed=wm and wm:getManagedWindow(frame)
  if managed and not frame.hidden then wm:renderRegions({wm:getWindowBounds(managed)}) end
end
local function choose(anchor,items)
  local selected=ltwapi.showMenu(anchor.pos2,items,gray)
  return selected and selected.value
end
local function setOutput()
  local rows,why=read()
  if not rows then ltnotify.warn("Redstone Control",why) return end
  local target,addressSide,targetChannel,targetBundled=address,side,channel,bundled
  local current=rows[bundled and channel+1 or 1].output
  local value=ltnotify.prompt("Set output",sideNames[side+1]..(bundled and " / "..tostring(colors[channel]) or "").."\nCurrent: "..tostring(current).."\nEnter a non-negative integer.\nVanilla uses 0-15; bundled often uses 0-255.")
  if value==nil then return end
  value=tonumber(value)
  if not value or value~=value or value<0 or value>2147483647 or value~=math.floor(value) then
    ltnotify.warn("Set output","Enter an integer from 0 to 2147483647.") return
  end
  local ok,err=pcall(function()
    local proxy=component.proxy(target)
    local result,reason
    if targetBundled then result,reason=proxy.setBundledOutput(addressSide,targetChannel,value)
    else result,reason=proxy.setOutput(addressSide,value) end
    if result==nil or result==false then error(reason or "Output could not be set.",0) end
  end)
  if not ok then ltnotify.warn("Set output",tostring(err)) end
end
local ok,err=pcall(function()
  scan() redraw(true) frame:enableAll()
  while true do
    local ev,a=ltevent.pull(0.75)
    if ev==events.close or ev=="ltde_shutdown" then break end
    local force=false
    if ev==events.normal or ev==events.bundled then bundled=ev==events.bundled list.scroll=0 force=true
    elseif ev==events.channel then channel=a force=true
    elseif ev==events.side then
      local items={}
      for i,name in ipairs(sideNames) do items[i]={label=name,value=i-1} end
      local value=choose(sideButton,items)
      if value~=nil then side=value end
      force=true
    elseif ev==events.device then
      scan()
      local items={}
      for _,id in ipairs(addresses) do items[#items+1]={label=id:sub(1,8),value=id} end
      if #items>0 then address=choose(deviceButton,items) or address end
      force=true
    elseif ev==events.set then setOutput() force=true
    elseif ev==events.refresh or ev=="component_added" or ev=="component_removed" then scan() force=true end
    if force or ev==nil or (ev=="redstone_changed" and a==address) then redraw(force) end
  end
end)
frame:disableAll()
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
