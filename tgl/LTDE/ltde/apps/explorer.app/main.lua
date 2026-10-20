--LTDE file explorer
local event=require("event")
local tgl=require("tgl")
local fs=require("filesystem")
local computer=require("computer")
local unicode=require("unicode")
local keyboard=require("keyboard")
local r=tgl.sys.renderer

local version="0.2"
local uid=tostring(math.random(1,1000000))
local events={
  close="explorer_done_"..uid,
  toolbar={
    newfolder="explorer_new_folder_"..uid,
    newfile="explorer_new_file_"..uid,
    find="explorer_find_"..uid,
    findinfiles="explorer_find_in_files_"..uid,
    open="explorer_open_"..uid,

    copy="explorer_copy_"..uid,
    paste="explorer_paste_"..uid,
    cut="explorer_cut_"..uid,
    duplicate="explorer_duplicate_"..uid,
    rename="explorer_rename_"..uid,
    move="explorer_move_"..uid,
    delete="explorer_delete_"..uid,
    undo="explorer_undo_"..uid,
    selectAll="explorer_select_all_"..uid,
    deselect="explorer_deselct_"..uid,

    refresh="explorer_refresh_"..uid,
    properties="explorer_properties_"..uid,
    statusbar="explorer_statusbar_"..uid,
    sidebar="explorer_sidebar_"..uid,
    hidden="explorer_hidden_"..uid,
    list="explorer_list_"..uid,
    bookmark="explorer_bookmark_"..uid,

    help="explorer_help_"..uid,
    about="explorer_about_"..uid
  },
  back="explorer_back_"..uid,
  forward="explorer_forward_"..uid,
  up="explorer_up_"..uid,
  home="explorer_home_"..uid,
  input="explorer_input_"..uid,
  go="explorer_go_"..uid,
  select="explorer_select_"..uid,
  sort="explorer_sort_"..uid,
}

---Colors
local gray=tgl.Color2:new(0,0xA5A5A5)
local mediumgray=tgl.Color2:new(0,0xC3C3C3)
local lightergray=tgl.Color2:new(0,0xF0F0F0)
local white=tgl.Color2:new(0,0xFFFFFF)
local blue_button=tgl.Color2:new(0x0000FF,0xA5A5A5)
local blue_text=tgl.Color2:new(tgl.defaults.colors16.darkblue,0xFFFFFF)
local sel_col=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)

---State
local home_folder="/home"
local current_folder="/home"
local historyBack={}
local historyFwd={}
local selected={}
-- _ltde_fileClipboard is shared between Explorer windows.
local showHidden=false
local showSidebar=true
local showStatusbar=true
local listView=false
local searchText=nil
local searchContents=false
local searchMatches={}
local undoRename=nil
local cfglib=assert(loadfile("/ltde/sys/cfglib.lua"))()
local bookmarks=cfglib.load("/ltde/cfg/bookmarks.conf") or cfglib.new()
local lastClickName=nil
local lastClickTime=0
local DBLCLICK=0.5
local currentItemCount=0
local app_x,app_y=60,20
local FOOT_W=app_x-12        -- footbar width: cols 13..app_x = 48 chars
local FOOT_STATUS_W=12
local FOOT_STATUS_X=FOOT_W-FOOT_STATUS_W+1   -- = 37
local sortBy="name"
local sortDir="asc"
local COL_NAME_W=28
local COL_SIZE_W=9
local COL_DATE_W=10
local DEVICE_SIZE_W=15
local DEVICE_ACCESS_W=4
local DEVICE_Y=12
local DEVICES_MAX_Y=app_y-4

local frame,cs=ltwapi.addWindow(60,20,"File Explorer",{
  onClose=function() ltevent.push(events.close) end,
  toolbar=true,
  menuItems={
    {label="File",items={
      {label="New Folder",eventName=events.toolbar.newfolder},
      {label="New File      Ctrl+N",eventName=events.toolbar.newfile},
      {label="Find          Ctrl+F",eventName=events.toolbar.find},
      {label="Find in files",eventName=events.toolbar.findinfiles},
      {label="Open Folder   Ctrl+O",eventName=events.toolbar.open},
      {label="Close",eventName=events.close},
    }},
    {label="Edit",items={
      {label="Copy       Ctrl+C",eventName=events.toolbar.copy},
      {label="Paste      Ctrl+V",eventName=events.toolbar.paste},
      {label="Cut        Ctrl+X",eventName=events.toolbar.cut},
      {label="Duplicate  Ctrl+D",eventName=events.toolbar.duplicate},
      {label="Rename     Ctrl+R",eventName=events.toolbar.rename},
      {label="Move       Ctrl+M",eventName=events.toolbar.move},
      {label="Delete        Del",eventName=events.toolbar.delete},
      {label="Undo rename Ctrl+Z",eventName=events.toolbar.undo},
      {label="Select All Ctrl+A",eventName=events.toolbar.selectAll},
      {label="Deselect      Esc",eventName=events.toolbar.deselect},
    }},
    {label="View",items={
      {label="Refresh",eventName=events.toolbar.refresh},
      {label="Toggle statusbar",eventName=events.toolbar.statusbar},
      {label="Toggle sidebar",eventName=events.toolbar.sidebar},
      {label="Show hidden files",eventName=events.toolbar.hidden},
      {label="List / Details",eventName=events.toolbar.list},
      {label="Properties",eventName=events.toolbar.properties},
    }},
    {label="Bookmarks",items={
      --fill dynamically from config
    }},
    {label="Help",items={
      {label="Help",eventName=events.toolbar.help},
      {label="About",eventName=events.toolbar.about},
    }},
  }
})
if not frame then return 1 end

---Build frame

local addrbar=tgl.Frame:new({
  back=tgl.EventButton("⬅",events.back,nil,tgl.Pos2:new(1,1),blue_button),
  forward=tgl.EventButton("➡",events.forward,nil,tgl.Pos2:new(4,1),blue_button),
  up=tgl.EventButton(" ⬆ ",events.up,nil,tgl.Pos2:new(7,1),blue_button),
  home=tgl.EventButton("🏠",events.home,nil,tgl.Pos2:new(10,1),blue_button),
  input=tgl.InputField:new(current_folder,tgl.Pos2:new(14,1),mediumgray)
},tgl.Size2:new(1,3,app_x,1),gray)
addrbar.objects.input.erase=false
addrbar.objects.input.defaultText=string.rep(" ",app_x-14)
addrbar.objects.input.eventName=events.input
addrbar.objects.input.stopOnClickOutside=true
addrbar.objects.input.scrollX=true
frame:add(addrbar,"addrbar")

local sidebar=tgl.Frame:new({
  tgl.Text:new("Places",lightergray,tgl.Pos2:new(1,1)),
  tgl.EventButton("Root",events.go,"/",tgl.Pos2:new(3,2),lightergray),
  tgl.EventButton("Home",events.go,home_folder,tgl.Pos2:new(3,3),lightergray),
  tgl.EventButton("Desktop",events.go,"/home/Desktop",tgl.Pos2:new(3,4),lightergray),
  tgl.EventButton("Documents",events.go,"/home/Documents",tgl.Pos2:new(3,5),lightergray),
  tgl.EventButton("Bookmarks",events.go,"bookmarks",tgl.Pos2:new(3,6),lightergray),
  tgl.EventButton("Apps",events.go,"/ltde/apps",tgl.Pos2:new(3,7),lightergray),
  tgl.EventButton("Configs",events.go,"/ltde/cfg",tgl.Pos2:new(3,8),lightergray),
  tgl.EventButton("LTDE",events.go,"/ltde",tgl.Pos2:new(3,9),lightergray),
  tgl.EventButton("Devices",events.go,"devices",tgl.Pos2:new(1,11),lightergray),
},tgl.Size2:newFromPoint(1,4,12,app_y),lightergray)
frame:add(sidebar,"sidebar")

-- colheader: cols 13-60, row 4 (1 row); folderbar: rows 5-19 (15 rows)
local hdrNameBtn=tgl.EventButton("",events.sort,"name",tgl.Pos2:new(1,1),mediumgray)
local hdrSizeBtn=tgl.EventButton("",events.sort,"size",tgl.Pos2:new(COL_NAME_W+1,1),mediumgray)
local hdrDateBtn=tgl.EventButton("",events.sort,"date",tgl.Pos2:new(COL_NAME_W+COL_SIZE_W+1,1),mediumgray)
frame:add(tgl.Frame:new({hdrNameBtn,hdrSizeBtn,hdrDateBtn},tgl.Size2:newFromPoint(13,4,app_x,4),mediumgray),"colheader")
frame:add(tgl.ScrollFrame:new({},tgl.Size2:newFromPoint(13,5,app_x,app_y-1),white),"folderbar")
local foot_info=tgl.Text:new(" 0 items",gray,tgl.Pos2:new(1,1))
foot_info.maxLength=FOOT_STATUS_X-2
local foot_status=tgl.Text:new("",gray,tgl.Pos2:new(FOOT_STATUS_X,1))
foot_status.maxLength=FOOT_STATUS_W
frame:add(tgl.Frame:new({_txt=foot_info,_status=foot_status},
  tgl.Size2:newFromPoint(13,app_y,app_x,app_y),gray),"footbar")

---Helpers

local function selCount()
  local n=0
  for _ in pairs(selected) do n=n+1 end
  return n
end

local function parentOf(p)
  local p2=p:gsub("/$","")
  if p2=="" then return "/" end
  local parent=p2:match("^(.+)/[^/]+$")
  if not parent or parent=="" then return "/" end
  return parent
end

local function sizeStr(bytes)
  if not bytes or bytes<0 then return "?" end
  if bytes<1024 then return bytes.." B"
  elseif bytes<1048576 then return string.format("%.1f KB",bytes/1024)
  else return string.format("%.1f MB",bytes/1048576) end
end

local function setFootStatus(msg)
  frame.objects.footbar.objects._status.text=msg or ""
end

local function updateFooter(count,name,fullpath)
  local msg
  if type(count)=="string" then
    msg=" "..count
  elseif name and fullpath then
    if fs.isDirectory(fullpath) then
      msg=" "..name.." (folder)"
    else
      local ok,sz=pcall(fs.size,fullpath)
      msg=" "..name.."  "..(ok and sizeStr(sz) or "?")
    end
  else
    msg=" "..(count or 0).." items"
  end
  frame.objects.footbar.objects._txt.text=msg
end

local function truncPad(s,w)
  local sw=unicode.wlen(s)
  if sw==w then return s end
  if sw<w then return s..string.rep(" ",w-sw) end
  return unicode.sub(s,1,w-1).."~"
end

---Mounted filesystems, one entry per device even when mounted more than once.
local devices={}
local deviceStamp=nil
local currentDevice=nil
local lastDeviceCheck=0

local function deviceValue(proxy,key)
  -- Component methods can be callable tables, not only Lua functions.
  local ok,value=pcall(function() return proxy[key]() end)
  if ok then return value end
end

local function updateDevices()
  local found={}
  for proxy,path in fs.mounts() do
    path=fs.canonical(path)
    if path~="/tmp" and path~="/dev" then
      local id=proxy.address or tostring(proxy)
      local old=found[id]
      if not old or #path<#old.path or (#path==#old.path and path<old.path) then
        found[id]={proxy=proxy,path=path,id=id}
      end
    end
  end
  local list={}
  for _,dev in pairs(found) do
    local label=deviceValue(dev.proxy,"getLabel")
    if type(label)~="string" or label=="" then label=dev.path=="/" and "System" or dev.id:sub(1,8) end
    dev.label=label
    dev.readOnly=deviceValue(dev.proxy,"isReadOnly")==true
    table.insert(list,dev)
  end
  table.sort(list,function(a,b)
    if a.path=="/" or b.path=="/" then return a.path=="/" and b.path~="/" end
    if a.label~=b.label then return a.label<b.label end
    return a.path<b.path
  end)
  local stamp={}
  for _,dev in ipairs(list) do
    table.insert(stamp,dev.id.."\0"..dev.path.."\0"..dev.label.."\0"..tostring(dev.readOnly))
  end
  stamp=table.concat(stamp,"\n")
  devices=list
  if stamp==deviceStamp then return false end
  deviceStamp=stamp
  local names={}
  for name in pairs(sidebar.objects) do
    if type(name)=="string" and name:sub(1,7)=="device_" then table.insert(names,name) end
  end
  for _,name in ipairs(names) do sidebar:remove(name) end
  for i,dev in ipairs(devices) do
    local y=DEVICE_Y+i-1
    if y>DEVICES_MAX_Y then break end
    local btn=tgl.EventButton(truncPad(" "..dev.label,12),events.go,dev.path,tgl.Pos2:new(1,y),lightergray)
    sidebar:add(btn,"device_"..i)
    if not frame.hidden and not sidebar.hidden then btn:enable() end
  end
  return true
end

local function displayDevices()
  local sf=frame.objects.folderbar
  sf:disableAll()
  sf.objects={}
  sf.scroll=0
  for i,dev in ipairs(devices) do
    local total=deviceValue(dev.proxy,"spaceTotal")
    local used=deviceValue(dev.proxy,"spaceUsed")
    local capacity="?"
    if type(total)=="number" and total>=0 and total<math.huge then
      local size
      if total>=1048576 then size=string.format("%.2fMb",total/1048576)
      elseif total>=1024 then size=string.format("%.2fKb",total/1024)
      else size=string.format("%dB",total) end
      local percent="?%"
      if type(used)=="number" and used>=0 and used<math.huge then
        percent=string.format("%d%%",total>0 and math.floor(math.max(0,math.min(100,used/total*100))) or 0)
      end
      capacity=percent.." "..size
    elseif total==math.huge then capacity="Unlimited" end
    local line=truncPad(" "..dev.label.." ("..dev.path..")",COL_NAME_W)
      ..truncPad(capacity,DEVICE_SIZE_W)..truncPad(dev.readOnly and " r" or " rw",DEVICE_ACCESS_W)
    local btn=tgl.EventButton(line,events.go,dev.path,tgl.Pos2:new(1,i),blue_text)
    sf.objects[i]=btn
  end
  currentItemCount=#devices
  sf.maxScroll=math.max(0,#devices-sf.size2.sizeY)
  sf:translate()
  if not frame.hidden then sf:enableAll() end
  updateFooter(#devices.." devices")
  setFootStatus("")
end

local function fmtSize(isDir,sz)
  if isDir then return string.rep(" ",COL_SIZE_W-6).."<dir> " end
  local s=sizeStr(sz or 0)
  local sw=unicode.wlen(s)
  return string.rep(" ",math.max(0,COL_SIZE_W-sw-1))..s.." "
end

local function fmtDate(ts)
  if type(ts)~="number" or ts<=0 or ts~=ts or ts==math.huge then
    return string.rep(" ",COL_DATE_W-1).."?"
  end
  -- Filesystem timestamps use milliseconds; os.date expects seconds.
  if ts>100000000000 then ts=math.floor(ts/1000) end
  local ok,date=pcall(os.date,"%d/%m/%Y",ts)
  if not ok or type(date)~="string" or #date~=COL_DATE_W then
    return string.rep(" ",COL_DATE_W-1).."?"
  end
  return date
end

local function hdrLabel(text,width,isActive,isAsc)
  local tw=unicode.wlen(text)
  local pad=width-tw-1
  local arrow=isActive and (isAsc and "↑" or "↓") or " "
  return text..string.rep(" ",math.max(0,pad))..arrow
end

local function updateSortHeaders()
  hdrSizeBtn.relpos2=tgl.Pos2:new(COL_NAME_W+1,1)
  local deviceView=current_folder=="devices"
  hdrDateBtn.relpos2=tgl.Pos2:new(COL_NAME_W+(deviceView and DEVICE_SIZE_W or COL_SIZE_W)+1,1)
  frame.objects.colheader:translate()
  if current_folder=="devices" then
    hdrNameBtn.text=truncPad(" Device / Mount",COL_NAME_W)
    hdrSizeBtn.text=truncPad("Used / Cap.    ",DEVICE_SIZE_W)
    hdrDateBtn.text=truncPad("Mode",DEVICE_ACCESS_W)
    return
  end
  if listView then
    hdrNameBtn.text=truncPad(" Name",frame.objects.folderbar.size2.sizeX-1)
    hdrSizeBtn.text=""
    hdrDateBtn.text=""
    return
  end
  local asc=sortDir=="asc"
  hdrNameBtn.text=hdrLabel(" Name",COL_NAME_W,sortBy=="name",asc)
  hdrNameBtn.col2=sortBy=="name" and gray or mediumgray
  hdrSizeBtn.text=hdrLabel(" Size",COL_SIZE_W,sortBy=="size",asc)
  hdrSizeBtn.col2=sortBy=="size" and gray or mediumgray
  hdrDateBtn.text=hdrLabel(" Date",COL_DATE_W,sortBy=="date",asc)
  hdrDateBtn.col2=sortBy=="date" and gray or mediumgray
end

local function matchesSearch(full,name,isDir)
  if not searchText then return true end
  if not searchContents then return name:lower():find(searchText,1,true)~=nil end
  if isDir then return false end
  if searchMatches[full]~=nil then return searchMatches[full] end
  local file=io.open(full,"r")
  if not file then return false end
  local found=false
  local ok=pcall(function()
    local tail=""
    while true do
      local block=file:read(4096)
      if not block then break end
      local text=tail..block:lower()
      if text:find(searchText,1,true) then found=true break end
      tail=#searchText>1 and text:sub(-(#searchText-1)) or ""
      os.sleep(0)
    end
  end)
  file:close()
  searchMatches[full]=ok and found
  return searchMatches[full]
end

local function displayFolder(keepScroll)
  updateSortHeaders()
  if current_folder=="devices" then displayDevices() return end
  local sf=frame.objects.folderbar
  sf:disableAll()
  sf.objects={}
  local oldScroll=keepScroll and sf.scroll or 0
  sf.scroll=0
  sf.maxScroll=0

  local iter,err=fs.list(current_folder)
  if not iter then
    sf.objects[1]=tgl.Text:new("Error: "..tostring(err),
      tgl.Color2:new(tgl.defaults.colors16.red,0xFFFFFF),tgl.Pos2:new(1,1))
    sf:translate()
    currentItemCount=0
    updateFooter(0)
    return
  end

  local allItems={}
  for name in iter do
    if showHidden or name:sub(1,1)~="." then
      local full=fs.concat(current_folder,name)
      local isDir=fs.isDirectory(full)
      local ok_sz,sz=pcall(fs.size,full)
      local ok_dt,dt=pcall(fs.lastModified,full)
      if matchesSearch(full,name,isDir) then allItems[#allItems+1]={
        name=name,
        isDir=isDir,
        size=ok_sz and sz or 0,
        date=ok_dt and dt or 0,
      } end
    end
  end

  table.sort(allItems,function(a,b)
    if a.isDir~=b.isDir then return a.isDir end
    if sortBy=="size" and a.size~=b.size then
      if sortDir=="asc" then return a.size<b.size else return a.size>b.size end
    elseif sortBy=="date" and a.date~=b.date then
      if sortDir=="asc" then return a.date<b.date else return a.date>b.date end
    end
    local an,bn=a.name:lower(),b.name:lower()
    if an==bn then return false end
    if sortDir=="asc" then return an<bn else return an>bn end
  end)

  currentItemCount=#allItems

  for i,item in ipairs(allItems) do
    local c
    if selected[item.name] then
      c=sel_col
    else
      local foreground=ltfiletypes.color(item.name,item.isDir)
      c=foreground and tgl.Color2:new(foreground,0xFFFFFF) or white
    end
    local nameCol=truncPad(" "..item.name,COL_NAME_W)
    local sizeCol=fmtSize(item.isDir,item.size)
    local dateCol=fmtDate(item.date)
    local line=listView and truncPad(" "..item.name,sf.size2.sizeX-1) or nameCol..sizeCol..dateCol
    local btn=tgl.EventButton(line,events.select,item.name,tgl.Pos2:new(1,i),c)
    btn.onClick=nil  -- selection is the feedback; delayed animation can outlive opening a file
    sf.objects[i]=btn
  end

  -- folderbar is Size2:newFromPoint(13,5,60,19) -> sizeY=15 visible rows
  sf.maxScroll=math.max(0,currentItemCount-sf.size2.sizeY)
  sf.scroll=math.min(oldScroll,sf.maxScroll)
  sf:translate()
  sf:enableAll()

  local selN=selCount()
  if selN>1 then
    updateFooter(selN.." selected")
  elseif selN==1 then
    local selName=next(selected)
    updateFooter(nil,selName,fs.concat(current_folder,selName))
  else
    updateFooter(currentItemCount)
  end
end

local function rerender()
  local wm=tgl.sys.wm
  local mwin=wm and wm:getManagedWindow(frame)
  if frame.hidden then return end
  if mwin then wm:renderRegions({wm:getWindowBounds(mwin)})
  else r:stop() frame:render() r:flush(true) end
end

local function rerenderFolder()
  rerender()
end

local function rerenderNav()
  rerender()
end

local function setFolder(path)
  searchText=nil
  searchMatches={}
  current_folder=path
  local proxy=path~="devices" and fs.get(path) or nil
  currentDevice=proxy and proxy.address or nil
  selected={}
  lastClickName=nil
  addrbar.objects.input.text=current_folder
  addrbar.objects.input._viewX=0
  displayFolder()
  setFootStatus("")
  rerenderNav()
end

local function navigate(path)
  if not path or path=="" then return end
  if path~="devices" then
    path=fs.canonical(path:sub(1,1)=="/" and path or fs.concat(current_folder=="devices" and home_folder or current_folder,path))
  end
  if path~="devices" and not fs.isDirectory(path) then
    ltnotify.warn("Not a folder",tostring(path))
    return
  end
  if path==current_folder then return end
  table.insert(historyBack,current_folder)
  historyFwd={}
  setFolder(path)
end

local function openItem(name)
  local full=fs.concat(current_folder,name)
  if fs.isDirectory(full) and not name:gsub("/+$",""):match("%.app$") then
    navigate(full)
    return
  end
  local prog,err
  if fs.isDirectory(full) then
    prog,err=_G.ltde_launch(full,nil,{})
  else
    prog,err=ltwapi.openFile(full)
  end
  if not prog then ltnotify.error("Open failed",tostring(err)) end
end

---File operation helpers

local fileops=assert(loadfile("/ltde/sys/slib/ltfiles.lua"))()

local function showConflictDialog(name)
  return ltnotify.dialog("File Conflict","Already exists: "..name,
    {"Replace","Rename","Skip","Cancel"},nil,nil,{checkbox="Apply to all (Replace / Skip)"})
end

local function showProgressFrame(opTitle,total)
  local PW,PH=44,6
  local px=math.floor((tgl.defaults.screenSizeX-PW)/2)+1
  local py=math.floor((tgl.defaults.screenSizeY-PH)/2)
  local col=tgl.Color2:new(0,0xE8E8E8)
  local titleCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
  local pbcol=tgl.Color2:new(tgl.defaults.colors16.darkblue,0xE8E8E8)

  local titleTxt=tgl.Frame:new({tgl.Text:new(opTitle,titleCol,tgl.Pos2:new(2,1))},
    tgl.Size2:newFromSize(2,2,PW-2,1),titleCol)
  local statusTxt=tgl.Text:new("",col,tgl.Pos2:new(2,3))
  statusTxt.maxLength=PW-4   -- enables blank-before-write to clear previous text
  local pbar=ltui.Progressbar:new(tgl.Pos2:new(2,4),PW-4,pbcol)
  local countTxt=tgl.Text:new("0 / "..tostring(total),col,tgl.Pos2:new(2,5))
  countTxt.maxLength=16

  local pf=tgl.Frame:new({t=titleTxt,s=statusTxt,pb=pbar,c=countTxt},
    tgl.Size2:newFromSize(px,py,PW,PH),col)
  pf.borders="─│┌┐└┘"

  local state=ltnotify.openModal(pf)

  local function update(status,done,newTotal)
    if newTotal then total=newTotal end
    statusTxt.text=status
    pbar:setValue(total>0 and done/total or 0)
    countTxt.text=done.." / "..total
    if state.wm then state.wm:renderRegions({pf.size2})
    else r:stop() pf:render() r:flush(true) end
  end

  local function close()
    ltnotify.closeModal(pf,state)
  end

  return update,close
end

local function runPaste(srcFolder,files,op,destFolder)
  local total,done=0,0
  local update,closeProgress=showProgressFrame(
    op=="copy" and "Copying files and folders" or "Moving files and folders",0)
  local errors={}
  local cancelled=false
  local conflictAction=nil
  local function conflict(name)
    if conflictAction then return conflictAction end
    local action,applyAll=showConflictDialog(name)
    if applyAll and (action=="Replace" or action=="Skip") then conflictAction=action end
    return action
  end
  local ok,err=pcall(function()
    for _,name in ipairs(files) do
      local path=fs.concat(srcFolder,name)
      update("Counting: "..name,0)
      local info=fileops.info(path)
      if info then
        total=total+info.files+info.folders+(fs.isDirectory(path) and 1 or 0)
      end
    end
    update("Preparing...",0,total)
    for _,name in ipairs(files) do
      name=name:gsub("/+$","")
      local src=fs.concat(srcFolder,name)
      local dst=fs.concat(destFolder,name)
      if op=="copy" and fileops.same(srcFolder,destFolder) then
        local base,ext=name:match("^(.-)(%.[^%.]+)$")
        if fs.isDirectory(src) or not base or base=="" then base=name ext="" end
        local n=1
        repeat
          dst=fs.concat(destFolder,base.." (Copy"..(n>1 and " "..n or "")..")"..ext)
          n=n+1
        until not fs.exists(dst)
      end
      local copied,reason,stopped=fileops.transfer(src,dst,op~="copy",{
        conflict=conflict,
        rename=function() return ltnotify.prompt("Rename destination","New name for copy:") end,
        update=function(path) update("Copying: "..fs.name(path),done) end,
        completed=function(path)
          done=done+1
          update("Copied: "..fs.name(path),done)
        end
      })
      if not copied then errors[#errors+1]=name..": "..tostring(reason) end
      if stopped then cancelled=true break end
      update((copied and "Finished: " or "Incomplete: ")..name,done)
    end
  end)
  closeProgress()
  if not ok then errors[#errors+1]=tostring(err) end
  return errors,cancelled
end

local function updateBookmarks()
  local items={
    {label="Add current folder",eventName=events.toolbar.bookmark,value="add"},
    {label="Remove current folder",eventName=events.toolbar.bookmark,value="remove"}
  }
  for _,key in ipairs(bookmarks:keys("folders")) do
    local path=bookmarks:get("folders",key)
    if type(path)=="string" and path~="" then
      items[#items+1]={label=path,eventName=events.go,value=path}
    end
  end
  ltwapi.setMenuItems(frame,"Bookmarks",items)
end

local function updateLayout()
  local left=showSidebar and 13 or 1
  local bottom=showStatusbar and app_y-1 or app_y
  sidebar.hidden=not showSidebar
  if showSidebar then sidebar:enableAll() else sidebar:disableAll() end
  local function resize(obj,x,y,w,h)
    obj.relsize2=tgl.Size2:newFromSize(x,y,w,h)
    obj.size2=tgl.Size2:newFromSize(frame.size2.x1+x-1,frame.size2.y1+y-1,w,h)
  end
  resize(frame.objects.colheader,left,4,app_x-left+1,1)
  resize(frame.objects.folderbar,left,5,app_x-left+1,bottom-4)
  resize(frame.objects.footbar,left,app_y,app_x-left+1,1)
  frame.objects.footbar.hidden=not showStatusbar
  COL_NAME_W=app_x-left-COL_SIZE_W-COL_DATE_W
  FOOT_W=app_x-left+1
  FOOT_STATUS_X=FOOT_W-FOOT_STATUS_W+1
  foot_info.maxLength=FOOT_STATUS_X-2
  foot_status.relpos2=tgl.Pos2:new(FOOT_STATUS_X,1)
  frame:translate()
  displayFolder(true)
  rerender()
end

---Main
updateBookmarks()
updateDevices()
local initialProxy=fs.get(current_folder)
currentDevice=initialProxy and initialProxy.address or nil
frame:enableAll()
updateSortHeaders()
displayFolder()
rerender()

while true do
  local ev,a,k1,k2=ltevent.pull(1)
  if computer.uptime()-lastDeviceCheck>=2 or ev==events.toolbar.refresh then
    lastDeviceCheck=computer.uptime()
    if updateDevices() then
      local present=currentDevice==nil
      for _,dev in ipairs(devices) do if dev.id==currentDevice then present=true end end
      local proxy=current_folder~="devices" and fs.get(current_folder) or nil
      if current_folder~="devices" and (not present or not fs.isDirectory(current_folder)
      or (currentDevice and (not proxy or proxy.address~=currentDevice))) then
        setFolder("devices")
        setFootStatus("Removed")
      elseif current_folder=="devices" then displayFolder() end
      rerender()
    end
  end
  if ev==events.close then break
  elseif ev=="key_down" then
    if k2==211 then ltevent.push(events.toolbar.delete)    -- Del
    elseif k2==1 then ltevent.push(events.toolbar.deselect)  -- Esc
    elseif k1==14 and k2==49 then ltevent.push(events.toolbar.newfile)   -- Ctrl+N
    elseif k1==6  and k2==33 then ltevent.push(events.toolbar.find)      -- Ctrl+F
    elseif k1==15 and k2==24 then ltevent.push(events.toolbar.open)      -- Ctrl+O
    elseif k1==1  and k2==30 then ltevent.push(events.toolbar.selectAll) -- Ctrl+A
    elseif k1==26 and k2==44 then ltevent.push(events.toolbar.undo)      -- Ctrl+Z
    elseif k1==3  and k2==46 then ltevent.push(events.toolbar.copy)      -- Ctrl+C
    elseif k1==22 and k2==47 then ltevent.push(events.toolbar.paste)     -- Ctrl+V
    elseif k1==24 and k2==45 then ltevent.push(events.toolbar.cut)       -- Ctrl+X
    elseif k1==4  and k2==32 then ltevent.push(events.toolbar.duplicate) -- Ctrl+D
    elseif k1==18 and k2==19 then ltevent.push(events.toolbar.rename)    -- Ctrl+R
    elseif k1==13 and k2==50 then ltevent.push(events.toolbar.move)      -- Ctrl+M
    end

  elseif ev==events.go then
    if a=="devices" then
      navigate("devices")
    elseif a=="bookmarks" then
      ltwapi.showMenu(sidebar.objects[6].pos2,ltwapi.getMenuItems(frame,"Bookmarks"),mediumgray)
    elseif a and a~="" then
      navigate(a)
    end

  elseif ev==events.back then
    if #historyBack>0 then
      table.insert(historyFwd,current_folder)
      setFolder(table.remove(historyBack))
    end

  elseif ev==events.forward then
    if #historyFwd>0 then
      table.insert(historyBack,current_folder)
      setFolder(table.remove(historyFwd))
    end

  elseif ev==events.up then
    local parent=parentOf(current_folder)
    if parent~=current_folder then navigate(parent) end

  elseif ev==events.home then
    navigate(home_folder)

  elseif ev==events.input then
    local path=tostring(a or ""):match("^%s*(.-)%s*$")
    if path~="" then navigate(path) end

  elseif ev==events.toolbar.open then
    addrbar.objects.input:disable()
    addrbar.objects.input:input()
    local path=addrbar.objects.input.text:match("^%s*(.-)%s*$")
    addrbar.objects.input:enable()
    if path~="" then navigate(path) end

  elseif ev==events.select then
    local name=a
    local now=computer.uptime()
    if name==lastClickName and (now-lastClickTime)<DBLCLICK and not keyboard.isControlDown() then
      lastClickName=nil
      openItem(name)
    else
      lastClickName=name
      lastClickTime=now
      if keyboard.isControlDown() then
        if selected[name] then selected[name]=nil
        else selected[name]=true end
      else
        selected={}
        selected[name]=true
      end
      displayFolder(true)
      rerenderFolder()
    end

  elseif ev==events.toolbar.deselect then
    selected={}
    lastClickName=nil
    displayFolder()
    rerenderFolder()

  elseif current_folder=="devices" and (ev==events.toolbar.newfolder or ev==events.toolbar.newfile
  or ev==events.toolbar.copy or ev==events.toolbar.cut or ev==events.toolbar.paste
  or ev==events.toolbar.rename or ev==events.toolbar.delete or ev==events.toolbar.move
  or ev==events.toolbar.duplicate or ev==events.toolbar.selectAll) then
    ltnotify.warn("Devices","Open a device folder first.")

  elseif ev==events.toolbar.selectAll then
    local sf=frame.objects.folderbar
    for _,obj in pairs(sf.objects) do
      if obj.callValue then selected[obj.callValue]=true end
    end
    displayFolder()
    rerenderFolder()

  elseif ev==events.toolbar.refresh then
    searchText=nil
    setFootStatus("")
    selected={}
    displayFolder()
    rerenderFolder()

  elseif ev==events.sort and current_folder~="devices" then
    if a==sortBy then
      sortDir=sortDir=="asc" and "desc" or "asc"
    else
      sortBy=a
      sortDir="asc"
    end
    updateSortHeaders()
    displayFolder()
    rerenderFolder()

  elseif ev==events.toolbar.hidden then
    showHidden=not showHidden
    local viewItems=ltwapi.getMenuItems(frame,"View")
    if viewItems then
      for _,mi in ipairs(viewItems) do
        if mi.eventName==events.toolbar.hidden then
          mi.label=showHidden and "Hide hidden files" or "Show hidden files"
          break
        end
      end
    end
    displayFolder()
    rerenderFolder()

  elseif ev==events.toolbar.newfolder then
    local name=ltnotify.prompt("New Folder","Enter folder name:")
    if name and not fileops.validName(name) then
      ltnotify.warn("Invalid name","Use a single file or folder name.")
    elseif name then
      local full=fs.concat(current_folder,name)
      if fs.exists(full) then
        ltnotify.warn("Already exists",name)
      else
        local ok,err=fs.makeDirectory(full)
        if ok then displayFolder() rerenderFolder()
        else ltnotify.error("Create failed",tostring(err)) end
      end
    end

  elseif ev==events.toolbar.newfile then
    local name=ltnotify.prompt("New File","Enter file name:")
    if name and not fileops.validName(name) then
      ltnotify.warn("Invalid name","Use a single file or folder name.")
    elseif name then
      local full=fs.concat(current_folder,name)
      if fs.exists(full) then
        ltnotify.warn("Already exists",name)
      else
        local f2,err=io.open(full,"w")
        if f2 then
          f2:close()
          displayFolder()
          rerenderFolder()
        else
          ltnotify.error("Create failed",tostring(err))
        end
      end
    end

  elseif ev==events.toolbar.delete then
    local selN=selCount()
    if selN==0 then
      ltnotify.warn("Nothing selected","Select an item first.")
    elseif selN==1 then
      local sel=next(selected)
      local chosen=ltnotify.dialog("Delete","Delete '"..sel.."'?",{"Yes","No"})
      if chosen=="Yes" then
        local ok,err=fs.remove(fs.concat(current_folder,sel))
        if ok then selected={} displayFolder() rerenderFolder()
        else ltnotify.error("Delete failed",tostring(err)) end
      end
    else
      local chosen=ltnotify.dialog("Delete","Delete "..selN.." items?",{"Yes","No"})
      if chosen=="Yes" then
        local failed={}
        for name in pairs(selected) do
          local ok,_=fs.remove(fs.concat(current_folder,name))
          if not ok then failed[#failed+1]=name end
        end
        selected={}
        displayFolder()
        rerenderFolder()
        if #failed>0 then
          ltnotify.error("Delete failed",table.concat(failed,", "))
        end
      end
    end

  elseif ev==events.toolbar.rename then
    if selCount()>1 then
      ltnotify.warn("Rename","Select only one item.")
    else
      local sel=next(selected)
      if sel then
        local newName=ltnotify.prompt("Rename","New name for '"..sel.."':")
        if newName and not fileops.validName(newName) then
          ltnotify.warn("Invalid name","Use a single file or folder name.")
        elseif newName and newName~=sel then
          local old=fs.concat(current_folder,sel)
          local new=fs.concat(current_folder,newName)
          if fs.exists(new) then
            ltnotify.warn("Already exists",newName)
          else
            local ok,err=fs.rename(old,new)
            if ok then
              undoRename={src=new,dst=old}
              selected={}
              displayFolder()
              rerenderFolder()
            else
              ltnotify.error("Rename failed",tostring(err))
            end
          end
        end
      else
        ltnotify.warn("Nothing selected","Select an item first.")
      end
    end

  elseif ev==events.toolbar.copy then
    local files={}
    for name in pairs(selected) do files[#files+1]=name end
    if #files==0 then ltnotify.warn("Copy","Nothing selected.")
    else
      _G._ltde_fileClipboard={op="copy",folder=current_folder,files=files}
      setFootStatus(#files.." copied")
      rerenderFolder()
    end

  elseif ev==events.toolbar.cut then
    local files={}
    for name in pairs(selected) do files[#files+1]=name end
    if #files==0 then ltnotify.warn("Cut","Nothing selected.")
    else
      _G._ltde_fileClipboard={op="cut",folder=current_folder,files=files}
      setFootStatus(#files.." cut")
      rerenderFolder()
    end

  elseif ev==events.toolbar.paste then
    local clipboard=_G._ltde_fileClipboard
    if not clipboard then
      ltnotify.warn("Paste","Clipboard is empty.")
    else
      local files=clipboard.files
      local op=clipboard.op
      local src=clipboard.folder
      local errs,cancelled=runPaste(src,files,op,current_folder)
      if op=="cut" and #errs==0 and not cancelled then _G._ltde_fileClipboard=nil end
      selected={}
      displayFolder()
      if cancelled then setFootStatus("Cancelled.")
      elseif #errs==0 then setFootStatus("Pasted.") end
      rerenderFolder()
      if #errs>0 and not cancelled then ltnotify.error("Operation failed",errs[1]) end
    end

  elseif ev==events.toolbar.duplicate then
    local files={}
    for name in pairs(selected) do files[#files+1]=name end
    if #files==0 then ltnotify.warn("Duplicate","Nothing selected.")
    else
      local errs,cancelled=runPaste(current_folder,files,"copy",current_folder)
      selected={}
      displayFolder()
      rerenderFolder()
      if #errs>0 and not cancelled then ltnotify.error("Duplicate failed",errs[1]) end
    end

  elseif ev==events.toolbar.move then
    if selCount()==0 then
      ltnotify.warn("Move","Nothing selected.")
    else
      local dest=ltnotify.prompt("Move to","Destination folder:")
      if dest and dest~="" then
        if not fs.isDirectory(dest) then
          ltnotify.warn("Move","Not a folder: "..dest)
        else
          local files={}
          for name in pairs(selected) do files[#files+1]=name end
          local errs,cancelled=runPaste(current_folder,files,"cut",dest)
          selected={}
          displayFolder()
          rerenderFolder()
          if #errs>0 and not cancelled then ltnotify.error("Move failed",errs[1]) end
        end
      end
    end

  elseif ev==events.toolbar.find or ev==events.toolbar.findinfiles then
    if current_folder=="devices" then ltnotify.warn("Find","Open a folder first.")
    else
      local text=ltnotify.prompt("Find in current folder","Text to find (empty clears search):")
      if text then
        searchMatches={}
        searchText=text~="" and text:lower() or nil
        searchContents=ev==events.toolbar.findinfiles
        selected={}
        displayFolder()
        setFootStatus(searchText and "Filtered" or "")
        rerenderFolder()
      end
    end

  elseif ev==events.toolbar.sidebar then
    showSidebar=not showSidebar
    updateLayout()

  elseif ev==events.toolbar.statusbar then
    showStatusbar=not showStatusbar
    updateLayout()

  elseif ev==events.toolbar.list then
    listView=not listView
    displayFolder(true)
    rerenderFolder()

  elseif ev==events.toolbar.bookmark then
    if current_folder=="devices" then ltnotify.warn("Bookmarks","Open a folder first.")
    else
      local paths={}
      for _,key in ipairs(bookmarks:keys("folders")) do
        local path=bookmarks:get("folders",key)
        if type(path)=="string" and path~="" and path~=current_folder then paths[#paths+1]=path end
      end
      if a=="add" then paths[#paths+1]=current_folder end
      local cfg=cfglib.new()
      for i,path in ipairs(paths) do cfg:set("folders","folder"..i,path) end
      local ok,err=cfg:save("/ltde/cfg/bookmarks.conf")
      if ok then bookmarks=cfg updateBookmarks()
      else ltnotify.error("Bookmarks",tostring(err)) end
    end

  elseif ev==events.toolbar.undo then
    if not undoRename then ltnotify.warn("Undo rename","No rename to undo.")
    elseif fs.exists(undoRename.dst) or not fs.exists(undoRename.src) then
      ltnotify.warn("Undo rename","The file or original name has changed.")
    else
      local ok,err=fs.rename(undoRename.src,undoRename.dst)
      if ok then undoRename=nil selected={} displayFolder() rerenderFolder()
      else ltnotify.error("Undo rename",tostring(err)) end
    end

  elseif ev==events.toolbar.help then
    ltnotify.dialog("Explorer Help",
      "Double-click: open. Ctrl-click: select.\n"..
      "Find searches the current folder.\n"..
      "Refresh clears the search.\n"..
      "Find in files searches contents.\n"..
      "Bookmarks are saved between sessions.\n"..
      "Undo reverses the last rename only.\n\n"..
      "Skipped/cancelled moves keep the source.\n"..
      "Completed copies stay at the destination.",{"OK"})

  elseif ev==events.toolbar.properties then
    if current_folder=="devices" then
      ltnotify.warn("Properties","Open a device folder first.")
    elseif selCount()>1 then
      ltnotify.warn("Properties","Select one file or folder.")
    else
      local name=next(selected)
      local path=name and fs.concat(current_folder,name) or current_folder
      setFootStatus("Calculating")
      rerenderFolder()
      local info,err=fileops.info(path)
      setFootStatus("")
      rerenderFolder()
      if not info then ltnotify.error("Properties",tostring(err))
      else
        local proxy=fs.get(path)
        local readOnly=proxy and deviceValue(proxy,"isReadOnly")
        local ok,date=pcall(fs.lastModified,path)
        local isDir=fs.isDirectory(path)
        local isLink=fs.isLink and fs.isLink(path)
        local details={
          "Name: "..truncPad(fs.name(path) or "/",44),
          "Path: "..truncPad(path,44),
          "Type: "..(isLink and "Symbolic link" or isDir and "Folder" or "File"),
          "Size: "..sizeStr(info.bytes).." ("..string.format("%.0f",info.bytes).." bytes)",
          "Modified: "..fmtDate(ok and date or nil),
          "Device access: "..(readOnly==nil and "?" or readOnly and "r" or "rw")
        }
        if isDir then details[#details+1]="Contains: "..info.files.." files, "..info.folders.." folders" end
        if info.skipped>0 then
          details[#details+1]="Partial size: "..info.skipped.." items skipped."
          details[#details+1]="Links, other mounts or unreadable items excluded."
        end
        ltnotify.dialog("Properties",table.concat(details,"\n"),{"OK"})
      end
    end

  elseif ev==events.toolbar.about then
    ltnotify.dialog("File Explorer","LTDE File Explorer v"..version,{"OK"})

  end
end

frame:disableAll()
os.sleep(0.3)
return 0
