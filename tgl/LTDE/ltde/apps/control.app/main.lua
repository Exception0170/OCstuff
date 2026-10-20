--LTDE Control Panel
local tgl=require("tgl")
local unicode=require("unicode")
local settings=assert(loadfile("/ltde/sys/slib/ltsettings.lua"))()
local session,err=settings.new()
if not session then ltnotify.error("Control Panel",tostring(err)) return 1 end
local uid=tostring(math.random(1,1000000))
local events={}
for _,name in ipairs({"close","page","field","color","apply","ok","cancel"}) do
  events[name]="control_"..name.."_"..uid
end
local gray=tgl.Color2:new(0,0xC3C3C3)
local white=tgl.Color2:new(0,0xFFFFFF)
local blue=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
local frame=ltwapi.addWindow(60,20,"Control Panel",{
  onClose=function() ltevent.push(events.close) end
})
if not frame then return 1 end
local pageIndex=1
local selected=nil
local editing=false
local restart=false
local status="Select a setting to edit."
local sidebar=tgl.Frame:new({},tgl.Size2:new(1,3,14,14),white)
local page=tgl.Frame:new({},tgl.Size2:new(15,3,45,14),gray)
frame:add(sidebar,"sidebar")
frame:add(page,"page")
local statusText=tgl.Text:new(status,gray,tgl.Pos2:new(2,17))
statusText.maxLength=58
frame:add(statusText,"status")
frame:add(tgl.EventButton("[ OK ]",events.ok,nil,tgl.Pos2:new(30,19),gray),"ok")
frame:add(tgl.EventButton("[ Cancel ]",events.cancel,nil,tgl.Pos2:new(39,19),gray),"cancel")
frame:add(tgl.EventButton("[ Apply ]",events.apply,nil,tgl.Pos2:new(50,19),gray),"apply")

local function fit(text,width)
  text=tostring(text)
  if unicode.wlen(text)>width then return unicode.sub(text,1,width-1).."~" end
  return text..string.rep(" ",width-unicode.wlen(text))
end

local function redraw()
  if frame.hidden then return end
  local wm=tgl.sys.wm
  local mwin=wm and wm:getManagedWindow(frame)
  if mwin then wm:renderRegions({wm:getWindowBounds(mwin)})
  else tgl.sys.renderer:stop() frame:render() tgl.sys.renderer:flush(true) end
end

local function buildPage()
  sidebar:disableAll()
  page:disableAll()
  sidebar.objects={}
  page.objects={}
  for i,definition in ipairs(session.pages) do
    sidebar:add(tgl.EventButton(fit(" "..definition.title,14),events.page,i,
      tgl.Pos2:new(1,i),i==pageIndex and blue or white),i)
  end
  local definition=session.pages[pageIndex]
  if definition then
    for i,field in ipairs(definition.fields) do
      local value=session.values[pageIndex][i]
      local label=fit(field.label,21)
      local text
      if field.kind=="boolean" then text=value and "[x]" or "[ ]"
      else text="["..tostring(value).."]" end
      page:add(tgl.EventButton(label..fit(text,21)..(field.restart and "*" or " "),
        events.field,i,tgl.Pos2:new(2,i),i==selected and blue or gray),"field"..i)
    end
    local field=definition.fields[selected]
    if field then
      local desc=field.desc
      if field.kind=="number" then desc=desc.." ("..field.min.."-"..field.max.." "..(field.unit or "")..")" end
      page:add(tgl.Text:new(fit(unicode.sub(desc,1,43),43),gray,tgl.Pos2:new(2,12)),"desc1")
      page:add(tgl.Text:new(fit(unicode.sub(desc,44,86),43),gray,tgl.Pos2:new(2,13)),"desc2")
      page:add(tgl.Text:new(field.restart and "* Requires restarting LTDE" or "Takes effect when applied",gray,tgl.Pos2:new(2,14)),"restart")
      if field.kind=="color" and editing then
        for i,color in ipairs(field.choices) do
          local value=tgl.defaults.colors16[color]
          local marker=session.values[pageIndex][selected]==color and "*" or " "
          local col=tgl.Color2:new((color=="white" or color=="yellow" or color=="lime" or color=="lightgray") and 0 or 0xFFFFFF,value)
          page:add(tgl.EventButton(fit(marker..color,10),events.color,color,
            tgl.Pos2:new(2+((i-1)%4)*11,5+math.floor((i-1)/4)),col),"color"..i)
        end
      end
    end
  end
  statusText.text=status
  frame:translate()
  frame:enableAll()
  frame.objects.apply.col2=session:dirty() and blue or gray
  redraw()
end

local function apply()
  if not session:dirty() then return true end
  local ok,reason,applied=session:apply()
  local wm=tgl.sys.wm
  local repaint=false
  for _,change in ipairs(applied) do
    if change.field.restart then restart=true end
    if wm and change.field.live=="wallpaper" then
      wm:setBackground(tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16[change.value]))
      repaint=true
    elseif wm and change.field.live=="drag_cursor" then wm._dragCursor=change.value end
  end
  if repaint then
    wm:renderRegions({tgl.Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY)})
  end
  if not ok then
    status="Some changes remain unapplied."
    ltnotify.error("Settings not saved",reason..(#applied>0 and " Earlier changes were saved." or ""))
  else
    status=restart and "Saved. Restart LTDE to apply starred settings." or "Settings applied."
  end
  buildPage()
  return ok
end

buildPage()
local ok,failure=pcall(function()
  while true do
    local ev,value=ltevent.pull()
    if ev==events.close or ev==events.cancel or ev=="ltde_shutdown" then break
    elseif ev==events.ok then
      if apply() then
        if restart then ltnotify.dialog("Control Panel","Settings saved. Restart LTDE to apply starred settings.",{"OK"}) end
        break
      end
    elseif ev==events.apply then apply()
    elseif ev==events.page and session.pages[value] then
      pageIndex=value selected=nil editing=false buildPage()
    elseif ev==events.field then
      local definition=session.pages[pageIndex]
      local field=definition and definition.fields[value]
      if field and selected~=value then
        selected=value
        editing=false
        status="Click the selected setting again to edit."
        buildPage()
      elseif field then
        editing=true
        buildPage()
        local current=session.values[pageIndex][value]
        if field.kind=="boolean" then session:set(pageIndex,value,not current)
        elseif field.kind~="color" then
          local entered=ltnotify.prompt(field.label,"Current: "..tostring(current).."\n"..
            (field.kind=="number" and "Enter "..field.min.."-"..field.max.." "..(field.unit or "")..":" or "Enter new value:"))
          if entered then
            local valid,why=session:set(pageIndex,value,entered)
            if not valid then ltnotify.warn("Invalid setting",why) end
          end
        end
        status=session:dirty() and "Changes have not been applied." or "No pending changes."
        buildPage()
      end
    elseif ev==events.color then
      local definition=session.pages[pageIndex]
      local field=definition and definition.fields[selected]
      if field and field.kind=="color" then
        local valid,why=session:set(pageIndex,selected,value)
        if valid then status="Changes have not been applied." buildPage()
        else ltnotify.warn("Invalid color",why) end
      end
    end
  end
end)
frame:disableAll()
ltwapi.removeWindow(frame)
if not ok then error(failure,0) end
return 0
