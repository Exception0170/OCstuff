---LTDE Notepad
local _openArg=(...)
local tgl=require("tgl")
local fs=require("filesystem")
local r=tgl.sys.renderer

local version="1.0"
local uid=string.sub(math.random(1,1000000),1,-3)
local events={
  close="notepad_done_"..uid,
  input="notepad_input_"..uid,
  toolbar={
    new="notepad_new_"..uid,
    open="notepad_open_"..uid,
    save="notepad_save_"..uid,
    saveAs="notepad_saveas_"..uid,
    close="notepad_close_"..uid,
    undo="notepad_undo_"..uid,
    settings="notepad_settings_"..uid,
    rename="notepad_rename_"..uid,
    tgoto="notepad_goto_"..uid,
    lineNums="notepad_linenums_"..uid,
    refresh="notepad_refresh_"..uid,
  },
  dev="notepad_dev_"..uid,
  about="notepad_about_"..uid
}

local filename=""
local prevtext=""
local saved=false
local undoStack={}

local frame,cs=ltwapi.addWindow(76,20,"Notepad",{
  onClose=function() ltevent.push(events.close) end,
  toolbar=true,
  menuItems={
    {label="File",items={
      {label="New      Ctrl+N",eventName=events.toolbar.new},
      {label="Open     Ctrl+O",eventName=events.toolbar.open},
      {label="Save     Ctrl+S",eventName=events.toolbar.save},
      {label="Save As  Ctrl+W",eventName=events.toolbar.saveAs},
      {label="Close    Ctrl+Q",eventName=events.toolbar.close},
      {label="Exit",eventName=events.close}
    }},
    {label="Edit",items={
      {label="Undo   Ctrl+Z",eventName=events.toolbar.undo},
      {label="Rename",eventName=events.toolbar.rename}
    }},
    {label="View",items={
      {label="Goto         Ctrl+G",eventName=events.toolbar.tgoto},
      {label="Hide line numbers",eventName=events.toolbar.lineNums},
      {label="Refresh",eventName=events.toolbar.refresh},
    }},
    {label="Help",items={
      {label="About",eventName=events.about},
    }},
  }
})
if not frame then return 1 end

local bgCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)

frame:add(tgl.InputBox:new("",tgl.Size2:newFromPoint(cs.x1,cs.y1+1,cs.x2,cs.y2-1),tgl.defaults.colors2.white),"input")
frame:add(tgl.Text:new("* Unnamed",bgCol,tgl.Pos2:new(cs.x1+3,cs.y1)),"filename")
frame:add(tgl.Text:new("Size: 0 B",bgCol,tgl.Pos2:new(cs.x1,cs.y2)),"size")
frame:add(tgl.Text:new("          ",bgCol,tgl.Pos2:new(cs.x2-10,cs.y2)),"status")

frame.objects.input.eventName=events.input
frame.objects.input.stopEventName=events.close
frame.objects.input.wrap=true
frame.objects.input.lineNumbers=true
frame.objects.input.lineNumCol2=tgl.Color2:new(0,0xB4B4B4)
frame.objects.status.maxLength=10
frame.objects.filename.maxLength=40
frame.objects.size.maxLength=20

frame:render()
frame.objects.input:enable()

local function getSize()
  local size=require("component").filesystem.size(filename)
  if size==0 then
    size=string.len(frame.objects.input.text)
  end
  if size>1100 then
    size=string.format("%.2f KB",size/1024)
  else
    size=size.." B"
  end
  return size
end

local function updateLabels()
  local stext=fs.name(filename)
  if not stext or stext=="" then stext="Unnamed" end
  if saved==false then stext="* "..stext end
  frame.objects.filename:updateText(stext)
  frame.objects.size:updateText("Size: "..getSize())
end

local function setStatus(str)
  frame.objects.status:updateText(str)
end

local function clearStatus()
  frame.objects.status:updateText("          ")
end

local function updateViewMenu()
  local lnLabel=(frame.objects.input.lineNumbers and "Hide" or "Show").." line numbers"
  ltwapi.setMenuItems(frame,"View",{
    {label="Goto         ctrl+G",eventName=events.toolbar.tgoto},
    {label=lnLabel,             eventName=events.toolbar.lineNums},
    {label="Refresh",           eventName=events.toolbar.refresh},
  })
end

local function savefile()
  if filename=="" then return end
  local file,err=io.open(filename,"w")
  if not file then
    ltnotify.error("Notepad","Could not save: "..(err or "unknown error"))
    return
  end
  file:write(frame.objects.input.text)
  file:close()
  saved=true
  setStatus("Saved")
  updateLabels()
end

local function getFilename()
  filename=ltnotify.prompt("Notepad","Enter file name")
  if filename=="" then
    ltnotify.warn("Notepad","Empty name")
  end
end

local function pushUndo()
  table.insert(undoStack,{text=prevtext,viewY=frame.objects.input.viewY})
  if #undoStack>50 then table.remove(undoStack,1) end
end

local function open()
  if filename=="" then return end
  local file,err=io.open(filename,"r")
  if not file then
    ltnotify.error("Notepad","Could not open: "..(err or "unknown error"))
    return
  end
  local _text=file:read("*a")
  file:close()
  saved=true
  undoStack={}
  prevtext=_text
  frame.objects.input.text=_text
  frame.objects.input.viewY=0
  setStatus("Opened")
  updateLabels()
  r:stop() frame.objects.input:render() r:flush()
end

local function new()
  filename=""
  frame.objects.input.text=""
  frame.objects.input.viewY=0
  saved=false
  prevtext=""
  undoStack={}
  updateLabels()
  r:stop() frame.objects.input:render() r:flush()
end

local function undo()
  if #undoStack==0 then
    ltnotify.warn("Notepad","Nothing to undo",2)
    return
  end
  local snap=table.remove(undoStack)
  prevtext=snap.text
  frame.objects.input.text=snap.text
  frame.objects.input.viewY=snap.viewY
  saved=false
  updateLabels()
  setStatus("Undo")
  r:stop() frame.objects.input:render() r:flush()
end

local function rename()
  --saves at a new location, deletes old
  local newname=ltnotify.prompt("Notepad","Enter new file name")
  if newname=="" then ltnotify.warn("Notepad","Empty name") return end
  if filename~="" then
    fs.rename(filename,newname)
  end
  filename=newname
  setStatus("renamed")
  savefile()
end

local function tgoto()
  local to=ltnotify.prompt("Notepad","Enter line number")
  to=tonumber(to)
  if not to then ltnotify.warn("Notepad","Line number should be a number") return end
  to=math.floor(to-1)
  frame.objects.input.viewY=to
  r:stop() frame.objects.input:render() r:flush()
end

if type(_openArg)=="string" and _openArg~="" then
  filename=_openArg
  open()
end

while true do
  local ev,_,k1,k2=ltevent.pull()
  if ev==events.close then break
  elseif ev==events.input then
    pushUndo()
    prevtext=frame.objects.input.text
    saved=false
    updateLabels()
    clearStatus()
  elseif ev=="key_down" then
    if k1==14 and k2==49 then ltevent.push(events.toolbar.new)
    elseif k1==15 and k2==24 then ltevent.push(events.toolbar.open)
    elseif k1==19 and k2==31 then ltevent.push(events.toolbar.save)
    elseif k1==23 and k2==17 then ltevent.push(events.toolbar.saveAS)
    elseif k1==17 and k2==16 then ltevent.push(events.toolbar.close)
    elseif k1==7  and k2==34 then ltevent.push(events.toolbar.tgoto)
    elseif k1==26 and k2==44 then ltevent.push(events.toolbar.undo)
    end
  elseif ev==events.toolbar.new then
    clearStatus()
    new()
  elseif ev==events.toolbar.open then
    getFilename()
    open()
  elseif ev==events.toolbar.save then
    if filename=="" then getFilename() end
    savefile()
  elseif ev==events.toolbar.saveAs then
    getFilename()
    savefile()
  elseif ev==events.toolbar.close then
    clearStatus()
    new()
  elseif ev==events.toolbar.rename then
    rename()
  elseif ev==events.toolbar.tgoto then
    tgoto()
  elseif ev==events.about then
    ltnotify.dialog("Notepad ver "..version,"Notepad - a simple text editor.")
  elseif ev==events.toolbar.undo then
    undo()
  elseif ev==events.toolbar.lineNums then
    frame.objects.input.lineNumbers=not frame.objects.input.lineNumbers
    updateViewMenu()
    r:stop() frame.objects.input:render() r:flush()
  elseif ev==events.toolbar.refresh then
    r:stop() frame.objects.input:render() r:flush()
  elseif ev==events.dev then
    ltnotify.warn("Notepad","Not implemented",2)
  end
end
os.sleep(.3)
return 0