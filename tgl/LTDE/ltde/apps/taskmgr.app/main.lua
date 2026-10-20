--LTDE Task Manager
local tgl=require("tgl")
local computer=require("computer")
local unicode=require("unicode")
local uid=tostring(math.random(1,1000000))
local events={}
for _,name in ipairs({"close","select","refresh","switch","endtask","start","stop","restart"}) do
  events[name]="taskmgr_"..name.."_"..uid
end
if not _G.ltproc then ltnotify.error("Task Manager","Process service unavailable. Restart LTDE.") return 1 end
local gray=tgl.Color2:new(0,0xC3C3C3)
local white=tgl.Color2:new(0,0xFFFFFF)
local blue=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
local frame=ltwapi.addWindow(60,20,"Task Manager",{
  onClose=function() ltevent.push(events.close) end
})
if not frame then return 1 end
local selected=nil
local programs={}
local stamp=nil
local lastUpdate=-math.huge
local wm=tgl.sys.wm
local list=tgl.ScrollFrame:new({},tgl.Size2:new(2,5,58,10),white)
frame:add(list,"list")
local function fit(value,width)
  local text=tostring(value)
  if unicode.wlen(text)>width then return unicode.sub(text,1,width-1).."~" end
  return text..string.rep(" ",width-unicode.wlen(text))
end
local function row(id,name,state,windows)
  return fit(id,6)..fit(name,29)..fit(state,12)..fit(windows,10)
end
frame:add(tgl.Text:new("Applications and services",gray,tgl.Pos2:new(2,3)),"title")
frame:add(tgl.Text:new(row("PID","Name","State","Type"),gray,tgl.Pos2:new(2,4)),"header")
local ram=tgl.Text:new("",gray,tgl.Pos2:new(2,15)) ram.maxLength=58
local vram=tgl.Text:new("",gray,tgl.Pos2:new(2,16)) vram.maxLength=58
local status=tgl.Text:new("Select an application.",gray,tgl.Pos2:new(2,17)) status.maxLength=58
frame:add(ram,"ram") frame:add(vram,"vram") frame:add(status,"status")
frame:add(tgl.EventButton("[Refresh]",events.refresh,nil,tgl.Pos2:new(2,19),gray),"refresh")
frame:add(tgl.EventButton("[Switch To]",events.switch,nil,tgl.Pos2:new(13,19),gray),"switch")
frame:add(tgl.EventButton("[End Task]",events.endtask,nil,tgl.Pos2:new(27,19),gray),"endtask")
frame:add(tgl.EventButton("[Close]",events.close,nil,tgl.Pos2:new(51,19),gray),"close")

for i,action in ipairs({"start","stop","restart"}) do
  local label=action:sub(1,1):upper()..action:sub(2)
  frame:add(tgl.EventButton("["..label.." Service]",events[action],nil,tgl.Pos2:new(2+(i-1)*18,18),gray),action)
end

local function redraw(area)
  if frame.hidden then return end
  local mwin=wm and wm:getManagedWindow(frame)
  if mwin then wm:renderRegions({area or wm:getWindowBounds(mwin)})
  else tgl.sys.renderer:stop() frame:render() tgl.sys.renderer:flush(true) end
end

local function memory(label,total,free,unit)
  if type(total)~="number" or type(free)~="number" or total<=0 then return label..": unavailable" end
  local scale=unit=="KB" and 1024 or 1
  return string.format("%s: %.0f / %.0f %s used (%.0f free)",label,
    (total-free)/scale,total/scale,unit,free/scale)
end

local function update(force)
  local fresh,err=ltproc.list()
  if not fresh then error(err,0) end
  local parts={}
  local present=false
  for _,prog in ipairs(fresh) do
    local count=0
    for _,mwin in ipairs(wm and wm.pidWindows[prog.pid or prog.id] or {}) do
      if not mwin.noTaskbar then count=count+1 end
    end
    prog.windows=count
    if prog.id==selected then present=true end
    parts[#parts+1]=row(prog.pid or (prog.serviceId and "-" or prog.id),prog.name,prog.state or (prog.running and "Running" or "Stopped"),prog.kind=="service" and (prog.protected and "Protected" or "Service") or "App")
  end
  if not present then selected=nil end
  programs=fresh
  local newStamp=table.concat(parts,"\n")
  local changed=force or stamp~=newStamp
  if changed then
    stamp=newStamp
    local scroll=list.scroll
    list:disableAll()
    list.objects={}
    for i,prog in ipairs(programs) do
      list.objects[i]=tgl.EventButton(parts[i],events.select,prog.id,tgl.Pos2:new(1,i),prog.id==selected and blue or white)
      list.objects[i].onClick=nil
    end
    list.maxScroll=math.max(0,#programs-list.size2.sizeY)
    list.scroll=math.min(scroll,list.maxScroll)
    list:translate()
    if not frame.hidden then list:enableAll() end
  end
  local ramText=memory("RAM",computer.totalMemory(),computer.freeMemory(),"KB")
  local gpu=tgl.sys.renderer.gpu
  local ok,total,free=pcall(function()return gpu.totalMemory(),gpu.freeMemory()end)
  local vramText=ok and memory("GPU buffer",total,free,"cells") or "GPU buffer: unavailable"
  local statusText=#programs.." process/service entries"..(selected and "  |  Selected: "..selected or "  |  Select an application.")
  local footer=ram.text~=ramText or vram.text~=vramText or status.text~=statusText
  ram.text=ramText vram.text=vramText status.text=statusText
  if changed then redraw()
  elseif footer then redraw(tgl.Size2:new(frame.size2.x1+1,frame.size2.y1+14,58,3)) end
end

local function selectedProgram()
  for _,prog in ipairs(programs) do if prog.id==selected then return prog end end
end

frame:enableAll()
local ok,err=pcall(function()
  update(true)
  while true do
    local ev,value=ltevent.pull(1)
    if ev==events.close or ev=="ltde_shutdown" then break end
    if ev==events.select then selected=value update(true)
    elseif ev==events.switch then
      local prog=selectedProgram()
      local target=nil
      for _,mwin in ipairs(prog and wm and wm.pidWindows[prog.pid or prog.id] or {}) do
        if not mwin.noTaskbar then target=mwin break end
      end
      if target then
        if target.minimized then wm:restoreWindow(target) else wm:bringToFront(target) end
      else ltnotify.warn("Switch To","Select an application with an open window.") end
    elseif ev==events.start or ev==events.stop or ev==events.restart then
      local prog=selectedProgram()
      if not prog or not prog.serviceId then ltnotify.warn("Services","Select a service first.")
      else
        local action=ev==events.start and "start" or ev==events.stop and "stop" or "restart"
        local approved=action=="start" or ltnotify.dialog("Service control",
          action.." "..prog.name.."?",{"Cancel","Continue"})=="Continue"
        if approved then
          local changed,why=ltproc.service(action,prog.serviceId)
          if not changed then ltnotify.error("Service control",why) end
          update(true)
        end
      end
    elseif ev==events.endtask then
      local prog=selectedProgram()
      if not prog then ltnotify.warn("End Task","Select an application first.")
      elseif prog.serviceId then ltnotify.warn("Services","Use Stop Service for a graceful shutdown.")
      elseif prog.self then ltnotify.warn("Task Manager","Use Close to exit Task Manager.")
      elseif ltnotify.dialog("End Task","End "..prog.name.." (PID "..prog.id..")? Unsaved changes will be lost.",{"Cancel","End Task"})=="End Task" then
        local ended,why=ltproc.terminate(prog.id)
        if not ended then ltnotify.warn("End Task",why) end
        update(true)
      end
    end
    if ev==events.refresh or computer.uptime()-lastUpdate>=1 then
      lastUpdate=computer.uptime()
      update(ev==events.refresh)
    end
  end
end)
frame:disableAll()
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
