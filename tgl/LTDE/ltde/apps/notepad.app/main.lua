---LTDE Notepad
local _openArg=(...)
local tgl=require("tgl")
local fs=require("filesystem")

local version="1.1"
local unicode=require("unicode")
local keyboard=require("keyboard")
local event=require("event")
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
    find="notepad_find_"..uid,
    findNext="notepad_findnext_"..uid,
    findPrevious="notepad_findprevious_"..uid,
  },
  dev="notepad_dev_"..uid,
  about="notepad_about_"..uid
}

local filename=""
local prevtext=""
local saved=true
local savedtext=""
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
    {label="Search",items={
      {label="Find...        Ctrl+F",eventName=events.toolbar.find},
      {label="Find Next      F3",eventName=events.toolbar.findNext},
      {label="Find Previous  Shift+F3",eventName=events.toolbar.findPrevious},
    }},
    {label="Help",items={
      {label="About",eventName=events.about},
    }},
  }
})
if not frame then return 1 end

local bgCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)

frame:add(tgl.InputBox:new("",tgl.Size2:newFromPoint(cs.x1,cs.y1+1,cs.x2,cs.y2-1),tgl.defaults.colors2.white),"input")
frame:add(tgl.Text:new("Unnamed",bgCol,tgl.Pos2:new(cs.x1+3,cs.y1)),"filename")
frame:add(tgl.Text:new("Size: 0 B",bgCol,tgl.Pos2:new(cs.x1,cs.y2)),"size")
frame:add(tgl.Text:new("          ",bgCol,tgl.Pos2:new(cs.x1+18,cs.y2)),"status")

frame.objects.input.eventName=events.input
frame.objects.input.stopEventName=events.close
frame.objects.input.wrap=true
frame.objects.input.lineNumbers=true
frame.objects.input.lineNumCol2=tgl.Color2:new(0,0xB4B4B4)
frame.objects.status.maxLength=cs.sizeX-18
frame.objects.filename.maxLength=40
frame.objects.size.maxLength=16

local function redraw()
  local wm=tgl.sys.wm
  local managed=wm and wm:getManagedWindow(frame)
  if managed and not frame.hidden then wm:renderRegions({wm:getWindowBounds(managed)}) end
end
redraw()
frame.objects.input:enable()

local function getSize()
  local size=#frame.objects.input.text
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
  frame.objects.filename.text=stext
  frame.objects.size.text="Size: "..getSize()
end

local function setStatus(str)
  frame.objects.status.text=str
end

local function clearStatus()
  frame.objects.status.text=""
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
  saved=true savedtext=frame.objects.input.text
  setStatus("Saved")
  updateLabels()
end

local function getFilename()
  local value=ltnotify.prompt("Notepad","Enter file name")
  if not value or value=="" then return false end
  filename=value
  return true
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
  saved=true savedtext=_text
  undoStack={}
  prevtext=_text
  frame.objects.input.text=_text
  frame.objects.input.highlight=nil
  frame.objects.input.viewY=0
  setStatus("Opened")
  updateLabels()
end

local function new()
  filename=""
  frame.objects.input.text=""
  frame.objects.input.highlight=nil
  frame.objects.input.viewY=0
  saved=true savedtext=""
  prevtext=""
  undoStack={}
  updateLabels()
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
  saved=snap.text==savedtext
  frame.objects.input.highlight=nil
  updateLabels()
  setStatus("Undo")
end

local function rename()
  --saves at a new location, deletes old
  local newname=ltnotify.prompt("Notepad","Enter new file name")
  if not newname or newname=="" then ltnotify.warn("Notepad","Empty name") return end
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
  frame.objects.input:showPosition(to+1,1)
end

local searchText=""
local matchCase=false
local lastStart,lastEnd=nil,nil
local searchedText=nil
local function findDialog()
  local go="notepad_find_go_"..uid
  local cancel="notepad_find_cancel_"..uid
  local toggle="notepad_find_case_"..uid
  local col=tgl.Color2:new(0,0xE1E1E1)
  local blue=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
  local width,height=44,8
  local field=tgl.InputField:new(string.rep(" ",width-6),tgl.Pos2:new(3,4),tgl.defaults.colors2.white)
  field.text=searchText field.erase=false field.scrollX=true
  field.restrictActiveArea=false
  field.stopOnClickOutside=true field.stopEventName=cancel field.eventName=go.."_input"
  local checked=matchCase
  local objects={
    title=tgl.Frame:new({tgl.Text:new("Find",blue,tgl.Pos2:new(2,1)),
      tgl.EventButton(" X ",cancel,nil,tgl.Pos2:new(width-5,1),tgl.defaults.colors2.close)},
      tgl.Size2:new(2,2,width-2,1),blue),
    label=tgl.Text:new("Find what:",col,tgl.Pos2:new(3,3)),field=field,
    case=tgl.EventButton((checked and "[x] " or "[ ] ").."Match case",toggle,nil,tgl.Pos2:new(3,5),col),
    message=tgl.Text:new("",col,tgl.Pos2:new(3,6)),
    find=tgl.EventButton("[Find Next]",go,nil,tgl.Pos2:new(3,7),col),
    cancel=tgl.EventButton("[Cancel]",cancel,nil,tgl.Pos2:new(20,7),col)
  }
  for _,object in pairs(objects) do if object.type=="Button" then object.onClick=nil end end
  objects.title.objects[2].onClick=nil
  local dialog=tgl.Frame:new(objects,tgl.Size2:new(math.floor((tgl.defaults.screenSizeX-width)/2),
    math.floor((tgl.defaults.screenSizeY-height)/2),width,height),col)
  dialog.borders="─│┌┐└┘"
  local modal=ltnotify.openModal(dialog)
  local function key(_,_,char,code)
    if code==28 or code==156 or char==13 then event.push(go)
    elseif code==1 or char==27 then event.push(cancel) end
  end
  local function shutdown()event.push(cancel)event.push(events.close)end
  event.listen("key_down",key) event.listen("ltde_shutdown",shutdown)
  local ok,value=pcall(function()
    field:disable() field:input() field:enable()
    while true do
      local ev=ltevent.pull()
      if ev==cancel then return nil
      elseif ev==toggle then
        checked=not checked objects.case.text=(checked and "[x] " or "[ ] ").."Match case"
        modal.wm:renderRegions({dialog.size2})
      elseif ev==go then
        if field.text~="" then return field.text end
        objects.message.text="Enter text to find." modal.wm:renderRegions({dialog.size2})
      end
    end
  end)
  event.ignore("key_down",key)event.ignore("ltde_shutdown",shutdown)
  ltnotify.closeModal(dialog,modal)
  if not ok then error(value,0) end
  return value,checked
end
local function find(prompt,backwards)
  if prompt or searchText=="" then
    local value,checked=findDialog()
    if not value then return end
    searchText,matchCase=value,checked lastStart,lastEnd=nil,nil
  end
  local text=frame.objects.input.text
  if text~=searchedText then lastStart,lastEnd=nil,nil searchedText=text end
  local haystack=matchCase and text or unicode.lower(text)
  local needle=matchCase and searchText or unicode.lower(searchText)
  local first,last,wrapped
  if backwards then
    local limit=lastStart or (#haystack+1)
    local at=1
    while true do
      local a,b=haystack:find(needle,at,true)
      if not a or a>=limit then break end
      first,last=a,b at=b+1
    end
    if not first and lastStart then
      wrapped=true at=1
      while true do
        local a,b=haystack:find(needle,at,true)
        if not a then break end
        first,last=a,b at=b+1
      end
    end
  else
    first,last=haystack:find(needle,(lastEnd or 0)+1,true)
    if not first and lastEnd then wrapped=true first,last=haystack:find(needle,1,true) end
  end
  frame.objects.input.highlight=nil
  if not first then setStatus("Not found: "..searchText) return end
  lastStart,lastEnd=first,last
  local chars=unicode.len(haystack:sub(1,first-1))
  local prefix=unicode.sub(text,1,chars)
  local _,newlines=prefix:gsub("\n","")
  local line,column=newlines+1,unicode.len(prefix:match("([^\n]*)$"))+1
  frame.objects.input:showPosition(line,column,unicode.len(searchText))
  setStatus((wrapped and "Wrapped: " or "Found: ").."Ln "..line..", Col "..column)
end
local function shortcut(char,code)
  local action
  if code==61 then action=keyboard.isShiftDown() and events.toolbar.findPrevious or events.toolbar.findNext
  else
    local keys={[6]=events.toolbar.find,[14]=events.toolbar.new,[15]=events.toolbar.open,
      [19]=events.toolbar.save,[23]=events.toolbar.saveAs,[17]=events.toolbar.close,
      [7]=events.toolbar.tgoto,[26]=events.toolbar.undo}
    action=keys[char]
    if keyboard.isControlDown() then
      action=({[33]=events.toolbar.find,[49]=events.toolbar.new,[24]=events.toolbar.open,
        [31]=events.toolbar.save,[17]=events.toolbar.saveAs,[16]=events.toolbar.close,
        [34]=events.toolbar.tgoto,[44]=events.toolbar.undo})[code] or action
    end
  end
  if action then ltevent.push(action) return true end
end
frame.objects.input.onKeyDown=shortcut

if type(_openArg)=="string" and _openArg~="" then
  filename=_openArg
  open() redraw()
end

local function commitInput()
  if frame.objects.input.text==prevtext then return false end
  pushUndo()
  prevtext=frame.objects.input.text
  saved=prevtext==savedtext
  frame.objects.input.highlight=nil
  updateLabels() clearStatus()
  return true
end

while true do
  local ev,_,k1,k2=ltevent.pull()
  local changed=commitInput()
  local repaint=true
  if ev==events.close or ev=="ltde_shutdown" then break
  elseif ev==events.input then repaint=changed
  elseif ev=="key_down" then
    shortcut(k1,k2) repaint=false
  elseif ev==events.toolbar.new then clearStatus() new()
  elseif ev==events.toolbar.open then if getFilename() then open() end
  elseif ev==events.toolbar.save then
    if filename~="" or getFilename() then savefile() end
  elseif ev==events.toolbar.saveAs then if getFilename() then savefile() end
  elseif ev==events.toolbar.close then clearStatus() new()
  elseif ev==events.toolbar.rename then rename()
  elseif ev==events.toolbar.tgoto then tgoto()
  elseif ev==events.toolbar.find then find(true)
  elseif ev==events.toolbar.findNext then find(false)
  elseif ev==events.toolbar.findPrevious then find(false,true)
  elseif ev==events.about then ltnotify.dialog("Notepad ver "..version,"Notepad - a simple text editor.")
  elseif ev==events.toolbar.undo then undo()
  elseif ev==events.toolbar.lineNums then
    frame.objects.input.lineNumbers=not frame.objects.input.lineNumbers updateViewMenu()
  elseif ev==events.toolbar.refresh then -- redraw below
  elseif ev==events.dev then ltnotify.warn("Notepad","Not implemented",2)
  else repaint=false end
  if repaint or changed then redraw() end
end
frame:disableAll()
ltwapi.removeWindow(frame)
return 0
