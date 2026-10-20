local event=require("event")
local unicode=require("unicode")
local tgl=require("tgl")
local computer=require("computer")
local ltnotify={}
ltnotify._dlgID=0
ltnotify._notifySlots={}
ltnotify._timers={}   -- core-owned expiry timer, keyed by timer id
ltnotify.maxNotifications=3

local function nextZ(wm)
  local maxZ=0
  local function visit(object)
    maxZ=math.max(maxZ,object.z_index or 0)
    for _,child in pairs(object.objects or {}) do visit(child) end
  end
  for _,mwin in ipairs(wm.windows) do visit(mwin.frame) end
  return maxZ+1
end

---Show a transient notification at top-right corner. Non-blocking.
---Stacks vertically up to maxNotifications. Silently drops if all slots full.
---@param title string
---@param text string
---@param timeout? number seconds before auto-dismiss (default 3)
---@param barCol? tgl.Color2 override title bar color
function ltnotify.notify(title,text,timeout,barCol)
  if not timeout then timeout=3 end
  if not text then text="" end
  if not barCol then barCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue) end
  --find a free slot
  local slot=nil
  for i=1,ltnotify.maxNotifications do
    if not ltnotify._notifySlots[i] then slot=i break end
  end
  if not slot then return end

  local bgCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
  local w=math.min(math.max(unicode.wlen(title),unicode.wlen(text))+4,40)
  local sw=tgl.defaults.screenSizeX
  local y=1+(slot-1)*3
  local size=tgl.Size2:newFromSize(sw-w+1,y,w,3)
  local function fit(value)
    if unicode.wlen(value)<=w-2 then return value end
    while unicode.wlen(value)>w-3 do value=unicode.sub(value,1,unicode.len(value)-1) end
    return value.."~"
  end
  local titleTxt=tgl.Text:new(fit(title),barCol,tgl.Pos2:new(2,1))
  local bodyTxt=tgl.Text:new(fit(text),bgCol,tgl.Pos2:new(2,2))
  local titleBar=tgl.Frame:new({t=titleTxt},tgl.Size2:newFromSize(1,1,w,1),barCol)
  titleBar.ignoreOpen=true
  local frame=tgl.Frame:new({titlebar=titleBar,body=bodyTxt},size,bgCol)
  local wm=tgl.sys.wm
  if wm then
    frame.z_index=nextZ(wm)
    frame._notifyWindow=wm:addOverlay(frame)
    frame._notifyWM=wm
    wm:renderRegions({size})
  else
    frame.z_index=500
    frame.ss=tgl.ScreenSave:new(size)
    frame:open(true)
    tgl.sys.renderer:flush(true)
  end
  ltnotify._notifySlots[slot]=frame
  frame._notifyExpires=computer.uptime()+math.max(0,tonumber(timeout) or 3)
end

---Show a warning notification. Yellow title bar, ⚠ prefix, beeps once.
---@param title string
---@param text string
---@param timeout? number seconds (default 4)
function ltnotify.warn(title,text,timeout)
  pcall(computer.beep,880,0.15)
  ltnotify.notify(
    "⚠ "..tostring(title or "Warning"),
    tostring(text or ""),
    timeout or 4,
    tgl.Color2:new(0,tgl.defaults.colors16.yellow)
  )
end

---Expire notifications independently of the app that created them.
function ltnotify.update()
  local now=computer.uptime()
  local expired={}
  for slot,frame in pairs(ltnotify._notifySlots) do
    if frame._notifyExpires and now>=frame._notifyExpires then
      expired[#expired+1]={slot=slot,frame=frame}
    end
  end
  if #expired==0 then return end
  tgl.sys.renderer:flush(true)
  local dirty={}
  for _,entry in ipairs(expired) do
    local frame=entry.frame
    if ltnotify._notifySlots[entry.slot]==frame then
      ltnotify._notifySlots[entry.slot]=nil
      frame:close()
      if frame._notifyWM then
        frame._notifyWM:removeOverlay(frame._notifyWindow)
        dirty[#dirty+1]=frame.size2
      end
    end
  end
  if tgl.sys.wm and #dirty>0 then tgl.sys.wm:renderRegions(dirty)
  else tgl.sys.renderer:flush(true) end
end

---Call from core, so app exit cannot stop notification expiry.
function ltnotify.start()
  if next(ltnotify._timers) then return end
  local id=event.timer(0.25,ltnotify.update,math.huge)
  ltnotify._timers[id]=true
end

---Cancel expiry and remove every notification on system shutdown.
function ltnotify.cleanup()
  for timerId in pairs(ltnotify._timers) do event.cancel(timerId) end
  ltnotify._timers={}
  tgl.sys.renderer:flush(true)
  local dirty={}
  for _,frame in pairs(ltnotify._notifySlots) do
    frame:close()
    if frame._notifyWM then
      frame._notifyWM:removeOverlay(frame._notifyWindow)
      dirty[#dirty+1]=frame.size2
    end
  end
  ltnotify._notifySlots={}
  if tgl.sys.wm and #dirty>0 then tgl.sys.wm:renderRegions(dirty)
  else tgl.sys.renderer:flush(true) end
end

---Split text into wrapped lines fitting maxW, respecting \n.
---@param text string
---@param maxW integer
---@return string[]
local function wrapText(text,maxW)
  local lines={}
  for raw in ((text or "").."\n"):gmatch("([^\n]*)\n") do
    if unicode.wlen(raw)<=maxW then
      lines[#lines+1]=raw
    else
      local pos=1
      local len=unicode.wlen(raw)
      while pos<=len do
        lines[#lines+1]=unicode.sub(raw,pos,math.min(pos+maxW-1,len))
        pos=pos+maxW
      end
    end
  end
  return lines
end

---Register dialogs above the current desktop, rather than at a fixed z-index.
local function openModal(frame)
  local wm=tgl.sys.wm
  local state={wm=wm,activeArea=tgl.sys.getActiveArea()}
  if wm then
    state.locked=wm.locked
    wm.locked=true
    frame.z_index=nextZ(wm)
    state.mwin=wm:addOverlay(frame)
    frame.hidden=false
    tgl.sys.setActiveArea(frame.size2)
    frame:enableAll()
    wm:renderRegions({frame.size2})
  else
    tgl.sys.renderer:flush(true)
    frame.ss=tgl.ScreenSave:new(frame.size2)
    tgl.sys.setActiveArea(frame.size2)
    frame:open(true)
    tgl.sys.renderer:flush(true)
  end
  return state
end

local function closeModal(frame,state)
  -- Finish queued input/cursor draws before repainting below their z-index.
  tgl.sys.renderer:flush(true)
  frame:close()
  tgl.sys.setActiveArea(state.activeArea)
  if state.wm then
    state.wm:removeOverlay(state.mwin)
    state.wm.locked=state.locked
    state.wm:renderRegions({frame.size2})
  else tgl.sys.renderer:flush(true) end
end

-- Custom system dialogs share the same stacking and cleanup rules.
ltnotify.openModal=openModal
ltnotify.closeModal=closeModal

---Blocking system dialog. Returns label of chosen button or nil on error.
---@param title string
---@param text string
---@param buttons string[] button labels e.g. {"OK","Cancel"}
---@param barCol? tgl.Color2 override title bar color
---@param icon? table optional {text,color} body icon
---@return string|nil
function ltnotify.dialog(title,text,buttons,barCol,icon,opts)
  if not buttons or #buttons==0 then buttons={"OK"} end
  if not barCol then barCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue) end
  ltnotify._dlgID=ltnotify._dlgID+1
  local evName="ltde_dlg_"..ltnotify._dlgID
  local bgCol=tgl.Color2:new(0,0xE1E1E1)
  local defaultBtnCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue)
  local sw,sh=tgl.defaults.screenSizeX,tgl.defaults.screenSizeY

  local totalBtnW=0
  for _,lbl in ipairs(buttons) do totalBtnW=totalBtnW+unicode.wlen(lbl)+4 end
  -- prefer wide enough to show text without wrapping, cap at screen
  local rawTextW=0
  for raw in ((text or "").."\n"):gmatch("([^\n]*)\n") do
    rawTextW=math.max(rawTextW,unicode.wlen(raw))
  end
  local iconW=icon and unicode.wlen(icon.text)+1 or 0
  local w=math.min(math.max(totalBtnW+4,unicode.wlen(title)+6,rawTextW+iconW+4,30),sw-4)
  local textMaxW=w-4-iconW

  local textLines=wrapText(text,textMaxW)
  local nLines=math.max(#textLines,1)
  -- layout: border / title / text*nLines / gap / buttons / border
  local checkbox=opts and opts.checkbox
  local checked=false
  local h=nLines+5+(checkbox and 1 or 0)
  local x=math.floor((sw-w)/2)
  local y=math.floor((sh-h)/2)
  local size=tgl.Size2:newFromSize(x,y,w,h)

  local objects={
    _title=tgl.Frame:new({tgl.Text:new(unicode.sub(title,1,w-4),barCol,tgl.Pos2:new(2,1))},
      tgl.Size2:new(2,2,w-2,1),barCol)
  }
  if icon then
    objects._icon=tgl.Text:new(icon.text,tgl.Color2:new(icon.color,bgCol[2]),tgl.Pos2:new(3,3))
  end
  for i,line in ipairs(textLines) do
    objects["_body"..i]=tgl.Text:new(line,bgCol,tgl.Pos2:new(3+iconW,i+2))
  end
  local bx=math.floor((w-totalBtnW)/2)+1
  for i,lbl in ipairs(buttons) do
    local col=i==1 and defaultBtnCol or barCol
    local btn=tgl.EventButton("["..lbl.."]",evName,lbl,tgl.Pos2:new(bx,h-1),col)
    btn.checkRendered=false btn.onClick=nil
    objects["btn"..i]=btn
    bx=bx+unicode.wlen(lbl)+4
  end

  if checkbox then
    local btn=tgl.EventButton("[ ] "..checkbox,evName,false,tgl.Pos2:new(3,h-2),bgCol)
    btn.checkRendered=false btn.onClick=nil
    objects._checkbox=btn
  end
  local frame=tgl.Frame:new(objects,size,bgCol)
  frame.borders="─│┌┐└┘"
  local modal=openModal(frame)
  local enterHandler=function(_,_,_char,code)
    if code==28 or code==156 then event.push(evName,buttons[1]) end
  end
  event.listen("key_down",enterHandler)
  local _ok,chosen=pcall(function()
    while true do
      local _,value=event.pull(evName)
      if value~=false or not checkbox then return value end
      checked=not checked
      objects._checkbox.text=(checked and "[x] " or "[ ] ")..checkbox
      if modal.wm then modal.wm:renderRegions({frame.size2})
      else
        local renderer=tgl.sys.renderer
        renderer:stop() frame:render() renderer:flush(true)
      end
    end
  end)
  event.ignore("key_down",enterHandler)
  closeModal(frame,modal)
  if not _ok then error(chosen,0) end
  return chosen,checked
end

---Show a blocking error dialog with title bar and ⛔ prefix. User must click OK.
---@param title string
---@param text string
function ltnotify.error(title,text)
  local c=require("computer")
  c.beep(1500,0.08) c.beep(1500,0.08)
  ltnotify.dialog(
    tostring(title or "Error"),
    tostring(text or ""),
    {"OK"},nil,{text="⛔",color=tgl.defaults.colors16.red}
  )
end

---Blocking prompt dialog with a text InputField. Returns entered string or nil on error.
---@param title string
---@param desc string description shown above the field
---@param secret? boolean mask input as asterisks
---@return string|nil
function ltnotify.prompt(title,desc,secret)
  ltnotify._dlgID=ltnotify._dlgID+1
  local evName="ltde_prompt_"..ltnotify._dlgID
  local bgCol=tgl.Color2:new(0,0xE1E1E1)
  local barCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
  local inputCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
  local sw,sh=tgl.defaults.screenSizeX,tgl.defaults.screenSizeY

  local rawDescW=0
  for raw in ((desc or "").."\n"):gmatch("([^\n]*)\n") do
    rawDescW=math.max(rawDescW,unicode.wlen(raw))
  end
  local w=math.min(math.max(rawDescW+4,36),sw-4)
  local textMaxW=w-4

  local descLines=wrapText(desc,textMaxW)
  local nDesc=math.max(#descLines,1)
  -- layout: border / title / desc*nDesc / gap / input / ok / border
  local h=nDesc+6
  local x=math.floor((sw-w)/2)
  local y=math.floor((sh-h)/2)
  local size=tgl.Size2:newFromSize(x,y,w,h)
  local fieldW=w-4

  local objects={
    _title=tgl.Frame:new({tgl.Text:new(unicode.sub(title or "Input",1,w-4),barCol,tgl.Pos2:new(2,1))},
      tgl.Size2:new(2,2,w-2,1),barCol)
  }
  for i,line in ipairs(descLines) do
    objects["_desc"..i]=tgl.Text:new(line,bgCol,tgl.Pos2:new(3,i+2))
  end

  local inputRow=nDesc+4
  local field=tgl.InputField:new(string.rep(" ",fieldW),tgl.Pos2:new(3,inputRow),inputCol)
  field.text=""
  field.secret=secret or false
  field.erase=false
  field.scrollX=true
  field.stopOnClickOutside=false
  field.stopEventName=evName
  field.checkRendered=false
  field.eventName=evName
  objects.field=field

  local okBtn=tgl.EventButton("[OK]",evName,nil,
    tgl.Pos2:new(math.floor((w-4)/2)+1,h-1),barCol)
  okBtn.checkRendered=false okBtn.onClick=nil
  objects.ok=okBtn

  local frame=tgl.Frame:new(objects,size,bgCol)
  frame.borders="─│┌┐└┘"
  local modal=openModal(frame)
  local _ok,_evn=pcall(function()
    field:disable()
    field:input()
    event.push(evName,field.text)
    field:enable()
    event.pull(evName)
  end)
  closeModal(frame,modal)
  if not _ok then error(_evn,0) end
  return field.text
end

---Show privilege elevation dialog. Returns true if user approves.
---@param perm string permission name
---@param reason string
---@return boolean
function ltnotify.elevate(perm,reason)
  local chosen=ltnotify.dialog(
    "Permission Request",
    "Perm: "..perm.."  Reason: "..reason,
    {"Allow","Deny"}
  )
  return chosen=="Allow"
end

return ltnotify
