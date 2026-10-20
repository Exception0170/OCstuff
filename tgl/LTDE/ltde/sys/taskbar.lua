local event=require("event")
local unicode=require("unicode")
local tgl=require("tgl")
local taskbar={}

local TAB_MAX=15
local TAB_MIN=4
local START_W=9   -- len(" [Start] ")

local _frame=nil
local _wmgr=nil
local _updateHandler=nil
---@type table[]
local _applets={}     -- ordered list, leftmost applet first
local _appletMap={}   -- id -> applet
local _tbCol,_startCol,_activeTabCol

local function getTitle(mwin)
  return mwin.frame.wmTitle or "?"
end

local function totalAppletWidth()
  local w=0
  for _,a in ipairs(_applets) do w=w+a.width end
  return w
end

---Update a single applet's label in-place and re-render the taskbar.
---Called by per-applet tick timers; does NOT rebuild tabs.
local function refreshApplet(a)
  if not _frame then return end
  local obj=_frame.objects["aplt_"..a.id]
  if not obj then return end
  local lbl=type(a.getLabel)=="function" and a.getLabel() or string.rep(" ",a.width)
  local lw=unicode.wlen(lbl)
  if lw>a.width then lbl=unicode.sub(lbl,1,a.width)
  elseif lw<a.width then lbl=lbl..string.rep(" ",a.width-lw) end
  if obj.type=="Text" then
    obj:updateText(lbl)
  else  -- Button
    obj.text=lbl
  end
  local r=tgl.sys.renderer
  r:stop()
  _frame:render()
  r:flush()
end

local function rebuildTabs()
  -- remove old dynamic objects
  local toRemove={}
  for k in pairs(_frame.objects) do
    if type(k)=="string" and (k:sub(1,4)=="tab_" or k:sub(1,5)=="aplt_") then
      toRemove[#toRemove+1]=k
    end
  end
  for _,k in ipairs(toRemove) do _frame:remove(k) end

  local sw=tgl.defaults.screenSizeX

  -- sorted window list
  local ordered={}
  for _,m in ipairs(_wmgr.windows) do ordered[#ordered+1]=m end
  table.sort(ordered,function(a,b) return (a.insertIdx or 0)<(b.insertIdx or 0) end)

  local numTabs=0
  for _,mwin in ipairs(ordered) do
    if not mwin.noTaskbar then numTabs=numTabs+1 end
  end

  -- available tab area
  local aw=totalAppletWidth()
  local sepW=(aw>0) and 1 or 0   -- gap between tabs and applets
  local tabAreaW=sw-START_W-1-sepW-aw
  local tabAreaEnd=sw-aw-sepW

  -- per-tab width
  local tabW=TAB_MAX
  if numTabs>0 then
    tabW=math.max(TAB_MIN,math.min(TAB_MAX,math.floor(tabAreaW/numTabs)))
  end

  -- place tab buttons
  local x=START_W+2
  local idx=0
  for _,mwin in ipairs(ordered) do
    if not mwin.noTaskbar then
      idx=idx+1
      if x+tabW-1>tabAreaEnd then break end

      local title=getTitle(mwin)
      local raw=mwin.minimized and ("["..title.."]") or title
      local maxRaw=tabW-1
      if unicode.wlen(raw)>maxRaw then
        raw=unicode.sub(raw,1,math.max(1,maxRaw-2))..".."
      end
      local label=" "..raw..string.rep(" ",maxRaw-unicode.wlen(raw))

      local col=(_wmgr.activeWindow==mwin) and _activeTabCol or _tbCol
      local cap=mwin
      local btn=tgl.Button:new(label,function()
        if cap.minimized then _wmgr:restoreWindow(cap)
        else _wmgr:bringToFront(cap) end
      end,tgl.Pos2:new(x,1),col)
      btn.checkRendered=false
      btn.onClick=nil
      _frame:add(btn,"tab_"..idx)
      x=x+tabW
    end
  end

  -- place applets right-to-left
  local ax=sw+1
  for i=#_applets,1,-1 do
    local a=_applets[i]
    ax=ax-a.width
    a._ax=ax

    local lbl=type(a.getLabel)=="function" and a.getLabel() or string.rep(" ",a.width)
    local lw=unicode.wlen(lbl)
    if lw>a.width then lbl=unicode.sub(lbl,1,a.width)
    elseif lw<a.width then lbl=lbl..string.rep(" ",a.width-lw) end

    local col=a.col2 or _tbCol
    if type(a.onClick)=="function" then
      local cap=a
      local btn=tgl.Button:new(lbl,function() cap.onClick(cap._ax,1) end,
        tgl.Pos2:new(ax,1),col)
      btn.checkRendered=false
      btn.onClick=nil
      _frame:add(btn,"aplt_"..a.id)
    else
      _frame:add(tgl.Text:new(lbl,col,tgl.Pos2:new(ax,1)),"aplt_"..a.id)
    end
  end

  _frame:enableAll()
end

local function renderSelf()
  local r=tgl.sys.renderer
  r:stop()
  _frame:render()
  r:flush()
end

---Register an applet on the right side of the taskbar.
---Applets stack leftward from the screen edge; first registered = leftmost.
---
---  width     integer            character width (required)
---  getLabel  function()->string called on render and on each tick (required)
---  tick      number             if set, auto-refresh interval in seconds
---  col2      tgl.Color2         color override (optional)
---  onClick   function(x,y)      click handler — makes the applet a button (optional)
---
---@param id string unique identifier
---@param config table
function taskbar.addApplet(id,config)
  if _appletMap[id] then taskbar.removeApplet(id) end
  local a={id=id,width=config.width,getLabel=config.getLabel,
           col2=config.col2,onClick=config.onClick}
  if config.tick then
    a._timer=event.timer(config.tick,function() refreshApplet(a) end,math.huge)
  end
  table.insert(_applets,a)
  _appletMap[id]=a
  if _frame then rebuildTabs() renderSelf() end
end

---Remove an applet and cancel its tick timer if any.
---@param id string
function taskbar.removeApplet(id)
  local a=_appletMap[id]
  if not a then return end
  if a._timer then event.cancel(a._timer) a._timer=nil end
  for i,ap in ipairs(_applets) do
    if ap.id==id then table.remove(_applets,i) break end
  end
  _appletMap[id]=nil
  if _frame then rebuildTabs() renderSelf() end
end

function taskbar.init(wmgr)
  _wmgr=wmgr
  local sw=tgl.defaults.screenSizeX
  local sh=tgl.defaults.screenSizeY

  _tbCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
  _startCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkgray)
  _activeTabCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)

  -- built-in clock (registered before frame so first rebuildTabs includes it)
  local clockApplet={id="clock",width=14,getLabel=function()
    local ok,t=pcall(os.date," %b %d %H:%M ")
    return ok and t or "  ---  --:-- "
  end}
  clockApplet._timer=event.timer(1,function() refreshApplet(clockApplet) end,math.huge)
  _applets={clockApplet}
  _appletMap["clock"]=clockApplet

  local startBtn=tgl.Button:new(" [Start] ",function()
    event.push("ltde_start_menu")
  end,tgl.Pos2:new(1,1),_startCol)
  startBtn.checkRendered=false
  startBtn.onClick=nil

  _frame=tgl.Frame:new({start=startBtn},
    tgl.Size2:newFromSize(1,sh,sw,1),_tbCol)
  _frame.wmTitle="taskbar"

  wmgr:addWindowDirect(_frame,nil,true)
  _frame.z_index=9000
  wmgr:sortWindows()

  rebuildTabs()
  _frame.hidden=false
  renderSelf()

  _updateHandler=function()
    rebuildTabs()
    renderSelf()
  end
  event.listen("ltde_taskbar_update",_updateHandler)

  wmgr.onFocusChange=function(_)
    rebuildTabs()
    renderSelf()
  end
end

function taskbar.cleanup()
  if _updateHandler then
    event.ignore("ltde_taskbar_update",_updateHandler)
    _updateHandler=nil
  end
  for _,a in ipairs(_applets) do
    if a._timer then event.cancel(a._timer) end
  end
  if _wmgr then
    _wmgr.onFocusChange=nil
    if _frame then
      local mwin=_wmgr:getManagedWindow(_frame)
      if mwin then _wmgr:closeWindow(mwin) end
    end
  end
  _applets={}
  _appletMap={}
  _frame=nil
  _wmgr=nil
end

return taskbar
