local event=require("event")
local unicode=require("unicode")
return function(tgl)
---Keyboard focus and input for one standalone UI, with nested modal roots.
tgl.Input={}
tgl.Input.__index=tgl.Input
local keyChars={[14]=8,[15]=9,[28]=13,[156]=13,[211]=127}

local function bounds(object)
  if object.size2 then return object.size2 end
  local pos=object.pos2
  if not pos then return nil end
  return {x1=pos.x,y1=pos.y,x2=pos.x+(object.width or unicode.wlen(object.defaultText or object.text or ""))-1,y2=pos.y}
end

local function visible(object)
  while object do
    if object.hidden or object.destroyed then return false end
    object=object._parentFrame
  end
  return true
end

local function intersect(a,b)
  local area={type="Size2",x1=math.max(a.x1,b.x1),y1=math.max(a.y1,b.y1),
    x2=math.min(a.x2,b.x2),y2=math.min(a.y2,b.y2)}
  if area.x1>area.x2 or area.y1>area.y2 then return nil end
  return area
end

function tgl.Input:new(root)
  checkArg(1,root,"table")
  if root.destroyed then return nil end
  local obj=setmetatable({},self)
  obj.type="Input"
  obj.root=root
  obj.events=tgl.Event:new()
  obj.enabled=false
  obj.destroyed=false
  obj.modals={}
  obj.members={}
  obj.owners={}
  return obj
end

---Visible bounds, shared by pointer hit tests and managed redraws.
function tgl.Input:clip(object,area)
  area=intersect(area,tgl.sys.activeArea)
  local owner=self.owners[object]
  if owner and area then area=intersect(area,owner.size2) end
  local parent=(owner or object)._parentFrame
  while parent and area do
    if parent.size2 then
      local s=parent.size2
      area=intersect(area,{x1=s.x1,y1=s.y1,
        x2=s.x2-(parent.type=="ScrollFrame" and parent._scrollbar and 1 or 0),y2=s.y2})
    end
    parent=parent._parentFrame
  end
  return area
end

---Redraw a control inside the visible bounds of its containers.
function tgl.Input:draw(object,callback,...)
  if not visible(object) then return end
  local r=tgl.sys.renderer
  local previous=r:getClipRegion()
  local clip=self:clip(object,tgl.sys.activeArea)
  if previous and clip then clip=intersect(clip,previous) end
  if not clip then return end
  r:setClipRegion(clip)
  local result=table.pack(pcall(callback,...))
  r:setClipRegion(previous)
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
end

---Bind current controls, including controls added since the previous event.
function tgl.Input:controls(pointer)
  local found,seen={},{}
  local function visit(object,path,visible,depth)
    if seen[object] or object.destroyed then return end
    seen[object]=true
    object.inputContext=self
    self.members[object]=true
    if object._scrollbar then
      seen[object._scrollbar]=true
      object._scrollbar.inputContext=self
      self.members[object._scrollbar]=true
      self.owners[object._scrollbar]=object
    end
    visible=visible and not object.hidden and (object.enabled~=false or object._clicking)
    local parent=object._parentFrame
    if parent and parent.type=="ScrollFrame" then
      local pos=object.relpos2 or object.relsize2
      if pos then
        local top=pos.y or pos.y1
        local height=pos.sizeY or 1
        visible=visible and top+height-1>parent.scroll and top<=parent.scroll+parent.size2.sizeY
      end
    end
    local area=bounds(object)
    local scrollArea=area and object.hitArea and self:clip(object,object.hitArea)
    if area then area=self:clip(object,area) end
    if (object.focusable or pointer and (object.pointerDown or object.pointerDrag or object.pointerScroll or object._scrollbar))
    and area and visible and (object.enabled or object._clicking) then
      found[#found+1]={object=object,area=area,scrollArea=scrollArea,path=path,depth=depth}
    end
    for key,child in pairs(object.objects or {}) do
      visit(child,path.."/"..tostring(key),visible,depth+1)
    end
  end
  visit(self.root,"",true,0)
  for i,previous in ipairs(self.modals) do visit(previous.root,"modal/"..i,false,0) end
  for object in pairs(self.members) do
    if not seen[object] and not (object._parentFrame and seen[object._parentFrame]) then
      if object.inputContext==self then object.inputContext=nil end
      self.members[object]=nil
      self.owners[object]=nil
    end
  end
  local order={}
  for i,object in ipairs(self.root.focusOrder or {}) do order[object]=i end
  table.sort(found,function(a,b)
    local ai,bi=order[a.object] or a.object.tabIndex or math.huge,order[b.object] or b.object.tabIndex or math.huge
    if ai~=bi then return ai<bi end
    if a.area.y1~=b.area.y1 then return a.area.y1<b.area.y1 end
    if a.area.x1~=b.area.x1 then return a.area.x1<b.area.x1 end
    return a.path<b.path
  end)
  return found
end

---Capture a gesture started by the current pointer-down callback.
function tgl.Input:capturePointer(object,screen,button,player)
  checkArg(1,object,"table")
  checkArg(2,screen,"string","nil")
  checkArg(3,button,"number","nil")
  checkArg(4,player,"string","nil")
  if not self.enabled or self.destroyed then return false end
  local pointer=self.pointerEvent
  screen=screen or (pointer and pointer.screen)
  button=button or (pointer and pointer.button)
  player=player or (pointer and pointer.player)
  if not screen or button==nil then return false end
  local gpu=tgl.sys.renderer.gpu
  local bound=self.screen or (gpu.getScreen and gpu.getScreen())
  if bound and screen~=bound then return false end
  if self.capture then
    local capture=self.capture
    return capture.object==object and capture.screen==screen and capture.button==button and capture.player==player
  end
  local owner=self.owners[object] or object
  local eligible=false
  for _,entry in ipairs(self:controls(true)) do
    if entry.object==owner then eligible=true break end
  end
  if not eligible or object.destroyed or object.hidden or object.enabled==false then return false end
  self.capture={object=object,owner=owner,root=self.root,screen=screen,button=button,player=player,
    x=pointer and pointer.x,y=pointer and pointer.y}
  return true
end

---Cancel capture. Normal pointer-up releases it without calling pointerCancel.
function tgl.Input:releasePointer(reason)
  checkArg(1,reason,"string","nil")
  local capture=self.capture
  if not capture then return false end
  self.capture=nil
  local object=capture.object
  if self.editing==object then
    if coroutine.status(self.editor)=="running" then self:stopEditing()
    else
      local redraw=self.redraw
      self.redraw=false
      local ok,err=pcall(self.feedEvent,self,"drop",capture.screen,capture.x,capture.y,capture.button,capture.player)
      self.redraw=redraw
      if not ok then tgl.util.log("Pointer cancel error: "..tostring(err),"Input") end
    end
  end
  if object.pointerCancel then
    local ok,err=pcall(object.pointerCancel,reason or "released",capture.screen,capture.button,capture.player)
    if not ok then tgl.util.log("Pointer cancel error: "..tostring(err),"Input") end
  end
  return true
end

---Cancel gestures belonging to an object or one of its children.
function tgl.Input:cancelPointer(object,reason)
  checkArg(1,object,"table")
  checkArg(2,reason,"string","nil")
  local capture=self.capture
  if not capture then return false end
  local owner=capture.owner
  if capture.object==object then return self:releasePointer(reason) end
  while owner do
    if owner==object then return self:releasePointer(reason) end
    owner=owner._parentFrame
  end
  return false
end

function tgl.Input:checkCapture()
  local capture=self.capture
  if not capture then return end
  local object=capture.object
  local gpu=tgl.sys.renderer.gpu
  local screen=self.screen or (gpu.getScreen and gpu.getScreen())
  if screen and capture.screen~=screen then self:releasePointer("screen") return end
  if not self.enabled or capture.root~=self.root or object.destroyed or object.hidden or object.enabled==false then
    self:releasePointer("unavailable")
    return
  end
  for _,entry in ipairs(self:controls(true)) do if entry.object==capture.owner then return end end
  self:releasePointer("unavailable")
end

function tgl.Input:callPointer(object,hook,...)
  if not object[hook] then return false end
  local result=table.pack(pcall(self.draw,self,object,object[hook],...))
  if not result[1] then
    self:cancelPointer(object,"error")
    tgl.util.log("Pointer handler error: "..tostring(result[2]),"Input")
    return false
  end
  return true,table.unpack(result,2,result.n)
end

---Forward only events accepted by the current editor's input wait.
function tgl.Input:feedEvent(name,...)
  for _,filter in ipairs(self.filters or {}) do
    if filter==name then return self:feed(name,...) end
  end
  return false
end

function tgl.Input:feed(...)
  if not self.editor or coroutine.status(self.editor)~="suspended" then return false end
  local editor=self.editor
  local object=self.editing
  local result=table.pack(coroutine.resume(editor,...))
  if not result[1] or coroutine.status(editor)=="dead" then
    if self.editor==editor then self.editor=nil self.editing=nil self.filters=nil end
    object._leaveInput=nil
    if not object.destroyed and object.eventName then event.push(object.eventName,object.text) end
    if not result[1] then error(result[2],0) end
  elseif self.editor==editor then
    self.filters={table.unpack(result,2,result.n)}
  end
  return true
end

function tgl.Input:stopEditing()
  if not self.editing then return end
  self.editing._leaveInput=true
  if coroutine.status(self.editor)=="running" then
    self.editor=nil self.editing=nil self.filters=nil
  else self:feed(self.editing.destroyEventName) end
end

function tgl.Input:startEditing(object,x,y)
  if self.editing==object then return end
  self:stopEditing()
  self.editing=object
  self.editor=coroutine.create(function()
    if object.type=="Scrollbar" then object.pointerDown("touch",nil,x,y)
    else object:input(x,y) end
  end)
  self:feed()
end

---Set focus to a control, or nil. Returns false if it is not eligible.
function tgl.Input:focus(object,redraw,x,y)
  checkArg(1,object,"table","nil")
  checkArg(2,redraw,"boolean","nil")
  checkArg(3,x,"number","nil")
  checkArg(4,y,"number","nil")
  if self.destroyed or not self.enabled then return false end
  if object then
    local eligible=false
    for _,entry in ipairs(self:controls()) do if entry.object==object then eligible=true break end end
    if not eligible then return false end
  end
  if self.focused==object then return true end
  self:releasePointer("focus")
  local old=self.focused
  self.focused=nil
  if old then old.focused=false end
  self.redraw=false
  self:stopEditing()
  self.redraw=nil
  if old and old.opened and old.hideOptions then
    old.opened=false
    if redraw==false and old.ss then old.ss:destroy() old.ss=nil
    else old:hideOptions() end
  end
  if redraw~=false and old and visible(old) then self:draw(old,old.render,old) end
  self.focused=object
  if object then
    object.focused=true
    if object.type=="InputField" or object.type=="InputBox" then self:startEditing(object,x,y)
    elseif redraw~=false then self:draw(object,object.render,object) end
  end
  if redraw~=false then tgl.sys.renderer:flush() end
  return true
end

---Detach a subtree without destroying it, for frame:remove().
function tgl.Input:release(object)
  self:cancelPointer(object,"detached")
  local child=self.focused
  while child do
    if child==object then self:focus(nil,false) break end
    child=child._parentFrame
  end
  local function detach(child)
    if child.inputContext==self then child.inputContext=nil end
    self.members[child]=nil
    self.owners[child]=nil
    for _,nested in pairs(child.objects or {}) do detach(nested) end
    if child._scrollbar then detach(child._scrollbar) end
  end
  detach(object)
end

function tgl.Input:next(reverse)
  checkArg(1,reverse,"boolean","nil")
  local controls=self:controls()
  if #controls==0 then self:focus(nil) return false end
  local index=reverse and 1 or 0
  for i,entry in ipairs(controls) do if entry.object==self.focused then index=i break end end
  index=(index+(reverse and -1 or 1)-1)%#controls+1
  return self:focus(controls[index].object)
end

---Start listening, or pass false to forward events through handle() yourself.
function tgl.Input:start(listen)
  checkArg(1,listen,"boolean","nil")
  if self.destroyed or self.root.destroyed then return false end
  if tgl.sys.input and tgl.sys.input~=self then return false end
  if self.enabled then return true end
  self.enabled=true
  tgl.sys.input=self
  self:controls()
  if listen~=false then
    for _,name in ipairs({"key_down","touch","scroll","drag","drop","clipboard"}) do
      self.events:listen(name,function(...)self:handle(...)end)
    end
  end
  self:next()
  return true
end

function tgl.Input:stop()
  self:releasePointer("stopped")
  self:focus(nil)
  self.enabled=false
  self.events:clear()
  for object in pairs(self.members) do
    if object.inputContext==self then object.inputContext=nil end
  end
  self.members={}
  self.owners={}
  if tgl.sys.input==self then tgl.sys.input=nil end
end

function tgl.Input:destroy()
  if self.destroyed then return false end
  self:stop()
  self.events:destroy()
  self.modals={}
  self.destroyed=true
  return true
end

---The caller opens/closes the dialog; this only changes its input scope.
function tgl.Input:pushModal(root)
  checkArg(1,root,"table","nil")
  if self.destroyed or not self.enabled or not root or root.destroyed then return false end
  local previous={root=self.root,focused=self.focused}
  self:releasePointer("modal")
  self:focus(nil,false)
  self.modals[#self.modals+1]=previous
  self.root=root
  self:next()
  return true
end

function tgl.Input:popModal()
  local previous=table.remove(self.modals)
  if not previous then return false end
  self:releasePointer("modal")
  self:focus(nil,false)
  self.root=previous.root
  if not self:focus(previous.focused) then self:next() end
  return true
end

local function contains(area,x,y)
  return area and x>=area.x1 and x<=area.x2 and y>=area.y1 and y<=area.y2
end

function tgl.Input:press(target,screen,x,y,button,player)
  if target._clicking then return end
  local bar=target._scrollbar
  local onBar=bar and contains(bar.size2,x,y)
  local editing=self.editing==target
  if editing then self:feedEvent("touch",screen,x,y,button,player)
  else self:focus(target,nil,x,y) end
  if target.type=="Scrollbar" then
    self:startEditing(target,x,y)
    if target._dragActive then self:capturePointer(target,screen,button,player) end
  elseif onBar and target.type=="InputBox" then
    if not editing then self:feedEvent("touch",screen,x,y,button,player) end
    self:capturePointer(target,screen,button,player)
  elseif onBar then
    self:startEditing(bar,x,y)
    if bar._dragActive then self:capturePointer(bar,screen,button,player) end
  elseif target.type~="InputField" and target.type~="InputBox" then
    self:callPointer(target,"pointerDown","touch",screen,x,y,button,player)
  end
end

function tgl.Input:handlePointer(name,screen,x,y,button,player,controls)
  if type(x)~="number" or type(y)~="number" then return false end
  if name=="drag" or name=="drop" then
    local capture=self.capture
    if not capture or capture.screen~=screen or capture.button~=button
    or capture.player~=player then return false end
    capture.x=x capture.y=y
    if name=="drop" then self.capture=nil end
    if self.editing==capture.object then self:feedEvent(name,screen,x,y,button,player)
    else self:callPointer(capture.object,name=="drag" and "pointerDrag" or "pointerDrop",name,screen,x,y,button,player) end
    tgl.sys.renderer:flush()
    return true
  end
  local gpu=tgl.sys.renderer.gpu
  local bound=self.screen or (gpu.getScreen and gpu.getScreen())
  if bound and screen~=bound then return false end
  if self.capture then return true end
  if not contains(tgl.sys.activeArea,x,y) then return #self.modals>0 end
  local object=self.focused
  if name=="touch" and object and object.opened and object.pointerDown then
    local s=bounds(object)
    local popup=self:clip(object,{x1=s.x1,y1=s.y1,x2=s.x2,y2=s.y1+#(object.options or {})})
    if contains(popup,x,y) then
      self:callPointer(object,"pointerDown",name,screen,x,y,button,player)
      tgl.sys.renderer:flush()
      return true
    elseif object.closeOnDefocus then
      object.opened=false
      object:hideOptions()
      self:draw(object,object.render,object)
      tgl.sys.renderer:flush()
    end
  end
  local target,depth=nil,-1
  for _,entry in ipairs(controls) do
    local area=name=="scroll" and entry.scrollArea or entry.area
    if contains(area,x,y) and (not target or (entry.object.z_index or 0)>(target.z_index or 0)
    or (entry.object.z_index or 0)==(target.z_index or 0) and entry.depth>=depth) then
      target=entry.object depth=entry.depth
    end
  end
  if not target then return #self.modals>0 end
  local z=(target.z_index or 0)+(self.editing==target and 1 or 0)
  if tgl.sys.renderer:getZ(x,y)>z then return #self.modals>0 end
  if name=="scroll" then
    local owner=target
    while owner do
      local scroll=owner.pointerScroll and owner or owner._scrollbar
      if scroll and scroll.pointerScroll then
        local ok,handled=self:callPointer(scroll,"pointerScroll",name,screen,x,y,button,player)
        if not ok or handled~=false then tgl.sys.renderer:flush() return true end
      end
      if owner==self.root then break end
      owner=owner._parentFrame
    end
    return #self.modals>0
  end
  local previous=self.pointerEvent
  self.pointerEvent={screen=screen,x=x,y=y,button=button,player=player}
  local ok,err=pcall(self.press,self,target,screen,x,y,button,player)
  self.pointerEvent=previous
  if not ok then
    self:releasePointer("error")
    tgl.util.log("Pointer handler error: "..tostring(err),"Input")
  end
  tgl.sys.renderer:flush()
  return true
end

function tgl.Input:handle(name,address,a,b,c,player)
  checkArg(1,name,"string")
  if not self.enabled or self.destroyed then return false end
  self:checkCapture()
  if self.root.destroyed then
    if #self.modals>0 then self:popModal() else self:destroy() end
    return true
  end
  if name=="key_down" and self.editing==self.focused and self.editing
  and self.editing.enabled and visible(self.editing) and a~=9 and b~=15 then
    if a==27 or b==1 then return false end
    if a==0 then a=keyChars[b] or a end
    return self:feedEvent(name,address,a,b,c,player)
  end
  local controls=self:controls(name=="touch" or name=="scroll")
  local eligible=false
  for _,entry in ipairs(controls) do
    if entry.object==self.focused and entry.object.focusable then eligible=true break end
  end
  if self.focused and not eligible then self:focus(nil) end
  if name=="key_down" then
    if a==0 then a=keyChars[b] or a end
    local keyboard=require("keyboard")
    local shift,ctrl=keyboard.isShiftDown(),keyboard.isControlDown()
    if a==27 or b==1 then return false end
    if a==9 or b==15 then
      if self.focused and self.focused.type=="InputBox" and self.focused.acceptTab~=false and not ctrl then
        if self.editing then self:feedEvent(name,address,a,b,c,player) end
        return true
      end
      return self:next(shift)
    end
    if self.editing then return self:feedEvent(name,address,a,b,c,player) end
    local object=self.focused
    if not object then return false end
    if object.type=="InputField" or object.type=="InputBox" then
      self:startEditing(object)
      if a~=13 then self:feed(name,address,a,b,c,player) end
      return true
    end
    if object.keyDown and object:keyDown(a,b,shift,ctrl) then tgl.sys.renderer:flush() return true end
    if (a==13 or a==32 or b==28 or b==156 or b==57) and not ctrl then
      if object._clicking then return true end
      if object.activate then object:activate()
      elseif object.pointerDown then
        local s=bounds(object)
        object.pointerDown("touch",nil,s.x1,s.y1,0)
      end
      tgl.sys.renderer:flush()
      return true
    end
    local parent=object._parentFrame
    if parent and ((parent.navigation=="horizontal" and (b==203 or b==205))
    or (parent.navigation=="vertical" and (b==200 or b==208))) then
      local group={}
      for _,entry in ipairs(controls) do if entry.object._parentFrame==parent then group[#group+1]=entry.object end end
      for i,child in ipairs(group) do
        if child==object then
          local step=(b==203 or b==200) and -1 or 1
          return self:focus(group[(i-1+step)%#group+1])
        end
      end
    end
  elseif name=="touch" or name=="scroll" or name=="drag" or name=="drop" then
    return self:handlePointer(name,address,a,b,c,player,controls)
  elseif self.editing then
    return self:feedEvent(name,address,a,b,c,player)
  end
  return false
end

return tgl end
