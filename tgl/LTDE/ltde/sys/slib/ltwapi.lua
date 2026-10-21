local event=require("event")
local unicode=require("unicode")
local tgl=require("tgl")
local ltwapi={}

local function wm() return tgl.sys.wm end

---Show a popup menu anchored just below anchorPos2.
---Blocks until selection or outside click. Fires item.eventName if set.
---items: {{label=string, eventName=string?, value=any?}, ...}
---@param z? integer z-index for the menu; defaults to max window z+1
---@return table|nil chosen item
function ltwapi.showMenu(anchorPos2,items,col2,z)
  if not anchorPos2 or not items or #items==0 then return nil end
  if not z then
    z=200
    if tgl.sys.wm then
      local maxZ=0
      for _,m in ipairs(tgl.sys.wm.windows or {}) do
        if m.frame.z_index>maxZ then maxZ=m.frame.z_index end
      end
      z=maxZ+1
    end
  end
  local r=tgl.sys.renderer
  local width=0
  for _,item in ipairs(items) do
    local w=unicode.wlen(item.label)+2
    if w>width then width=w end
  end
  -- +2 on each axis for inline border
  local frameSize=tgl.Size2:newFromSize(anchorPos2.x,anchorPos2.y+1,width+2,#items+2)
  local ss=tgl.ScreenSave:new(frameSize)

  local result=nil
  local frameObjs={}
  for i,item in ipairs(items) do
    frameObjs["item"..i]=tgl.Button:new(" "..item.label,function()
      result=item
      event.push("ltde_menu_done")
    end,tgl.Pos2:new(2,i+1),col2)
    frameObjs["item"..i].onClick=nil
  end
  local frame=tgl.Frame:new(frameObjs,frameSize,col2)
  frame.z_index=z
  frame.borders="─│┌┐└┘"

  r:stop()
  frame:render()
  r:flush()
  frame:enableAll()

  local outsideHandler=function(_,_,x,y)
    if not tgl.util.pointInSize2(x,y,frameSize) then
      event.push("ltde_menu_done")
    end
  end
  local prevAA=tgl.sys.getActiveArea()
  tgl.sys.setActiveArea(frameSize)
  event.listen("touch",outsideHandler)
  local _ok,_err=pcall(event.pull,"ltde_menu_done")
  event.ignore("touch",outsideHandler)
  tgl.sys.setActiveArea(prevAA)
  frame:disableAll()
  ss:render()
  --Restore the popup area before its action can resize or close the window.
  r:flush()
  if not _ok then error(_err,0) end
  if result and result.eventName then
    event.push(result.eventName,result.value)
  end
  return result
end

---Create a titled window and register it with ltwm.
---ltwm decides screen position via cascade.
---
---opts.toolbar=true adds a toolbar row
---opts.menuItems={{label, items={{label,eventName,value},...}},...} populates it
---opts.onClose: function called when window is closed via title bar X button
---
---@param sizeX integer
---@param sizeY integer
---@param title string
---@param opts? table
---@return tgl.Frame|nil
---@return tgl.Size2|nil content area (frame-relative coords)
function ltwapi.addWindow(sizeX,sizeY,title,opts)
  local wmgr=wm()
  if not wmgr then return nil,nil end
  if not title then title="Untitled" end
  local activeBarCol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
  local inactiveBarCol=tgl.Color2:new(tgl.defaults.colors16.lightgray,tgl.defaults.colors16.darkgray)
  local frameCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
  local toolbarCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)

  --buttons use nil callback, set after frame is created (closure over frame)
  local closeBtn=tgl.Button:new(" X ",nil,tgl.Pos2:new(sizeX-2,1),tgl.defaults.colors2.close)
  closeBtn.onClick=nil

  local minBtn=tgl.Button:new(" - ",nil,tgl.Pos2:new(sizeX-6,1),inactiveBarCol)
  minBtn.onClick=nil

  -- local titleTxt=tgl.Text:new(title,inactiveBarCol,
  --   tgl.Pos2:new(math.floor((sizeX-unicode.wlen(title))/2),1))
  local titleTxt=tgl.Text:new(title,inactiveBarCol,tgl.Pos2:new(2,1))
  local titleBar=tgl.Frame:new({title=titleTxt,min=minBtn,close=closeBtn},
    tgl.Size2:newFromSize(1,1,sizeX,1),inactiveBarCol)
  titleBar.ignoreOpen=true

  local contentY=2
  local objects={titlebar=titleBar}

  if opts and opts.toolbar then
    local tbObjs={}
    local tbMenus={}
    local tbX=1
    local popupCol=tgl.Color2:new(0,0xE1E1E1)
    for _,mi in ipairs(opts.menuItems or {}) do
      local lbl=mi.label
      local btn=tgl.Button:new(lbl,nil,tgl.Pos2:new(tbX,1),toolbarCol)
      btn.menuItems=mi.items or {}
      btn.callback=function()
        ltwapi.showMenu(btn.pos2,btn.menuItems,popupCol,btn.z_index+1)
      end
      table.insert(tbObjs,btn)
      tbMenus[lbl]=btn
      tbX=tbX+unicode.wlen(lbl)+1
    end
    local tbFrame=tgl.Frame:new(tbObjs,tgl.Size2:newFromSize(1,2,sizeX,1),toolbarCol)
    tbFrame.ignoreOpen=true
    tbFrame.menus=tbMenus
    objects.toolbar=tbFrame
    contentY=3
  end

  local frame=tgl.Frame:new(objects,tgl.Size2:newFromSize(1,1,sizeX,sizeY),frameCol)
  local contentSize2=tgl.Size2:newFromSize(1,contentY,sizeX,sizeY-contentY+1)
  frame.wmTitle=title

  frame.onFocusChange=function(active)
    local col=active and activeBarCol or inactiveBarCol
    titleBar.col2=col
    titleTxt.col2=col
    minBtn.col2=col
  end

  frame._onClose=opts and type(opts.onClose)=="function" and opts.onClose or nil

  closeBtn.callback=function()
    ltwapi.removeWindow(frame)  -- fires frame._onClose via wmgr:closeWindow
  end
  minBtn.callback=function()
    ltwapi.minimize(frame)
  end

  local pid=_G._ltde_co_pid and _G._ltde_co_pid[coroutine.running()]
  wmgr:addWindow(frame,pid,false)
  frame:enableAll()
  return frame,contentSize2
end

---Re-render all windows and flush to screen immediately.
function ltwapi.refresh()
  local wmgr=wm()
  if wmgr then wmgr:renderAll() end
end

---@param frame tgl.Frame
function ltwapi.removeWindow(frame)
  local wmgr=wm()
  if not wmgr then return end
  local mwin=wmgr:getManagedWindow(frame)
  if mwin then wmgr:closeWindow(mwin) end
end

---@param frame tgl.Frame
---@param title string
function ltwapi.setTitle(frame,title)
  if not frame then return end
  local tb=frame.objects and frame.objects.titlebar
  if tb and tb.objects and tb.objects.title then
    tb.objects.title:updateText(title)
  end
end

---@param frame tgl.Frame
function ltwapi.minimize(frame)
  local wmgr=wm()
  if not wmgr then return end
  local mwin=wmgr:getManagedWindow(frame)
  if mwin then wmgr:minimizeWindow(mwin) end
end

---Bring window to front and mark it as the active window.
---Call this after frame:open() to give a newly opened window focus.
---@param frame tgl.Frame
function ltwapi.focus(frame)
  local wmgr=wm()
  if not wmgr then return end
  local mwin=wmgr:getManagedWindow(frame)
  if mwin then wmgr:bringToFront(mwin) end
end

---@param frame tgl.Frame
---@param enabled boolean
function ltwapi.setToolbarEnabled(frame,enabled)
  if not frame then return end
  local tb=frame.objects and frame.objects.toolbar
  if not tb then return end
  if enabled then tb:enableAll() else tb:disableAll() end
end

---Replace the dropdown items for a named toolbar menu.
---Takes effect immediately on the next open of that dropdown.
---@param frame tgl.Frame
---@param menuLabel string top-level button label e.g. "File"
---@param items table[] {{label,eventName,value?},...}
function ltwapi.setMenuItems(frame,menuLabel,items)
  local tb=frame.objects and frame.objects.toolbar
  if not tb or not tb.menus then return end
  local btn=tb.menus[menuLabel]
  if btn then btn.menuItems=items end
end

---Get the live menuItems table for a named toolbar menu (mutate in place).
---@param frame tgl.Frame
---@param menuLabel string
---@return table[]|nil
function ltwapi.getMenuItems(frame,menuLabel)
  local tb=frame.objects and frame.objects.toolbar
  if not tb or not tb.menus then return nil end
  local btn=tb.menus[menuLabel]
  return btn and btn.menuItems or nil
end

---Open a file with its registered application. Returns program or nil,error.
function ltwapi.openFile(path)
  local fs=require("filesystem")
  if type(path)~="string" or not fs.exists(path) then return nil,"File not found." end
  if fs.isDirectory(path) then return nil,"Expected a file." end
  path=fs.canonical(path)
  local ext=(fs.name(path):match("%.([^%.]+)$") or ""):lower()
  local associations=_G._ltde_associations or {}
  local app=associations[ext] or associations["*"]
  if type(app)~="string" or not fs.isDirectory(app) then return nil,"No valid application for this file." end
  if not _G.ltde_launch then return nil,"Launch service unavailable." end
  return _G.ltde_launch(app,nil,{path})
end

return ltwapi
