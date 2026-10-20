local event=require("event")
local thread=require("thread")
local tgl=require("tgl")
local ltwm={}

---@class ltwm.ManagedWindow
---@field frame tgl.Frame
---@field pid integer|nil
---@field noTaskbar boolean
---@field minimized boolean

---@class ltwm.WindowManager
---@field windows ltwm.ManagedWindow[]
---@field pidWindows table<integer,ltwm.ManagedWindow[]>
---@field activeWindow ltwm.ManagedWindow|nil
---@field locked boolean
---@field cascadeN integer
---@field bgCol2 tgl.Color2|nil wallpaper color; full-screen fill at z=-1 every renderAll
ltwm.WindowManager={}
ltwm.WindowManager.__index=ltwm.WindowManager

function ltwm.WindowManager:new()
  if tgl.sys.wm then return tgl.sys.wm end
  local obj=setmetatable({},self)
  obj.windows={}
  obj.pidWindows={}
  obj.activeWindow=nil
  obj.locked=false
  obj.cascadeN=0
  obj.bgCol2=nil
  obj.onFocusChange=nil  --set by taskbar: called with mwin on every bringToFront
  obj._insertCnt=0
  obj._dragThreads={}   -- tracked so cleanup() can kill any still-waiting ones
  obj._dragCursor="+"   -- overridden by core.lua from display.conf

  obj.resetHandler=function(_,_,key1)
    if key1==23 then obj:cleanup() tgl.util.clear() end
  end

  obj.focusHandler=function(_,_,x,y)
    if obj.locked then return end
    local mwin=obj:getWindowAt(x,y)
    if not mwin or mwin.noTaskbar then return end  --system UI: skip focus/drag
    if mwin~=obj.activeWindow then obj:bringToFront(mwin) end
    if y==mwin.frame.size2.y1 then
      local xOff=x-mwin.frame.size2.x1
      -- prune dead threads before adding a new one
      for i=#obj._dragThreads,1,-1 do
        if obj._dragThreads[i]:status()=="dead" then
          table.remove(obj._dragThreads,i)
        end
      end
      local t=thread.create(function()
        local r=tgl.sys.renderer
        local cursorCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.magenta)
        local saved=nil  -- {char,col,x,y} GPU cell saved under cursor

        local function eraseCursor()
          if not saved then return end
          tgl.changeToColor2(saved.col)
          r.gpu.set(saved.x,saved.y,saved.char)
          saved=nil
        end

        local function drawCursor(x,y)
          if obj._dragCursor=="" then return end
          local sw=tgl.defaults.screenSizeX
          local sh=tgl.defaults.screenSizeY
          if x<1 or x>sw or y<1 or y>sh then return end
          local char,col=r:getPoint(x,y)
          if not char then return end
          saved={char=char,col=col,x=x,y=y}
          tgl.changeToColor2(cursorCol)
          r.gpu.set(x,y,obj._dragCursor)
        end

        local id,_,dx,dy=event.pullMultiple("drag","drop")
        while id=="drag" do
          eraseCursor()
          drawCursor(dx,dy)
          id,_,dx,dy=event.pullMultiple("drag","drop")
        end
        eraseCursor()
        if id=="drop" and dx and dy then
          local sw=tgl.defaults.screenSizeX
          local sh=tgl.defaults.screenSizeY-1
          local nx=math.max(1,math.min(dx-xOff,sw-mwin.frame.size2.sizeX+1))
          local ny=math.max(1,math.min(dy,sh-mwin.frame.size2.sizeY+1))
          if nx~=mwin.frame.size2.x1 or ny~=mwin.frame.size2.y1 then
            obj:moveWindow(mwin,tgl.Pos2:new(nx,ny))
          end
        end
      end)
      t:detach()
      table.insert(obj._dragThreads,t)
    end
  end

  event.listen("key_down",obj.resetHandler)
  event.listen("touch",obj.focusHandler)
  tgl.sys.wm=obj
  tgl.util.log("LTWM initialized","LTWM")
  return obj
end

---@param col2 tgl.Color2
function ltwm.WindowManager:setBackground(col2)
  self.bgCol2=col2
end

---@param sizeX integer
---@param sizeY integer
---@return tgl.Pos2
function ltwm.WindowManager:getNextCascadePos(sizeX,sizeY)
  local sw=tgl.defaults.screenSizeX
  local sh=tgl.defaults.screenSizeY-1
  local x=3+(self.cascadeN*2)%(math.floor(sw/3))
  local y=2+(self.cascadeN)%(math.floor(sh/3))
  self.cascadeN=(self.cascadeN+1)%15
  return tgl.Pos2:new(math.min(x,sw-sizeX+1),math.min(y,sh-sizeY+1))
end

---@param frame tgl.Frame
---@param pid integer|nil
---@param noTaskbar boolean
---@return boolean
function ltwm.WindowManager:addWindow(frame,pid,noTaskbar)
  if not frame then return false end
  local pos=self:getNextCascadePos(frame.size2.sizeX,frame.size2.sizeY)
  frame:moveToPos2(pos)
  self._insertCnt=self._insertCnt+1
  local mwin={frame=frame,pid=pid,noTaskbar=noTaskbar or false,minimized=false,insertIdx=self._insertCnt}
  local maxZ=0
  for _,m in ipairs(self.windows) do
    if m.frame.z_index>maxZ then maxZ=m.frame.z_index end
  end
  frame.z_index=maxZ+1  --new windows always on top
  frame.wm_managed=true
  if pid then
    if not self.pidWindows[pid] then self.pidWindows[pid]={} end
    table.insert(self.pidWindows[pid],mwin)
  end
  table.insert(self.windows,mwin)
  self:sortWindows()
  if not noTaskbar then self:bringToFront(mwin) end
  return true
end

---@param frame tgl.Frame
---@param pid integer|nil
---@param noTaskbar boolean
---@return ltwm.ManagedWindow
function ltwm.WindowManager:addWindowDirect(frame,pid,noTaskbar)
  self._insertCnt=self._insertCnt+1
  local mwin={frame=frame,pid=pid,noTaskbar=noTaskbar or false,minimized=false,insertIdx=self._insertCnt}
  frame.z_index=#self.windows+100
  frame.wm_managed=true
  table.insert(self.windows,mwin)
  self:sortWindows()
  return mwin
end

---Register a modal overlay so renderAll always includes it in z-ordering.
---Does not change z_index, does not trigger taskbar/focus events.
---@param frame tgl.Frame
---@return ltwm.ManagedWindow
function ltwm.WindowManager:addOverlay(frame)
  self._insertCnt=self._insertCnt+1
  local mwin={frame=frame,pid=nil,noTaskbar=true,minimized=false,insertIdx=self._insertCnt}
  frame.wm_managed=true
  table.insert(self.windows,mwin)
  self:sortWindows()
  return mwin
end

---Remove a previously registered overlay frame.
---@param mwin ltwm.ManagedWindow
function ltwm.WindowManager:removeOverlay(mwin)
  self:_removeFromLists(mwin)
  mwin.frame.wm_managed=false
end

function ltwm.WindowManager:_removeFromLists(mwin)
  for i,m in ipairs(self.windows) do
    if m==mwin then table.remove(self.windows,i) break end
  end
  if mwin.pid and self.pidWindows[mwin.pid] then
    local pl=self.pidWindows[mwin.pid]
    for i,m in ipairs(pl) do
      if m==mwin then table.remove(pl,i) break end
    end
    if #pl==0 then self.pidWindows[mwin.pid]=nil end
  end
  if self.activeWindow==mwin then self.activeWindow=nil end
end

function ltwm.WindowManager:sortWindows()
  table.sort(self.windows,function(a,b)
    return a.frame.z_index<b.frame.z_index
  end)
end

---Get a copy of the visible bounds, including an outline border.
function ltwm.WindowManager:getWindowBounds(mwin)
  local s=mwin.frame.size2
  local border=mwin.frame.borders and mwin.frame.borderType=="outline" and 1 or 0
  return tgl.Size2:newFromPoint(math.max(1,s.x1-border),math.max(1,s.y1-border),
    math.min(tgl.defaults.screenSizeX,s.x2+border),math.min(tgl.defaults.screenSizeY,s.y2+border))
end

---Redraw damaged rectangles, keeping unrelated desktop areas untouched.
---@param regions tgl.Size2[]
function ltwm.WindowManager:renderRegions(regions)
  local dirty={}
  for _,s in ipairs(regions) do
    local parts={s}
    for _,other in ipairs(dirty) do
      local remaining={}
      for _,area in ipairs(parts) do
        if not tgl.util.size2Intersects(area,other) then
          table.insert(remaining,area)
        else
          local x1,y1=math.max(area.x1,other.x1),math.max(area.y1,other.y1)
          local x2,y2=math.min(area.x2,other.x2),math.min(area.y2,other.y2)
          local function add(ax1,ay1,ax2,ay2)
            if ax1<=ax2 and ay1<=ay2 then
              table.insert(remaining,tgl.Size2:newFromPoint(ax1,ay1,ax2,ay2))
            end
          end
          -- Subtract the overlap without adding the corners of a bounding box.
          add(area.x1,area.y1,area.x2,y1-1)
          add(area.x1,y2+1,area.x2,area.y2)
          add(area.x1,y1,x1-1,y2)
          add(x2+1,y1,area.x2,y2)
        end
      end
      parts=remaining
    end
    for _,area in ipairs(parts) do table.insert(dirty,area) end
  end
  local r=tgl.sys.renderer
  local prevClip=r:getClipRegion()
  r:stop()
  local ok,err=pcall(function()
    for _,area in ipairs(dirty) do
      r:setClipRegion(area)
      if self.bgCol2 then r:fill(area," ",self.bgCol2,-1) end
      for _,mwin in ipairs(self.windows) do
        if not mwin.minimized and not mwin.frame.hidden
        and tgl.util.size2Intersects(self:getWindowBounds(mwin),area) then
          mwin.frame:renderRegion(area)
        end
      end
    end
  end)
  r:setClipRegion(prevClip)
  r:flush(true)
  if not ok then error(err,0) end
end

---Flush all visible windows + optional full-screen background immediately.
function ltwm.WindowManager:renderAll()
  local r=tgl.sys.renderer
  r:stop()
  if self.bgCol2 then
    local sw=tgl.defaults.screenSizeX
    local sh=tgl.defaults.screenSizeY
    r:fill(tgl.Size2:newFromSize(1,1,sw,sh)," ",self.bgCol2,-1)
  end
  for _,mwin in ipairs(self.windows) do
    if not mwin.minimized then mwin.frame:render() end
  end
  r:flush()
end

---@param mwin ltwm.ManagedWindow
function ltwm.WindowManager:bringToFront(mwin)
  if not mwin then return end
  local regions={self:getWindowBounds(mwin)}
  local alreadyActive=(self.activeWindow==mwin)
  if not alreadyActive and self.activeWindow then
    table.insert(regions,self:getWindowBounds(self.activeWindow))
    local f=self.activeWindow.frame
    if type(f.onFocusChange)=="function" then f.onFocusChange(false) end
  end
  local maxZ=0
  for _,m in ipairs(self.windows) do
    if m.frame.z_index>maxZ then maxZ=m.frame.z_index end
  end
  mwin.frame.z_index=maxZ+1
  self:sortWindows()
  self.activeWindow=mwin
  if not alreadyActive then
    if type(mwin.frame.onFocusChange)=="function" then mwin.frame.onFocusChange(true) end
    if type(self.onFocusChange)=="function" then self.onFocusChange(mwin) end
  end
  self:renderRegions(regions)
end

---@param mwin ltwm.ManagedWindow
function ltwm.WindowManager:minimizeWindow(mwin)
  if not mwin or mwin.minimized then return end
  if type(mwin.frame.onFocusChange)=="function" then mwin.frame.onFocusChange(false) end
  mwin.minimized=true
  mwin.frame.hidden=true
  mwin.frame:disableAll()
  if self.activeWindow==mwin then self.activeWindow=nil end
  self:renderRegions({self:getWindowBounds(mwin)})
  event.push("ltde_taskbar_update")
end

---@param mwin ltwm.ManagedWindow
function ltwm.WindowManager:restoreWindow(mwin)
  if not mwin or not mwin.minimized then return end
  mwin.minimized=false
  mwin.frame.hidden=false
  mwin.frame:enableAll()
  self:bringToFront(mwin)
  event.push("ltde_taskbar_update")
end

---@param mwin ltwm.ManagedWindow
function ltwm.WindowManager:closeWindow(mwin)
  if not mwin then return end
  mwin.frame:disableAll()
  -- Finish queued button animation draws before repainting below the window.
  tgl.sys.renderer:flush(true)
  mwin.frame.hidden=true
  self:_removeFromLists(mwin)
  self:renderRegions({self:getWindowBounds(mwin)})
  if not mwin.noTaskbar then event.push("ltde_taskbar_update") end
  if mwin.pid then event.push("ltde_win_closed",mwin.pid) end
  if type(mwin.frame._onClose)=="function" then mwin.frame._onClose() end
end

---@param mwin ltwm.ManagedWindow
---@param pos2 tgl.Pos2
---@return boolean
function ltwm.WindowManager:moveWindow(mwin,pos2)
  if not mwin or not pos2 then return false end
  local oldBounds=self:getWindowBounds(mwin)
  mwin.frame:moveToPos2(pos2)
  self:renderRegions({oldBounds,self:getWindowBounds(mwin)})
  return true
end

---@param x integer
---@param y integer
---@return ltwm.ManagedWindow|nil
function ltwm.WindowManager:getWindowAt(x,y)
  for i=#self.windows,1,-1 do
    local mwin=self.windows[i]
    if not mwin.minimized and tgl.util.pointInSize2(x,y,mwin.frame.size2) then
      return mwin
    end
  end
  return nil
end

---@param frame tgl.Frame
---@return ltwm.ManagedWindow|nil
function ltwm.WindowManager:getManagedWindow(frame)
  for _,mwin in ipairs(self.windows) do
    if mwin.frame==frame then return mwin end
  end
  return nil
end

function ltwm.WindowManager:cleanup()
  for _,mwin in ipairs(self.windows) do
    mwin.frame:disableAll()
    mwin.frame.wm_managed=false
    if type(mwin.frame._onClose)=="function" then mwin.frame._onClose() end
  end
  self.windows={}
  self.pidWindows={}
  self.activeWindow=nil
  event.ignore("key_down",self.resetHandler)
  event.ignore("touch",self.focusHandler)
  for _,t in ipairs(self._dragThreads) do
    if t:status()~="dead" then t:kill() end
  end
  self._dragThreads={}
  if tgl.sys.wm==self then tgl.sys.wm=nil end
  tgl.util.log("LTWM cleanup done","LTWM")
end

return ltwm
