local event=require("event")
return function(tgl)
---Owned OpenOS listeners and timers. This does not create a separate event queue.
---@class tgl.Event
tgl.Event={}
tgl.Event.__index=tgl.Event

---@param parent? tgl.Event defaults to the library scope
---@return tgl.Event
function tgl.Event:new(parent)
  checkArg(1,parent,"table","nil")
  parent=parent or tgl.sys.events
  if parent and parent.destroyed then error("Event scope is destroyed",2) end
  local obj=setmetatable({},self)
  obj.type="Event"
  obj.listeners={}
  obj.timers={}
  obj.children=setmetatable({},{__mode="k"})
  obj.parent=parent
  obj.destroyed=false
  if parent then parent.children[obj]=true end
  return obj
end

function tgl.Event:listen(name,callback)
  checkArg(1,name,"string")
  checkArg(2,callback,"function")
  if self.destroyed then return false end
  local listeners=self.listeners[name]
  if not listeners then listeners={} self.listeners[name]=listeners end
  if listeners[callback] then return false end
  local handler
  handler=function(...)
    if self.destroyed or listeners[callback]~=handler then return false end
    local ok,result=pcall(callback,...)
    if (not ok or result==false) and listeners[callback]==handler then
      self:ignore(name,callback)
    end
    if not ok then error(result,0) end
    return result
  end
  local registered=event.listen(name,handler)
  if registered==false then return false end
  listeners[callback]=handler
  return true
end

function tgl.Event:ignore(name,callback)
  checkArg(1,name,"string")
  checkArg(2,callback,"function")
  local listeners=self.listeners[name]
  local handler=listeners and listeners[callback]
  if not handler then return false end
  listeners[callback]=nil
  if not next(listeners) then self.listeners[name]=nil end
  event.ignore(name,handler)
  return true
end

function tgl.Event:timer(interval,callback,times)
  checkArg(1,interval,"number")
  checkArg(2,callback,"function")
  checkArg(3,times,"number","nil")
  times=times or 1
  if interval~=interval or interval<0 or interval==math.huge then error("Invalid timer interval",2) end
  if times~=times or times<1 or times%1~=0 and times~=math.huge then error("Invalid timer count",2) end
  if self.destroyed then return false end
  local id
  id=event.timer(interval,function(...)
    if self.destroyed or not self.timers[id] then return false end
    local ok,result=pcall(callback,...)
    times=times-1
    if not ok or result==false or times==0 then self:cancel(id) end
    if not ok then error(result,0) end
    return result
  end,times)
  if not id then return false end
  self.timers[id]=true
  return id
end

function tgl.Event:cancel(id)
  checkArg(1,id,"number")
  if not self.timers[id] then return false end
  self.timers[id]=nil
  event.cancel(id)
  return true
end

---Remove registrations, including child scopes. The scopes remain reusable.
function tgl.Event:clear()
  for child in pairs(self.children) do child:clear() end
  for name,listeners in pairs(self.listeners) do
    for callback in pairs(listeners) do self:ignore(name,callback) end
  end
  for id in pairs(self.timers) do self:cancel(id) end
end

---Permanently close this scope and its children.
function tgl.Event:destroy()
  if self.destroyed then return false end
  self.destroyed=true
  for child in pairs(self.children) do child:destroy() end
  self:clear()
  if self.parent then self.parent.children[self]=nil self.parent=nil end
  return true
end

tgl.sys.events=tgl.Event:new()
return tgl end
