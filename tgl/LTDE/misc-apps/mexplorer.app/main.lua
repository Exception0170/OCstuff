--LTDE ME network client
local tgl=require("tgl")
local tui=require("tgl-ui")
local unicode=require("unicode")
local computer=require("computer")
local fs=require("filesystem")
local network=assert(loadfile("/ltde/apps/mexplorer.app/network.lua"))()
local me=network:new()
local uid=tostring(math.random(1,1000000))
local events={}
for _,name in ipairs({"close","connect","export","refresh","auto","tab","search","sort","select","details","nbt","craft","requests","cancel","help","about"}) do
  events[name]="mexplorer_"..name.."_"..uid
end
if tgl.defaults.screenSizeX<72 or tgl.defaults.screenSizeY<23 then
  ltnotify.error("MExplorer","A screen of at least 72x23 characters is required.") return 1
end
local gray=tgl.Color2:new(0,0xD2D2D2)
local white=tgl.Color2:new(0,0xFFFFFF)
local blue=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
local barColor=tgl.Color2:new(tgl.defaults.colors16.darkblue,0xFFFFFF)
local closing=false
local frame=ltwapi.addWindow(72,22,"MExplorer",{
  toolbar=true,onClose=function() closing=true ltevent.push(events.close) end,
  menuItems={
    {label="File",items={{label="Connect...",eventName=events.connect},{label="Export inventory...",eventName=events.export},
      {label="Close",eventName=events.close}}},
    {label="View",items={{label="Refresh     F5",eventName=events.refresh},{label="[x] Auto-refresh status",eventName=events.auto}}},
    {label="Help",items={{label="Help",eventName=events.help},{label="About",eventName=events.about}}}
  }
})
if not frame then return 1 end
local wm=tgl.sys.wm
local page="overview"
local requestView=false
local auto=true
local lastPoll=-math.huge
local filtered={}
local views={}
local notice="Connect an Adapter to an ME Interface or Controller."
local modalSerial=0
local function fit(value,width)
  local text=tostring(value or ""):gsub("[%c]"," ")
  if unicode.wlen(text)>width then return unicode.sub(text,1,width-1).."~" end
  return text..string.rep(" ",width-unicode.wlen(text))
end
local function amount(value)
  local text=string.format("%.0f",tonumber(value) or 0)
  local sign,digits=text:match("^(%-?)(%d+)$")
  if not digits then return text end
  return sign..digits:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
end
local function addText(key,text,x,y,width,parent)
  local object=tgl.Text:new(text,gray,tgl.Pos2:new(x,y)) object.maxLength=width
  local target=parent or frame
  target:add(object,key) return object
end
local function addButton(key,text,event,value,x,y,parent)
  local object=tgl.EventButton(text,event,value,tgl.Pos2:new(x,y),gray)
  object.onClick=nil
  local target=parent or frame
  target:add(object,key) return object
end
local tabs={}
for _,entry in ipairs({{"overview","Overview",2},{"items","Items",15},{"fluids","Fluids",25},{"craftables","Crafting",36},{"cpus","CPUs",50}}) do
  tabs[entry[1]]=addButton(entry[1],"["..entry[2].."]",events.tab,entry[1],entry[3],3)
end
local deviceText=addText("device","Not connected",2,4,68)
local findLabel=addText("findLabel","Find:",2,5,5)
local search=tgl.InputField:new(string.rep(" ",33),tgl.Pos2:new(8,5),white)
search.erase=false search.scrollX=true search.stopOnClickOutside=true search.restrictActiveArea=false
search.stopEventName=events.close search.eventName=events.search frame:add(search,"search")
local sort=addButton("sort","[Sort: name]",events.sort,nil,44,5)
local requests=addButton("requests","[Requests]",events.requests,nil,59,5)
local header=addText("header","",2,6,67)
local list=tgl.Frame:new({},tgl.Size2:new(2,7,67,11),white) frame:add(list,"list")
local rows={}
for i=1,11 do rows[i]=addButton("row"..i,"",events.select,i,1,i,list) end
local scrollbar=tgl.Scrollbar:new(tgl.Size2:new(69,7,1,11),gray) frame:add(scrollbar,"scrollbar")
local details=addText("details","",2,18,68)
local detailButton=addButton("detailsButton","[Details]",events.details,nil,2,19)
local craftButton=addButton("craftButton","[Craft...]",events.craft,nil,14,19)
local cancelButton=addButton("cancelButton","[Cancel request]",events.cancel,nil,14,19)
local nbtButton=addButton("nbtButton","[View NBT]",events.nbt,nil,28,19)
addButton("refresh","[Refresh]",events.refresh,nil,59,19)
local progress=tui.Progressbar:new(tgl.Pos2:new(2,20),18,barColor) frame:add(progress,"progress")
local progressText=addText("progressText","",22,20,48)
local status=addText("status","",2,21,68)
local overview=tgl.Frame:new({},tgl.Size2:new(2,5,68,13),gray) frame:add(overview,"overviewPanel")
local overviewLines={}
for _,y in ipairs({1,3,5,7,8,9,10}) do overviewLines[y]=addText("line"..y,"",1,y,68,overview) end
local energyBar=tui.Progressbar:new(tgl.Pos2:new(1,2),28,tgl.Color2:new(tgl.defaults.colors16.darkgreen,0xFFFFFF))
overview:add(energyBar,"energyBar")
local cpuBar=tui.Progressbar:new(tgl.Pos2:new(1,6),28,barColor) overview:add(cpuBar,"cpuBar")
local function key() return requestView and page=="craftables" and "requests" or page end
local function view()
  local name=key()
  views[name]=views[name] or {query="",sort="name",scroll=0}
  return views[name]
end
local function redraw(area)
  local managed=wm and wm:getManagedWindow(frame)
  if managed and not frame.hidden then wm:renderRegions({area or wm:getWindowBounds(managed)}) end
end
local function ratio(part,total) return total and total>0 and math.max(0,math.min(1,(part or 0)/total)) or 0 end
local function selected()
  for _,row in ipairs(filtered) do if row.key==view().selected then return row end end
end
local function rebuild()
  local state=view()
  local kind=key()
  local isOverview=page=="overview"
  frame:disableAll()
  for name,button in pairs(tabs) do button.col2=name==page and blue or gray end
  overview.hidden=not isOverview
  for _,object in ipairs({findLabel,search,sort,header,list,scrollbar}) do object.hidden=isOverview end
  requests.hidden=page~="craftables" requests.text=requestView and "[Recipes]" or "[Requests]"
  detailButton.hidden=isOverview
  craftButton.hidden=page~="items" and not (page=="craftables" and not requestView)
  cancelButton.hidden=kind~="requests"
  nbtButton.hidden=page~="items" and not (page=="craftables" and not requestView)
  progress.hidden=true progressText.text=""
  deviceText.text=me.address and "ME: "..me.address or "ME: not connected"
  filtered={}
  if isOverview then for _,button in ipairs(rows) do button.hidden=true end end
  if isOverview then
    local p=me.power
    local busy=0 for _,cpu in ipairs(me.cpus) do if cpu.busy then busy=busy+1 end end
    overviewLines[1].text=p.stored and p.maximum and "Energy: "..amount(p.stored).." / "..amount(p.maximum).." AE  ("..
      string.format("%.0f%%",ratio(p.stored,p.maximum)*100)..")" or "Energy: unavailable"
    energyBar:setValue(ratio(p.stored,p.maximum))
    local function power(value)return value and string.format("%.2f",value) or "?" end
    overviewLines[3].text="Input: "..power(p.input).."  Usage: "..power(p.usage).."  Idle: "..power(p.idle).." AE/t"
    overviewLines[5].text="CPUs busy: "..busy.." / "..#me.cpus
    cpuBar:setValue(ratio(busy,#me.cpus))
    overviewLines[8].text="Items: "..(me.items and #me.items or "not loaded").."  Fluids: "..(me.fluids and #me.fluids or "not loaded")
    overviewLines[9].text="Craftables: "..(me.craftables and #me.craftables or "not loaded").."  Requests: "..#me.requests
    overviewLines[10].text="Name a CPU block in an Anvil to select that CPU for crafts."
    details.text="Auto-refresh: "..(auto and "status every 2 seconds" or "off").."; inventory refresh is manual."
  else
    search.text=state.query sort.text=state.sort=="name" and "[Sort: name]" or "[Sort: amount]"
    local query=unicode.lower(state.query)
    for _,row in ipairs(me[kind] or {}) do
      if unicode.lower(row.label.." "..row.name):find(query,1,true) then filtered[#filtered+1]=row end
    end
    table.sort(filtered,function(a,b)
      if state.sort=="amount" and (a.quantity or a.storage or 0)~=(b.quantity or b.storage or 0) then
        return (a.quantity or a.storage or 0)>(b.quantity or b.storage or 0)
      end
      local an,bn=unicode.lower(a.label),unicode.lower(b.label)
      if an==bn then return a.key<b.key end return an<bn
    end)
    state.scroll=math.max(0,math.min(state.scroll,math.max(0,#filtered-11)))
    scrollbar.scroll=state.scroll scrollbar.visibleSize=11 scrollbar.maxScroll=math.max(0,#filtered-11)
    if kind=="cpus" then header.text=fit("CPU",30)..fit("Storage",14)..fit("Co-proc.",11).."State"
    elseif kind=="requests" then header.text=fit("Requested item",39)..fit("Amount",14).."State"
    else header.text=fit("Name",43)..fit(kind=="fluids" and "Amount (mB)" or kind=="craftables" and "Batch" or "Amount",15)..(kind=="items" and "Craft" or "") end
    for i,button in ipairs(rows) do
      local row=filtered[state.scroll+i]
      button.hidden=not row
      if row then
        if kind=="cpus" then button.text=fit(row.label,30)..fit(amount(row.storage).." B",14)..fit(row.coprocessors,11)..fit(row.busy and "Busy" or "Idle",11)
        elseif kind=="requests" then button.text=fit(row.label,39)..fit(amount(row.quantity),14)..fit(row.state,13)
        else button.text=fit(row.label,43)..fit(amount(row.quantity),15)..fit(kind=="items" and (row.craftable and "Yes" or "No") or "",8) end
        button.col2=row.key==state.selected and blue or white
      end
    end
    local row=selected()
    details.text=row and (row.name..(row.damage and " / "..row.damage or "")..(row.error and " | "..row.error or "")) or (#filtered.." entries; click to select.")
    if kind=="cpus" then
      local busy=0 for _,cpu in ipairs(me.cpus) do if cpu.busy then busy=busy+1 end end
      progressText.text=busy.." / "..#me.cpus.." CPUs busy"
    elseif kind=="requests" then
      local completed=0 for _,job in ipairs(me.requests) do if job.state=="Complete" then completed=completed+1 end end
      progressText.text=completed.." / "..#me.requests.." requests completed"
    else progress.hidden=true progressText.text=me.times[kind] and "Loaded: "..me.times[kind] or "Not loaded" end
  end
  local err=me.errors[key()]
  status.text=err and "STALE: "..tostring(err) or notice
  if not closing and not frame.hidden then frame:enableAll() end
  redraw()
end
scrollbar.onChange=function(value) view().scroll=value rebuild() end
local function choose(title,choices)
  if #choices==0 then return nil end
  modalSerial=modalSerial+1
  local done="mexplorer_choose_"..uid.."_"..modalSerial
  local height=math.min(10,#choices)+5
  local popup=tgl.Frame:new({},tgl.Size2:new(math.floor((tgl.defaults.screenSizeX-54)/2)+1,
    math.floor((tgl.defaults.screenSizeY-height)/2)+1,54,height),gray)
  popup.borders="─│┌┐└┘"
  local titlebar=tgl.Frame:new({},tgl.Size2:new(2,2,52,1),blue)
  titlebar:add(tgl.Text:new(fit(title,50),blue,tgl.Pos2:new(1,1)),"title") popup:add(titlebar,"titlebar")
  local options=tgl.ScrollFrame:new({},tgl.Size2:new(3,3,49,height-5),white)
  for i,choice in ipairs(choices) do
    local button=tgl.EventButton(fit(choice.label,48),done,i,tgl.Pos2:new(1,i),white)
    button.onClick=nil options.objects[i]=button
  end
  options.maxScroll=math.max(0,#choices-(height-5)) popup:add(options,"options")
  addButton("cancel","[Cancel]",done,nil,3,height-1,popup)
  local state=ltnotify.openModal(popup)
  local ok,result=pcall(function()
    while not closing do
      local ev,value,_,code=ltevent.pull(0.5)
      if ev==done then return value end
      if ev=="ltde_shutdown" or ev==events.close then closing=true return end
      if ev=="key_down" and code==1 then return end
    end
  end)
  ltnotify.closeModal(popup,state)
  if not ok then error(result,0) end
  return result and choices[result].value
end
local function work(title,fn,cancellable)
  local canceled=false
  local popup=tgl.Frame:new({},tgl.Size2:new(math.floor((tgl.defaults.screenSizeX-48)/2)+1,
    math.floor((tgl.defaults.screenSizeY-7)/2)+1,48,7),gray)
  popup.borders="─│┌┐└┘"
  local titlebar=tgl.Frame:new({},tgl.Size2:new(2,2,44,1),blue)
  titlebar:add(tgl.Text:new(fit(title,43),blue,tgl.Pos2:new(1,1)),"title") popup:add(titlebar,"titlebar")
  local text=addText("text","",3,3,43,popup)
  local bar=tui.Progressbar:new(tgl.Pos2:new(3,4),42,barColor) popup:add(bar,"bar")
  local count=addText("count","Working...",3,5,43,popup)
  local cancel=tgl.Button:new("[Cancel]",function() canceled=true end,tgl.Pos2:new(3,6),gray)
  cancel.onClick=nil cancel.hidden=cancellable==false popup:add(cancel,"cancel")
  local state=ltnotify.openModal(popup)
  local function update(label,done,total)
    if canceled or closing then error("Canceled.",0) end
    text.text=label bar.hidden=not total
    if total then bar:setValue(ratio(done,total)) end
    count.text=total and (done.." / "..total) or "Waiting for ME network..."
    wm:renderRegions({popup.size2}) os.sleep(0)
    if canceled or closing then error("Canceled.",0) end
  end
  local ok,result,err=pcall(fn,update)
  ltnotify.closeModal(popup,state)
  if not ok then return nil,tostring(result) end
  return result,err
end
local function refresh(kind)
  if not me.proxy then notice="No ME component connected." rebuild() return end
  local ok,err
  local function update(label,done,total)
    if closing then error("Canceled.",0) end
    progress.hidden=not total
    if total then progress:setValue(ratio(done,total)) end
    progressText.text=label..(total and "  "..done.." / "..total or "")
    redraw(tgl.Size2:new(progress.pos2.x,progress.pos2.y,68,1)) os.sleep(0)
  end
  local success,result,why=pcall(function()
    if kind=="overview" or kind=="cpus" or kind=="requests" then update("Refreshing status...",0,nil) return me:poll() end
    return me:refresh(kind,update)
  end)
  if success then ok,err=result,why else ok,err=nil,tostring(result) end
  notice=ok and "Refreshed "..kind.."." or tostring(err)
  if not ok and not closing and err~="Canceled." then ltnotify.error("Refresh failed",tostring(err)) end
  rebuild()
end
local function connect()
  local ok,devices=pcall(network.devices)
  if not ok then ltnotify.error("ME connection",tostring(devices)) return end
  local choices={}
  for _,device in ipairs(devices) do choices[#choices+1]={label=device.kind.."  "..device.address,value=device.address} end
  if #choices==0 then ltnotify.error("ME connection","No ME component found. Connect an Adapter to an ME Interface or Controller.") return end
  local address=choose("Connect to ME network",choices)
  if not address then return end
  local connected,err=me:connect(address)
  if not connected then ltnotify.error("ME connection",err) return end
  views={} notice="Connected to "..address me:poll() lastPoll=computer.uptime()
  refresh(key())
end
local function info()
  local row=selected()
  if not row then notice="Select an entry first." rebuild() return end
  local text
  if key()=="cpus" then text="CPU: "..row.label.."\nStorage: "..amount(row.storage).." bytes\nCo-processors: "..row.coprocessors.."\nState: "..(row.busy and "Busy" or "Idle")
  elseif key()=="requests" then text=row.label.."\nQuantity: "..amount(row.quantity).."\nCPU: "..row.cpu.."\nState: "..row.state.."\nNetwork: "..tostring(row.address)..(row.error and "\n"..row.error or "")
  else text=row.label.."\nID: "..row.name.."\n"..(row.damage and "Damage: "..row.damage.."\n" or "")..
    (key()=="craftables" and "Recipe output: " or "Stored: ")..amount(row.quantity)..(page=="fluids" and " mB" or "")..
    (row.craftable~=nil and "\nCraftable: "..(row.craftable and "Yes" or "No").."\nNBT: "..(row.nbt and "Yes" or "No") or "") end
  ltnotify.dialog("ME details",text,{"OK"})
end
local function viewNBT()
  local row=selected()
  if not row then notice="Select an item first." rebuild() return end
  local nbt=assert(loadfile("/ltde/apps/mexplorer.app/nbt.lua"))()
  local lines=nbt.describe(row)
  local wrapped={}
  for _,line in ipairs(lines) do
    repeat
      wrapped[#wrapped+1]=line:sub(1,57)
      line=line:sub(58)
    until line=="" or #wrapped>=512
    if #wrapped>=512 then wrapped[#wrapped+1]="<display truncated>" break end
  end
  modalSerial=modalSerial+1
  local done="mexplorer_nbt_"..uid.."_"..modalSerial
  local popup=tgl.Frame:new({},tgl.Size2:new(math.floor((tgl.defaults.screenSizeX-64)/2)+1,
    math.floor((tgl.defaults.screenSizeY-20)/2)+1,64,20),gray)
  popup.borders="─│┌┐└┘"
  local titlebar=tgl.Frame:new({},tgl.Size2:new(2,2,62,1),blue)
  titlebar:add(tgl.Text:new(fit("NBT: "..row.label,60),blue,tgl.Pos2:new(1,1)),"title") popup:add(titlebar,"titlebar")
  addText("hint","Read only; item data from the last refresh.",3,3,59,popup)
  local content=tgl.ScrollFrame:new({},tgl.Size2:new(3,4,59,13),white)
  for i,line in ipairs(wrapped) do content.objects[i]=tgl.Text:new(line,white,tgl.Pos2:new(1,i)) end
  content.maxScroll=math.max(0,#wrapped-13) popup:add(content,"nbt")
  addButton("close","[Close]",done,nil,3,19,popup)
  local state=ltnotify.openModal(popup)
  local ok,err=pcall(function()
    while not closing do
      local ev,_,_,code=ltevent.pull(0.5)
      if ev==done or ev=="key_down" and code==1 then break end
      if ev=="ltde_shutdown" or ev==events.close then closing=true break end
    end
  end)
  ltnotify.closeModal(popup,state)
  if not ok then error(err,0) end
end
local function craft()
  local row=selected()
  if not row then notice="Select a craftable item first." rebuild() return end
  local recipe,err=me:recipeFor(row)
  if not recipe then ltnotify.error("Craft item",err) return end
  local quantity=ltnotify.prompt("Craft "..fit(row.label,32),"Quantity to request (1-2147483647):")
  if not quantity then return end
  quantity=tonumber(quantity)
  if not quantity or quantity%1~=0 or quantity<1 or quantity>2147483647 then ltnotify.error("Craft item","Enter a positive whole quantity up to 2147483647.") return end
  local choices={{label="Automatic CPU selection",value=""}}
  me:poll()
  if me.errors.cpus then ltnotify.error("Crafting CPUs",me.errors.cpus) return end
  for _,cpu in ipairs(me.cpus) do
    choices[#choices+1]={label=cpu.label..(cpu.name=="" and " - name required" or
      "  "..amount(cpu.storage).." B"..(cpu.busy and " (busy)" or " (idle)")),value=cpu}
  end
  local cpu=choose("Crafting CPU",choices)
  if cpu==nil then return end
  if type(cpu)=="table" then
    if cpu.name=="" then
      ltnotify.error("Unnamed CPU","This CPU has no AE2 name. Rename one of its blocks in an Anvil, place it back, and refresh.\nAutomatic selection can use unnamed CPUs.") return
    end
    cpu=cpu.name
  end
  local job
  job,err=work("Submitting craft request",function(update)
    update("Submitting "..amount(quantity).." items...",0,nil)
    return me:request(recipe,quantity,cpu~="" and cpu or nil)
  end,false)
  if not job then ltnotify.error("Craft request",tostring(err)) return end
  page="craftables" requestView=true view().selected=job.key view().scroll=math.max(0,#me.requests-11)
  notice="Request submitted; planning may take a moment." rebuild()
end
local function export()
  local scope=choose("Export inventory",{{label="Items (CSV)",value="items"},{label="Fluids (CSV, mB)",value="fluids"},
    {label="Craftables (CSV)",value="craftables"},{label="Full snapshot (Lua)",value="snapshot"}})
  if not scope then return end
  if scope=="snapshot" then
    for _,kind in ipairs({"items","fluids","craftables"}) do
      if not me[kind] then refresh(kind) if not me[kind] then return end end
    end
    me:poll()
  elseif not me[scope] then refresh(scope) if not me[scope] then return end end
  local path=ltnotify.prompt("Export "..scope,"Destination file path:\nExample: /home/me-"..scope..(scope=="snapshot" and ".lua" or ".csv").."\nExports the last loaded data, including stale entries.")
  if not path or path:match("^%s*$") then return end
  path=fs.canonical(path)
  local overwrite=fs.exists(path)
  if overwrite and ltnotify.dialog("Replace file?",path,{"Replace","Cancel"})~="Replace" then return end
  local ok,err=work("Exporting inventory",function(update)return me:export(path,scope,overwrite,update)end)
  notice=ok and "Exported to "..path or tostring(err)
  if not ok and err~="Canceled." then ltnotify.error("Export failed",tostring(err)) end
  rebuild()
end
local shutdown=function() closing=true end
local function statusStamp()
  local parts={}
  for _,name in ipairs({"stored","maximum","input","usage","idle"}) do
    parts[#parts+1]=name..":"..tostring(me.power[name])..":"..tostring(me.errors[name])
  end
  parts[#parts+1]=tostring(me.errors.cpus)
  for _,cpu in ipairs(me.cpus) do parts[#parts+1]=cpu.key..tostring(cpu.busy)..cpu.storage..":"..cpu.coprocessors end
  for _,job in ipairs(me.requests) do parts[#parts+1]=job.state..tostring(job.error) end
  return table.concat(parts,"|")
end
ltevent.listen("ltde_shutdown",shutdown)
local ok,err=pcall(function()
  local scanned,devices=pcall(network.devices)
  if not scanned then notice="Component scan failed: "..tostring(devices)
  elseif #devices==1 then
    local connected,why=me:connect(devices[1].address)
    if connected then
      local polled,pollErr=me:poll() notice=polled and "Connected. Choose Items or Crafting to browse." or "Status unavailable: "..pollErr
    else notice=tostring(why) end
  elseif #devices>1 then notice="Multiple ME components found. Use File > Connect." end
  rebuild()
  while not closing do
    local ev,a,b,c,d=ltevent.pull(0.5)
    if ev==events.close or ev=="ltde_shutdown" then break end
    if ev==events.connect then connect()
    elseif ev==events.tab then
      page=a search.text=view().query
      if (page=="items" or page=="fluids" or page=="craftables") and not me[key()] then refresh(key()) else rebuild() end
    elseif ev==events.search then view().query=tostring(a or "") view().scroll=0 rebuild()
    elseif ev==events.sort then view().sort=view().sort=="name" and "amount" or "name" rebuild()
    elseif ev==events.select then
      local row=filtered[view().scroll+a] view().selected=row and row.key or nil rebuild()
    elseif ev==events.details then info()
    elseif ev==events.nbt then viewNBT()
    elseif ev==events.craft then craft()
    elseif ev==events.requests then requestView=not requestView rebuild() if not me[key()] then refresh(key()) end
    elseif ev==events.cancel then
      local row=selected()
      if row and ltnotify.dialog("Cancel crafting?",row.label,{"Cancel request","Keep running"})=="Cancel request" then
        local canceled,why=me:cancel(row)
        if not canceled then ltnotify.error("Cancel request",why) end
        rebuild()
      elseif not row then notice="Select a request first." rebuild() end
    elseif ev==events.export then export()
    elseif ev==events.refresh or ev=="key_down" and c==63 then refresh(key())
    elseif ev=="key_down" and page~="overview" and search.enabled then
      local delta=({[200]=-1,[208]=1,[201]=-11,[209]=11})[c]
      if delta or c==199 or c==207 then
        local state=view()
        local index=state.scroll+1
        for i,row in ipairs(filtered) do if row.key==state.selected then index=i break end end
        index=math.max(1,math.min(#filtered,c==199 and 1 or c==207 and #filtered or index+(delta or 0)))
        state.selected=filtered[index] and filtered[index].key or nil
        state.scroll=math.max(0,math.min(index-1,math.max(state.scroll,index-11)))
        rebuild()
      end
    elseif ev==events.auto then
      auto=not auto
      ltwapi.setMenuItems(frame,"View",{{label="Refresh     F5",eventName=events.refresh},
        {label=(auto and "[x]" or "[ ]").." Auto-refresh status",eventName=events.auto}})
      rebuild()
    elseif ev==events.help then
      ltnotify.dialog("MExplorer help","Connect an OC Adapter to an ME Interface or Controller.\n"..
        "Items/Fluids: search locally, sort and scroll. F5 refreshes.\n"..
        "Crafting: choose a recipe, quantity and CPU.\n"..
        "For named CPU selection, rename one of its blocks in an Anvil.\n"..
        "View NBT shows available tags and item metadata.\n"..
        "Requests tracks jobs submitted in this app session.\n"..
        "Cancellation depends on your component version.\n"..
        "Power/CPU/request status polls every 2 seconds.\n"..
        "Inventory refresh is manual; failed reads keep stale data.\n"..
        "File > Export saves loaded lists as CSV or a Lua snapshot.\n"..
        "Closing MExplorer does not cancel running crafts.",{"OK"})
    elseif ev==events.about then ltnotify.dialog("MExplorer","MExplorer 0.1\nAE2 ME client for LTDEv1",{"OK"})
    elseif ev=="scroll" and page~="overview" and wm:getWindowAt(b,c)==wm:getManagedWindow(frame)
    and tgl.util.pointInSize2(b,c,list.size2) and tgl.util.pointInSize2(b,c,tgl.sys.activeArea) then
      view().scroll=math.max(0,math.min(scrollbar.maxScroll,view().scroll-d*3)) rebuild()
    end
    if auto and me.proxy and computer.uptime()-lastPoll>=2 and not closing then
      lastPoll=computer.uptime()
      local old=statusStamp()
      local polled,why=me:poll()
      if not polled then notice="Status unavailable: "..why
      elseif notice:sub(1,19)=="Status unavailable:" then notice="Status refreshed." end
      if old~=statusStamp() then
        if page=="overview" or key()=="cpus" or key()=="requests" then
          if page=="overview" or search.enabled then rebuild() end
        else
          status.text=me.errors[key()] and "STALE: "..me.errors[key()] or notice
          redraw(tgl.Size2:new(status.pos2.x,status.pos2.y,68,1))
        end
      end
    end
  end
end)
closing=true frame:disableAll() ltevent.ignore("ltde_shutdown",shutdown)
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
