local event=require("event")
local unicode=require("unicode")
local tgl=require("tgl")
local startmenu={}
local _wmgr=nil
local _handler=nil
local _open=false
local _active=nil
local _serial=0
local MENU_W=30
local LOGO_W=2
local MAX_ROWS=12
local APPS_DIR="/ltde/apps"
local _bgCol,_logoCol,_shutdownCol

local function fit(text,width)
  text=tostring(text)
  while unicode.wlen(text)>width do text=unicode.sub(text,1,unicode.len(text)-1) end
  return text..string.rep(" ",width-unicode.wlen(text))
end

local function scanApps()
  local fs=require("filesystem")
  local apps={}
  local iter=fs.list(APPS_DIR)
  if iter then for name in iter do
    local dir=name:gsub("/+$","")
    local path=fs.concat(APPS_DIR,dir)
    if dir:match("%.app$") and fs.isDirectory(path) then
      local label=dir:sub(1,-5)
      local chunk=loadfile(fs.concat(path,"manifest.lua"),"t",{})
      if chunk then
        local ok,manifest=pcall(chunk)
        if ok and type(manifest)=="table" and type(manifest.name)=="string" then label=manifest.name end
      end
      apps[#apps+1]={name=label,path=path}
    end
  end end
  table.sort(apps,function(a,b)
    if a.name:lower()==b.name:lower() then return a.path<b.path end
    return a.name:lower()<b.name:lower()
  end)
  return apps
end

local function closeActive()
  local active=_active
  if not active then return end
  _active=nil
  if active.frame.objects.search then active.frame.objects.search.hidden=true end
  event.ignore("touch",active.outside)
  ltnotify.closeModal(active.frame,active.modal)
end

local function openPopup(frame,done)
  local active={frame=frame,done=done}
  active.modal=ltnotify.openModal(frame)
  active.outside=function(_,_,x,y)
    if not tgl.util.pointInSize2(x,y,frame.size2) then event.push(done) end
  end
  _active=active
  event.listen("touch",active.outside)
end

local function showShutdownDialog()
  _serial=_serial+1
  local done="ltde_power_".._serial
  local w,h=26,8
  local sw,sh=tgl.defaults.screenSizeX,tgl.defaults.screenSizeY
  local objects={
    title=tgl.Frame:new({tgl.Text:new("Power Options",_logoCol,tgl.Pos2:new(2,1))},tgl.Size2:new(2,2,w-2,1),_logoCol)
  }
  local choices={
    {"Exit to Shell","ltde_shutdown_request"},
    {"Restart LTDE","ltde_restart_ltde"},
    {"Shut Down Computer","ltde_computer_poweroff"},
    {"Restart Computer","ltde_computer_restart"},
    {"Cancel",nil}
  }
  for i,choice in ipairs(choices) do
    local btn=tgl.EventButton(fit(" "..choice[1],w-4),done,choice[2],tgl.Pos2:new(3,i+2),i==3 and _shutdownCol or _bgCol)
    btn.onClick=nil
    objects[i]=btn
  end
  local frame=tgl.Frame:new(objects,tgl.Size2:new(math.floor((sw-w)/2)+1,math.floor((sh-h)/2)+1,w,h),_bgCol)
  frame.borders="─│┌┐└┘"
  openPopup(frame,done)
  local ok,result=pcall(function()
    while _active do
      local ev,value,_,code=event.pull()
      if ev==done then return value end
      if ev=="key_down" and code==1 then return end
    end
  end)
  closeActive()
  if not ok then error(result,0) end
  if result then event.push(result) end
end

function startmenu.open()
  if _open or not _wmgr then return end
  _open=true
  local ok,err=pcall(function()
    _serial=_serial+1
    local done="ltde_start_done_".._serial
    local searchEvent="ltde_start_search_".._serial
    local apps=scanApps()
    local sh=tgl.defaults.screenSizeY
    local w=math.min(MENU_W,tgl.defaults.screenSizeX)
    local rows=math.max(1,math.min(MAX_ROWS,sh-5,math.max(4,#apps)))
    local h=rows+3
    local contentW=w-LOGO_W
    local frame=tgl.Frame:new({},tgl.Size2:new(1,sh-h,w,h),_bgCol)
    local logoObjects={}
    local name="LTDEv1"
    for i=1,math.min(#name,h) do
      logoObjects[i]=tgl.Text:new(name:sub(i,i),_logoCol,tgl.Pos2:new(2,i))
    end
    frame:add(tgl.Frame:new(logoObjects,tgl.Size2:new(1,1,LOGO_W,h),_logoCol),"logo")
    frame:add(tgl.Text:new("Find:",_bgCol,tgl.Pos2:new(3,h-1)),"label")
    local search=tgl.InputField:new(string.rep(" ",contentW-7),tgl.Pos2:new(9,h-1),tgl.Color2:new(0,0xFFFFFF))
    search.text=""
    search.erase=false
    search.scrollX=true
    search.stopOnClickOutside=true
    search.stopEventName=done
    search.eventName=searchEvent
    frame:add(search,"search")
    local list=tgl.ScrollFrame:new({},tgl.Size2:new(3,1,contentW,rows),_bgCol)
    frame:add(list,"apps")
    frame:add(tgl.Text:new(string.rep("─",contentW),_bgCol,tgl.Pos2:new(3,h-2)),"separator")
    local shut=tgl.EventButton(fit(" Shut Down...",contentW),done,"__shutdown__",tgl.Pos2:new(3,h),_shutdownCol)
    shut.onClick=nil
    frame:add(shut,"shutdown")
    local function filter(query)
      query=tostring(query or ""):lower()
      list:disableAll()
      list.objects={}
      list.scroll=0
      local count=0
      for _,app in ipairs(apps) do
        if app.name:lower():find(query,1,true) or app.path:lower():find(query,1,true) then
          count=count+1
          local btn=tgl.EventButton(fit(" "..app.name,contentW-1),done,app.path,tgl.Pos2:new(1,count),_bgCol)
          btn.onClick=nil
          list.objects[count]=btn
        end
      end
      if count==0 then list.objects[1]=tgl.Text:new(" No matching apps",_bgCol,tgl.Pos2:new(1,1)) end
      list.maxScroll=math.max(0,count-rows)
      frame:translate()
      list:translate()
      if _active then
        list:enableAll()
        _wmgr:renderRegions({frame.size2})
      end
    end
    filter("")
    openPopup(frame,done)
    local result=nil
    while _active do
      local ev,value,_,code=event.pull()
      if ev==done then result=value break
      elseif ev==searchEvent then filter(value)
      elseif ev=="key_down" and code==1 then break end
    end
    closeActive()
    if result=="__shutdown__" then showShutdownDialog()
    elseif result then event.push("ltde_open_app",result) end
  end)
  closeActive()
  _open=false
  if not ok then error(err,0) end
end

function startmenu.init(wmgr)
  _wmgr=wmgr
  _bgCol=tgl.Color2:new(0,0xE1E1E1)
  _logoCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
  _shutdownCol=tgl.defaults.colors2.close
  _handler=function() startmenu.open() end
  event.listen("ltde_start_menu",_handler)
end

function startmenu.cleanup()
  if _active then event.push(_active.done) end
  closeActive()
  if _handler then event.ignore("ltde_start_menu",_handler) _handler=nil end
  _open=false
  _wmgr=nil
end

return startmenu
