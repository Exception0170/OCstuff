local unicode=require("unicode")
local thread=require("thread")
local event=require("event")
return function(tgl)
local function canOwn(parent,object)
  if type(object)~="table" or not object.type or object.destroyed then return false end
  if object._parentFrame and object._parentFrame~=parent then return false end
  local ancestor=parent
  while ancestor do
    if ancestor==object then return false end
    ancestor=ancestor._parentFrame
  end
  return true
end

---Base for TGL UI objects
---@class tgl.UIObject
---@field type string
---@field z_index integer
---@field hidden boolean if object is hidden
---@field destroyed boolean|nil if object was permanently disposed
---@field events tgl.Event|nil owned listeners and timers
---@field new function(self,...):UIObject Constructor
---@field render function Render function
tgl.UIObject={}
tgl.UIObject.__index=tgl.UIObject

---Apply container bounds to direct redraws too, without requiring an input context.
function tgl.sys.drawObject(object,draw,...)
  if object.destroyed or object.hidden then return false end
  local clip={type="Size2",x1=1,y1=1,x2=tgl.defaults.screenSizeX,y2=tgl.defaults.screenSizeY}
  local function limit(size2,scrollbar)
    clip.x1=math.max(clip.x1,size2.x1) clip.y1=math.max(clip.y1,size2.y1)
    clip.x2=math.min(clip.x2,size2.x2-(scrollbar and 1 or 0)) clip.y2=math.min(clip.y2,size2.y2)
  end
  local owner=object.owner
  if owner then
    if owner.hidden or owner.destroyed then return false end
    limit(owner.size2)
  end
  local child=owner or object
  local parent=child._parentFrame
  while parent do
    if parent.hidden or parent.destroyed then return false end
    if parent.type=="ScrollFrame" then
      local pos=child.relpos2 or child.relsize2
      if pos then
        local top=pos.y or pos.y1
        if top+(pos.sizeY or 1)-1<=parent.scroll or top>parent.scroll+parent.size2.sizeY then return false end
      end
    end
    if parent.size2 then limit(parent.size2,parent.type=="ScrollFrame" and parent._scrollbar) end
    child=parent parent=parent._parentFrame
  end
  if not owner and not object._parentFrame then return draw(...) end
  return tgl.sys.renderer:withClip(clip,draw,...)
end

---Wrap a built-in draw method once; custom child renderers are scoped by Frame.
function tgl.sys.wrapRender(class)
  local render=class.render
  class.render=function(self,...)return tgl.sys.drawObject(self,render,self,...)end
end

---Managed editors yield input to their context; legacy editors still pull it.
function tgl.UIObject:pullInput(...)
  if self._leaveInput or self.destroyed then return self.destroyEventName end
  local context=self.inputContext
  if context and context.editing==self and coroutine.running()==context.editor then
    return coroutine.yield(...)
  end
  return event.pullMultiple(...)
end

---Keep native mouse listeners from also handling a context's input.
function tgl.sys.wrapInput(object,handler)
  return function(...)
    if object.inputContext and object.inputContext.enabled then return end
    return handler(...)
  end
end

function tgl.sys.clipInput(object,draw)
  return function(...)
    local context=object.inputContext
    if context and context.enabled then
      if context.redraw==false then return end
      return context:draw(object,draw,...)
    end
    return tgl.sys.drawObject(object,draw,...)
  end
end

---Permanently release this object and its owned children. Does not restore pixels.
---@return boolean
function tgl.UIObject:destroy()
  if self.destroyed then return false end
  self.destroyed=true
  self.hidden=true
  local context=self.inputContext
  if context then
    context:cancelPointer(self,"destroyed")
    if context.focused==self then context:focus(nil,false) end
    if context.root==self and #context.modals==0 then context:destroy() end
    context.members[self]=nil
    context.owners[self]=nil
    self.inputContext=nil
  end
  if self.destroyEventName and (self._inputActive or self._dragActive) then
    event.push(self.destroyEventName)
  end
  if self.disable then self:disable() end
  self.enabled=false
  self._clicking=nil
  if self.events then self.events:destroy() end
  if self.objects then
    for _,object in pairs(self.objects) do
      if object.destroy then object:destroy()
      else tgl.UIObject.destroy(object) end
    end
    self.objects={}
  end
  if self._scrollbar then self._scrollbar:destroy() self._scrollbar=nil end
  if self.ss then self.ss:destroy() self.ss=nil end
  if self.unload then self:unload() end
  self.owner=nil
  local parent=self._parentFrame
  if parent then
    for name,object in pairs(parent.objects) do
      if object==self then
        if parent.remove then parent:remove(name) else parent.objects[name]=nil end
      end
    end
    self._parentFrame=nil
  end
  return true
end

---Base for all single-line objects
---@class tgl.LineObject:tgl.UIObject
---@field pos2 tgl.Pos2
---@field col2 tgl.Color2
tgl.LineObject=setmetatable({},{__index=tgl.UIObject})
tgl.LineObject.__index=tgl.LineObject

---Base for all single-line interactable objects
---@class tgl.LineObjectInteractable:tgl.LineObject
---@field enabled boolean If object is active
---@field enable function Enable object
---@field disable function Disable object
---@field checkRendered boolean Check if object is actually rendered(default=true)
tgl.LineObjectInteractable=setmetatable({},{__index=tgl.LineObject})
tgl.LineObjectInteractable.__index=tgl.LineObjectInteractable

---Base BoxObject
---@class tgl.BoxObject:tgl.UIObject
---@field size2 tgl.Size2
---@field col2 tgl.Color2
tgl.BoxObject=setmetatable({},{__index=tgl.UIObject})
tgl.BoxObject.__index=tgl.BoxObject
---@param pos2 tgl.Pos2
---@return boolean
function tgl.BoxObject:moveToPos2(pos2)
  checkArg(1,pos2,"table","nil")
  if not pos2 then return false end
  return self.size2:moveToPos2(pos2)
end


---Single line text object
---@class tgl.Text:tgl.LineObject
---@field text string
---@field maxLength integer Max text length, -1 for unlimited
---@field vertical boolean Render text vertically
tgl.Text=setmetatable({},{__index=tgl.LineObject})
tgl.Text.__index=tgl.Text
---@param text string
---@param col2? tgl.Color2
---@param pos2? tgl.Pos2
---@return tgl.Text
function tgl.Text:new(text,col2,pos2)
  checkArg(1,text,"string")
  checkArg(2,col2,"table","nil")
  checkArg(3,pos2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="Text"
  obj.z_index=0
  obj.text=text
  obj.col2=col2 or tgl.sys.themeColor("text")
  obj.pos2=pos2 or nil --Intended: pos2 can be nil, text will displayed on current cursor pos
  obj.maxLength=-1
  obj.vertical=false
  return obj
end

---@param nextLine? boolean change to next line after rendering
function tgl.Text:render(nextLine)
  checkArg(1,nextLine,"boolean","nil")
  local r=tgl.sys.renderer
  local function draw(pos2,text)
    if self.gradient then
      local area=self.gradientArea
      if not area and self._parentFrame and self._parentFrame.gradient==self.gradient then area=self._parentFrame.size2 end
      return r:gradientText(pos2,text,self.gradient,area,self.col2,self.z_index,self.vertical)
    end
    return r:set(pos2,text,self.col2,self.z_index,self.vertical)
  end
  if self.maxLength>=0 then
    if unicode.wlen(self.text)>self.maxLength then
      if self.maxLength>4 then
        self.text=unicode.sub(self.text,1,self.maxLength-2)..".."
      else
        self.text=unicode.sub(self.text,1,self.maxLength)
      end
    end
  end
  if self.destroyed or self.hidden then return end
  if not self.pos2 then
    local text=self.text
    if nextLine then text=text.."\n" end
    draw(tgl.getCurrentPos2(),text)
    return
  end
  if self.maxLength>4 then
    draw(self.pos2,string.rep(" ",self.maxLength))
  end
  draw(self.pos2,self.text)
  return
end
---Clear text field and render new text
function tgl.Text:updateText(text)
  if self.destroyed then return false end
  text=tostring(text)
  if self.text==text then return false end
  local old=self.text
  self.text=tostring(text)
  tgl.sys.drawObject(self,function()
    if self.pos2 and unicode.wlen(text)<unicode.wlen(old) then
      local width=self.vertical and 1 or unicode.wlen(old)
      local height=self.vertical and unicode.len(old) or 1
      local area=tgl.Size2:new(self.pos2.x,self.pos2.y,width,height)
      local r=tgl.sys.renderer
      if self.gradient then
        local bounds=self.gradientArea or (self._parentFrame and self._parentFrame.gradient==self.gradient and self._parentFrame.size2) or area
        r:withClip(area,r.gradient,r,bounds,self.gradient,self.col2,self.z_index)
      else r:fill(area," ",self.col2,self.z_index) end
    end
    self:render()
  end)
  return true
end

---A special object to store multiple Text objects and render at same time
---@class tgl.MultiText:tgl.UIObject
---@field objects tgl.Text[]
---@field pos2 tgl.Pos2
tgl.MultiText=setmetatable({},{__index=tgl.UIObject})
tgl.MultiText.__index=tgl.MultiText
---@param objects tgl.Text[]
---@param pos2? tgl.Pos2
---@return tgl.MultiText|tgl.UIObject
function tgl.MultiText:new(objects,pos2)
  checkArg(1,objects,"table")
  checkArg(2,pos2,"table","nil")
  if type(objects)=="table" then
    local obj=setmetatable({},self)
    obj.type="MultiText"
    obj.z_index=0
    obj.objects={}
    for _,object in pairs(objects) do
      if type(object)=="table" and object.type=="Text" and not canOwn(obj,object) then return nil end
    end
    for k,object in pairs(objects) do
      if type(object)=="table" then
        if object.type=="Text" then
          object._parentFrame=obj
          if not tonumber(k) then obj.objects[k]=object
          else table.insert(obj.objects,object) end
        end
      end
    end
    obj.pos2=pos2 or tgl.Pos2:new()
    return obj
  end
end
function tgl.MultiText:render()
  if self.destroyed or self.hidden then return end
  local startX=self.pos2.x
  for _,object in pairs(self.objects) do
    if object.pos2 then object:render()
    else
      object.pos2=tgl.Pos2:new(startX,self.pos2.y)
      startX=startX+unicode.wlen(object.text)
      object:render()
    end
  end
end

---Single-line text button, runs callback function
---@class tgl.Button:tgl.LineObjectInteractable
---@field callback function Function to run on click
---@field text string
---@field handler function Button handler, main button logic(is set by default)
---@field onClick function handles graphic like color change on press
tgl.Button=setmetatable({},{__index=tgl.LineObjectInteractable})
tgl.Button.__index=tgl.Button
---@param text string
---@param callback function
---@param pos2? tgl.Pos2
---@param color2? tgl.Color2
---@return tgl.Button
function tgl.Button:new(text,callback,pos2,color2)
  checkArg(1,text,"string","nil")
  checkArg(2,callback,"function","nil")
  checkArg(3,pos2,"table","nil")
  checkArg(4,color2,"table","nil")
  ---@type tgl.Button
  local obj=setmetatable({},self)
  obj.type="Button"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.events=tgl.Event:new()
  obj.z_index=0
  obj.text=text or "[New Button]"
  if not callback then
  	callback=function() tgl.util.log("Empty Button!","Button/callback") end
  end
  obj.enabled=false
  obj.callback=callback
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.col2=color2 or tgl.sys.themeColor("button")
  obj.checkRendered=true -- check if button is on screen
  obj.handler=function (_,_,x,y,b)
    if obj.destroyed then return end
    if x>=obj.pos2.x
    and x<obj.pos2.x+unicode.wlen(obj.text)
    and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.text=="" then return end
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
      end
      if type(obj.onClick)=="function" then
        thread.create(obj.onClick):detach()
      end
      local success,err=pcall(obj.callback,b)
      if not success then
        tgl.util.log("Button handler error: "..err,"Button/handler")
      end
    end
  end
  obj.onClick=function()
    if obj.destroyed or obj.hidden or not obj.enabled then return end
    obj:disable()
    obj._clicking=true
    local prev=obj.col2
    obj.col2=tgl.Color2:new(obj.col2[2],obj.col2[1])
    obj:render()
    obj.col2=prev
    os.sleep(.05)
    if obj._clicking and not obj.destroyed and not obj.hidden then
      obj._clicking=nil
      obj:render()
      obj:enable()
    end
    obj._clicking=nil
  end
  obj.pointerDown=obj.handler
  obj.handler=tgl.sys.wrapInput(obj,obj.handler)
  return obj
end
function tgl.Button:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  self.events:listen("touch",self.handler)
end
function tgl.Button:disable()
  self.enabled=false
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  self._clicking=nil  --cancel any pending onClick restore
  self.events:ignore("touch",self.handler)
end
function tgl.Button:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return end
  tgl.sys.renderer:set(self.pos2,self.text,col2,self.z_index)
end

---Makes a Button which fires an eventName event with callValue value
---@param text string
---@param eventName string Event name to push
---@param callValue? any Value to push event with
---@param pos2 tgl.Pos2?
---@param col2 tgl.Color2?
---@return Button
function tgl.EventButton(text,eventName,callValue,pos2,col2)
  checkArg(1,text,"string","nil")
  checkArg(2,eventName,"string")
  checkArg(4,pos2,"table","nil")
  checkArg(5,col2,"table","nil")
  local obj=tgl.Button:new(text,function()end,pos2,col2)
  obj.eventName=eventName
  obj.callValue=callValue
  obj.pointerDown=function(_,_,x,y)
    if obj.destroyed then return end
    if x>=obj.pos2.x
    and x<obj.pos2.x+unicode.wlen(obj.text)
    and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
      end
      if type(obj.onClick)=="function" then
        thread.create(obj.onClick):detach()
      end
      event.push(obj.eventName,obj.callValue)
    end
  end
  obj.handler=tgl.sys.wrapInput(obj,obj.pointerDown)
  obj.callback=nil
  return obj
end

---Extract a visible substring from s, skipping startW terminal-width cells from the left, up to maxW wide.
local function _iFWidthSub(s,startW,maxW)
  local i=1
  local len=unicode.len(s)
  local w=0
  while i<=len and w<startW do
    w=w+unicode.charWidth(unicode.sub(s,i,i))
    i=i+1
  end
  local out={}
  local ow=0
  while i<=len and ow<maxW do
    local ch=unicode.sub(s,i,i)
    local cw=unicode.charWidth(ch)
    if ow+cw>maxW then break end
    out[#out+1]=ch
    ow=ow+cw
    i=i+1
  end
  return table.concat(out)
end

---One-line text input
---@class tgl.InputField:tgl.LineObjectInteractable
---@field defaultText string Default display string
---@field eventName string Event to push after input is done
---@field charCol2 tgl.Color2 Cursor Color2, uses background color(default - lime)
---@field erase boolean If erase field after input is done
---@field secret boolean If use password protection
---@field handler function Function is called on user click
---@field stopOnClickOutside boolean stop input when clicking outside the field (default=false)
tgl.InputField=setmetatable({},{__index=tgl.LineObjectInteractable})
tgl.InputField.__index=tgl.InputField
function tgl.InputField:new(text,pos2,col2)
  checkArg(1,text,"string","nil")
  checkArg(2,pos2,"table","nil")
  checkArg(3,col2,"table","nil")
  ---@type tgl.InputField
  local obj=setmetatable({},self)
  obj.type="InputField"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.events=tgl.Event:new()
  obj.destroyEventName="tgl_destroy_"..tostring(obj)
  obj.z_index=0
  obj.text=""
  obj.secret=false
  obj.defaultText=text or "[______]"
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.col2=col2 or tgl.sys.themeColor("input")
  obj.eventName="InputEvent"
  obj.checkRendered=true
  obj.charCol2=tgl.Color2:new(obj.col2[2],obj.col2[1])
  obj.erase=true
  obj.stopOnClickOutside=false
  obj.stopEventName=nil
  obj.maxLen=-1
  obj.scrollX=false
  obj._viewX=0
  obj.handler=function (_,_,x,y)
    if obj.destroyed then return end
    local textLen=unicode.wlen(obj.text)
    if textLen==0 then textLen=unicode.wlen(obj.defaultText) end
    if x>=obj.pos2.x and x<obj.pos2.x+textLen and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
      end
      obj:disable()
      obj:input()
      if obj.destroyed then return end
      event.push(obj.eventName,obj.text)
      obj:enable()
    end
  end
  obj.pointerDown=obj.handler
  obj.handler=tgl.sys.wrapInput(obj,obj.handler)
  return obj
end
---InputField input function
function tgl.InputField:input()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed then return false end
  self._inputActive=true
  local r=tgl.sys.renderer
  local displayW=unicode.wlen(self.defaultText)
  local printChar=tgl.Text:new(" ",self.charCol2)
  local _prevAA=tgl.sys.getActiveArea()
  local inputArea
  if self.restrictActiveArea~=false and not (self.inputContext and self.inputContext.enabled) then
    inputArea=tgl.Size2:newFromSize(self.pos2.x,self.pos2.y,displayW,1)
    tgl.sys.setActiveArea(inputArea)
  end
  local curCharIdx=0  -- 0-based: cursor is after this many chars
  local curWidth=0    -- terminal-width from text start to cursor
  local viewX=0       -- terminal-width scrolled off the left
  if self.erase and not (self.inputContext and self.inputContext.enabled) then
    r:fill(tgl.Size2:newFromSize(self.pos2.x,self.pos2.y,displayW+1,1)," ",col2,self.z_index)
    self.text=""
  else
    if self.text=="" then
      if not (self.inputContext and self.inputContext.enabled) then
        r:fill(tgl.Size2:newFromSize(self.pos2.x,self.pos2.y,displayW+1,1)," ",col2,self.z_index)
      end
    else
      curCharIdx=unicode.len(self.text)
      curWidth=unicode.wlen(self.text)
      if self.scrollX then viewX=math.max(0,curWidth-displayW) end
    end
  end
  local function renderVisible()
    r:fill(tgl.Size2:newFromSize(self.pos2.x,self.pos2.y,displayW,1)," ",col2,self.z_index)
    if self.text~="" then
      local disp
      if self.secret then
        disp=string.rep("*",math.min(unicode.len(self.text),displayW))
      elseif self.scrollX then
        disp=_iFWidthSub(self.text,viewX,displayW)
      else
        disp=self.text
      end
      if disp and disp~="" then r:set(self.pos2,disp,col2,self.z_index) end
    end
  end
  local function printChr()
    local ch=curCharIdx<unicode.len(self.text) and unicode.sub(self.text,curCharIdx+1,curCharIdx+1) or " "
    printChar.text=self.secret and " " or ch
    printChar.pos2=tgl.Pos2:new(self.pos2.x+(curWidth-viewX),self.pos2.y)
    printChar.z_index=self.z_index
    printChar:render()
  end
  renderVisible=tgl.sys.clipInput(self,renderVisible)
  printChr=tgl.sys.clipInput(self,printChr)
  renderVisible()
  printChr()
  local _pull={"interrupted","key_down",self.destroyEventName}
  if self.stopOnClickOutside then table.insert(_pull,"touch") end
  if self.stopEventName then table.insert(_pull,self.stopEventName) end
  while true do
    local id,_,a,b=self:pullInput(table.unpack(_pull))
    if self._leaveInput or self.destroyed or id==self.destroyEventName then break end
    if self.stopEventName and id==self.stopEventName then
      event.push(self.stopEventName)
      break
    elseif id=="touch" then
      if not(a>=self.pos2.x and a<self.pos2.x+displayW and b==self.pos2.y) then break end
    else
      local key=a    -- char code
      local kcode=b  -- scan code
      if curWidth<0 then curWidth=0 end
      if key==tgl.defaults.keys.enter or key==tgl.defaults.keys.esc
      or kcode==28 or kcode==156 or kcode==1 or id=="interrupted" then
        break
      elseif kcode==tgl.defaults.keys2.arrow_left then
        if curCharIdx>0 then
          local ch=unicode.sub(self.text,curCharIdx,curCharIdx)
          curWidth=curWidth-unicode.charWidth(ch)
          curCharIdx=curCharIdx-1
          if self.scrollX and curWidth<viewX then viewX=curWidth end
          renderVisible() printChr()
        end
      elseif kcode==tgl.defaults.keys2.arrow_right then
        if curCharIdx<unicode.len(self.text) then
          curCharIdx=curCharIdx+1
          local ch=unicode.sub(self.text,curCharIdx,curCharIdx)
          curWidth=curWidth+unicode.charWidth(ch)
          if self.scrollX and (curWidth-viewX)>=displayW then viewX=curWidth-displayW+1 end
          renderVisible() printChr()
        end
      elseif (key==tgl.defaults.keys.backspace or kcode==14) and curCharIdx>0 then
        local ch=unicode.sub(self.text,curCharIdx,curCharIdx)
        local chW=unicode.charWidth(ch)
        self.text=unicode.sub(self.text,1,curCharIdx-1)..unicode.sub(self.text,curCharIdx+1)
        curCharIdx=curCharIdx-1
        curWidth=curWidth-chW
        if self.scrollX and curWidth<viewX then viewX=math.max(0,curWidth) end
        renderVisible() printChr()
      elseif (key==tgl.defaults.keys.delete or kcode==211) and curCharIdx<unicode.len(self.text) then
        self.text=unicode.sub(self.text,1,curCharIdx)..unicode.sub(self.text,curCharIdx+2)
        renderVisible() printChr()
      elseif key>=32 and key~=tgl.defaults.keys.delete then
        local ch=unicode.char(key)
        local chW=unicode.charWidth(ch)
        local fits=(self.maxLen<0 or unicode.len(self.text)<self.maxLen)
          and (self.scrollX or unicode.wlen(self.text)+chW<=displayW)
        if fits then
          self.text=unicode.sub(self.text,1,curCharIdx)..ch..unicode.sub(self.text,curCharIdx+1)
          curCharIdx=curCharIdx+1
          curWidth=curWidth+chW
          if self.scrollX and (curWidth-viewX)>=displayW then viewX=curWidth-displayW+1 end
          renderVisible() printChr()
        end
      end
    end
  end
  self._viewX=viewX
  self._inputActive=nil
  if not self.destroyed and not (self.inputContext and (self.inputContext.redraw==false or self.inputContext.editing~=self))
  and not (self._parentFrame and self._parentFrame.hidden) then
    printChar.col2=col2
    printChr()
    renderVisible()
  end
  if inputArea and (not self.destroyed or tgl.sys.getActiveArea()==inputArea) then
    if _prevAA then tgl.sys.setActiveArea(_prevAA) else tgl.sys.resetActiveArea() end
  end
end
function tgl.InputField:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return false end
  local r=tgl.sys.renderer
  local displayW=unicode.wlen(self.defaultText)
  if self.text~="" and displayW>0 then
    r:fill(tgl.Size2:newFromSize(self.pos2.x,self.pos2.y,displayW,1)," ",col2,self.z_index)
  end
  if self.text=="" then
    r:set(self.pos2,self.defaultText,col2,self.z_index)
  elseif self.secret then
    local cnt=self.scrollX and math.min(unicode.wlen(self.text),displayW) or unicode.wlen(self.text)
    r:set(self.pos2,string.rep("*",cnt),col2,self.z_index)
  elseif self.scrollX then
    local disp=_iFWidthSub(self.text,self._viewX or 0,displayW)
    if disp~="" then r:set(self.pos2,disp,col2,self.z_index) end
  else
    r:set(self.pos2,self.text,col2,self.z_index)
  end
end
function tgl.InputField:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  self.events:listen("touch",self.handler)
end
function tgl.InputField:disable()
  self.enabled=false
  if self.inputContext then
    self.inputContext:cancelPointer(self,"disabled")
    if self.inputContext.editing==self then self.inputContext:stopEditing() end
  end
  self.events:ignore("touch",self.handler)
end

---Vertical scrollbar, callback-based
---@class tgl.Scrollbar:tgl.BoxObject
---@field scroll integer
---@field scrollSpeed integer
---@field maxScroll integer
---@field visibleSize integer height of the visible viewport
---@field hitArea tgl.Size2 area responding to mouse wheel (default=size2)
---@field onChange function|nil called with new scroll value
---@field col2 tgl.Color2 fg=thumb(█) bg=track(space)
---@field enabled boolean
tgl.Scrollbar=setmetatable({},{__index=tgl.BoxObject})
tgl.Scrollbar.__index=tgl.Scrollbar
---@param size2 tgl.Size2 1 column wide
---@param col2? tgl.Color2 fg=thumb color, bg=track color
---@return tgl.Scrollbar
function tgl.Scrollbar:new(size2,col2)
  checkArg(1,size2,"table")
  checkArg(2,col2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="Scrollbar"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.events=tgl.Event:new()
  obj.destroyEventName="tgl_destroy_"..tostring(obj)
  obj.z_index=0
  obj.size2=size2
  obj.col2=col2 or tgl.sys.themeColor("scrollbar")
  obj.trackChar=tgl.sys.themeChar("scrollbarTrack")
  obj.thumbChar=tgl.sys.themeChar("scrollbarThumb")
  obj.scroll=0
  obj.maxScroll=0
  obj.scrollSpeed=1
  obj.visibleSize=size2.sizeY
  obj.hitArea=size2
  obj.onChange=nil
  obj.enabled=false
  obj.scrollHandler=function(_,_,x,y,dir)
    if obj.destroyed or obj.hidden or not obj.enabled then return end
    dir=dir*obj.scrollSpeed
    if obj.maxScroll<=0 then return end
    if not tgl.util.pointInSize2(x,y,obj.hitArea) then return end
    if not tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then return end
    if tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
    obj:setScroll(obj.scroll-dir)
  end
  obj.touchHandler=function(_,_,x,y)
    if obj.destroyed or obj.hidden or not obj.enabled then return end
    if obj.maxScroll<=0 then return end
    if not (x==obj.size2.x1 and y>=obj.size2.y1 and y<=obj.size2.y2) then return end
    if not tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then return end
    if tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
    local startY=y
    local startScroll=obj.scroll
    local trackH=obj.size2.sizeY
    obj._dragActive=true
    while true do
      local id,_,_,dy=obj:pullInput("drag","drop",obj.destroyEventName)
      if id==obj.destroyEventName or obj._leaveInput or id=="drop" or obj.destroyed or obj.hidden or not obj.enabled then break end
      obj:setScroll(startScroll+math.floor((dy-startY)*obj.maxScroll/trackH))
    end
    obj._dragActive=nil
  end
  obj.pointerDown=obj.touchHandler
  obj.pointerScroll=obj.scrollHandler
  obj.touchHandler=tgl.sys.wrapInput(obj,obj.touchHandler)
  obj.scrollHandler=tgl.sys.wrapInput(obj,obj.scrollHandler)
  return obj
end
---@param n integer
function tgl.Scrollbar:setScroll(n)
  checkArg(1,n,"number")
  if self.destroyed then return false end
  n=math.max(0,math.min(self.maxScroll,n))
  if n==self.scroll then return end
  self.scroll=n
  local r=tgl.sys.renderer
  r:stop()
  local deferred=r._deferFlush
  r._deferFlush=true
  local ok,err=pcall(function()
    if type(self.onChange)=="function" then self.onChange(self.scroll) end
    self:render()
  end)
  r._deferFlush=deferred
  r:flush(true)
  if not ok then error(err,0) end
end
function tgl.Scrollbar:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return end
  local r=tgl.sys.renderer
  r:fill(self.size2,self.trackChar,col2,self.z_index)
  if self.maxScroll>0 then
    local trackH=self.size2.sizeY
    local thumbH=math.max(1,math.floor(trackH*self.visibleSize/(self.visibleSize+self.maxScroll)))
    local thumbY=math.floor(self.scroll*(trackH-thumbH)/self.maxScroll)
    r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1+thumbY,1,thumbH),self.thumbChar,col2,self.z_index)
  end
end
function tgl.Scrollbar:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  self.events:listen("scroll",self.scrollHandler)
  self.events:listen("touch",self.touchHandler)
end
function tgl.Scrollbar:disable()
  self.enabled=false
  if self.inputContext then
    self.inputContext:cancelPointer(self,"disabled")
    if self.inputContext.editing==self then self.inputContext:stopEditing() end
  end
  self.events:ignore("scroll",self.scrollHandler)
  self.events:ignore("touch",self.touchHandler)
end

function tgl.Scrollbar:keyDown(char,code)
  local value=self.scroll
  if code==200 then value=value-self.scrollSpeed
  elseif code==208 then value=value+self.scrollSpeed
  elseif code==201 then value=value-self.visibleSize
  elseif code==209 then value=value+self.visibleSize
  elseif code==199 then value=0
  elseif code==207 then value=self.maxScroll
  else return false end
  self:setScroll(value)
  return true
end

---2D Text
---@class tgl.TextBox:tgl.BoxObject
---@field text string
---@field tabSize integer
---@field showScroll boolean auto-show scrollbar when content overflows
---@field viewY integer current scroll offset in lines
---@field enabled boolean
tgl.TextBox=setmetatable({},{__index=tgl.BoxObject})
tgl.TextBox.__index=tgl.TextBox
---@param text string
---@param size2 tgl.Size2
---@param col2? tgl.Color2
function tgl.TextBox:new(text,size2,col2)
  checkArg(1,text,"string")
  checkArg(2,size2,"table")
  checkArg(3,col2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="TextBox"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.z_index=0
  obj.tabSize=2
  obj.scrollTrackChar=tgl.sys.themeChar("scrollbarTrack")
  obj.scrollThumbChar=tgl.sys.themeChar("scrollbarThumb")
  obj.scrollcol2=tgl.sys.themeColor("scrollbar")
  obj.showScroll=true
  obj.viewY=0
  obj.text=text
  obj.size2=size2
  obj.col2=col2 or tgl.sys.themeColor("input")
  obj.enabled=false
  obj._scrollbar=nil
  return obj
end
function tgl.TextBox:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return end
  local r=tgl.sys.renderer
  local maxH=self.size2.sizeY
  local lineCount=0
  for _ in (self.text.."\n"):gmatch("[^\n]*\n") do lineCount=lineCount+1 end
  local scrollActive=self.showScroll and lineCount>maxH
  local maxW=self.size2.sizeX-(scrollActive and 1 or 0)
  if scrollActive then
    if not self._scrollbar then
      self._scrollbar=tgl.Scrollbar:new(
        tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,maxH))
      if self.enabled then self._scrollbar:enable() end
    end
    self._scrollbar.size2:moveToPos2(tgl.Pos2:new(self.size2.x2,self.size2.y1))
    self._scrollbar.owner=self
    self._scrollbar.col2=self.scrollcol2
    self._scrollbar.trackChar=self.scrollTrackChar
    self._scrollbar.thumbChar=self.scrollThumbChar
    self._scrollbar.inputContext=self.inputContext
    self._scrollbar.focused=self.focused
    self._scrollbar.focusCol2=self.focusCol2
    self._scrollbar.hitArea=self.size2
    self._scrollbar.z_index=self.z_index
    self._scrollbar.maxScroll=lineCount-maxH
    self._scrollbar.visibleSize=maxH
    self._scrollbar.scroll=self.viewY
    self._scrollbar.onChange=function(s)
      self.viewY=s
      self:render()
    end
  else
    if self._scrollbar then
      self._scrollbar:destroy()
      self._scrollbar=nil
    end
    self.viewY=0
  end
  local fillSize=scrollActive
    and tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,maxW,maxH)
    or self.size2
  r:fill(fillSize," ",col2,self.z_index)
  local tabRepl=string.rep(" ",self.tabSize)
  local y=self.size2.y1
  local lineN=0
  for line in (self.text.."\n"):gmatch("([^\n]*)\n") do
    lineN=lineN+1
    if lineN>self.viewY then
      if y>self.size2.y2 then break end
      line=line:gsub("\t",tabRepl)
      if unicode.wlen(line)>maxW then line=unicode.sub(line,1,maxW) end
      if #line>0 then r:set(tgl.Pos2:new(self.size2.x1,y),line,col2,self.z_index) end
      y=y+1
    end
  end
  if scrollActive then self._scrollbar:render() end
end
function tgl.TextBox:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  if self._scrollbar then self._scrollbar:enable() end
end
function tgl.TextBox:disable()
  self.enabled=false
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  if self._scrollbar then self._scrollbar:disable() end
end

function tgl.TextBox:keyDown(char,code)
  if self._scrollbar then return self._scrollbar:keyDown(char,code) end
  return false
end

---2D multiline text input box
---@class tgl.InputBox:tgl.BoxObject
---@field text string
---@field tabSize integer
---@field showScroll boolean
---@field viewY integer scroll offset, persists across edit sessions
---@field cursorCol2 tgl.Color2
---@field eventName string
---@field stopEventName string
---@field enabled boolean
---@field handler function
---@field checkRendered boolean check if the box is actually visible before activating (default=true)
---@field stopOnClickOutside boolean stop editing when clicking outside the box (default=true)
---@field clearOnClick boolean clear text when clicking to start editing (default=false)
---@field wrap boolean soft-wrap long lines (default false)
---@field lineNumbers boolean show line numbers in gutter (default false)
---@field lineNumCol2 tgl.Color2|nil gutter color; defaults to darkgray on text background
tgl.InputBox=setmetatable({},{__index=tgl.BoxObject})
tgl.InputBox.__index=tgl.InputBox
---@param text string
---@param size2 tgl.Size2
---@param col2? tgl.Color2
---@return tgl.InputBox
function tgl.InputBox:new(text,size2,col2)
  checkArg(1,text,"string")
  checkArg(2,size2,"table")
  checkArg(3,col2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="InputBox"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.events=tgl.Event:new()
  obj.destroyEventName="tgl_destroy_"..tostring(obj)
  obj.z_index=0
  obj.text=text
  obj.size2=size2
  obj.col2=col2 or tgl.sys.themeColor("input")
  obj.tabSize=2
  obj.scrollTrackChar=tgl.sys.themeChar("scrollbarTrack")
  obj.scrollThumbChar=tgl.sys.themeChar("scrollbarThumb")
  obj.scrollcol2=tgl.sys.themeColor("scrollbar")
  obj.showScroll=true
  obj.viewY=0
  obj._scrollbar=nil
  obj.cursorCol2=tgl.Color2:new(obj.col2[2],obj.col2[1])
  obj.eventName="InputBoxEvent"
  obj.stopEventName="InputBoxStop"
  obj.checkRendered=true
  obj.stopOnClickOutside=true
  obj.clearOnClick=false
  obj.wrap=false
  obj.lineNumbers=false
  obj.lineNumCol2=nil
  obj.enabled=false
  obj.handler=function(_,_,x,y)
    if obj.destroyed then return end
    if tgl.sys.wm and tgl.sys.wm.locked then return end
    local maxX=(obj._scrollbar~=nil) and (obj.size2.x2-1) or obj.size2.x2
    if x>=obj.size2.x1 and x<=maxX and
    y>=obj.size2.y1 and y<=obj.size2.y2 and
    tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
      end
      obj:disable()
      obj:input(x,y)
      if obj.destroyed then return end
      event.push(obj.eventName,obj.text)
      if not obj._keepDisabled then obj:enable() end
      obj._keepDisabled=nil
    end
  end
  obj.pointerDown=obj.handler
  obj.handler=tgl.sys.wrapInput(obj,obj.handler)
  return obj
end
function tgl.InputBox:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  self.events:listen("touch",self.handler)
  if self._scrollbar then self._scrollbar:enable() end
end
function tgl.InputBox:disable()
  self.enabled=false
  if self.inputContext then
    self.inputContext:cancelPointer(self,"disabled")
    if self.inputContext.editing==self then self.inputContext:stopEditing() end
  end
  if self._inputActive then
    event.push(self.stopEventName)
    self._keepDisabled=true
  end
  self.events:ignore("touch",self.handler)
  if self._scrollbar then self._scrollbar:disable() end
end
-- Scrolling changes the viewport, not the document's line layout.
local function inputBoxLayout(box)
  local layout=box._layout
  if layout and layout.text==box.text and layout.width==box.size2.sizeX and layout.height==box.size2.sizeY
  and layout.tabSize==box.tabSize and layout.showScroll==box.showScroll
  and layout.lineNumbers==box.lineNumbers and layout.wrap==box.wrap then return layout end
  box._layout=nil
  local lines={}
  for line in (box.text.."\n"):gmatch("([^\n]*)\n") do lines[#lines+1]=line end
  local lnw=box.lineNumbers and (#tostring(#lines)+1) or 0
  local scrollActive=box.showScroll and #lines>box.size2.sizeY
  local mw=math.max(1,box.size2.sizeX-lnw-(scrollActive and 1 or 0))
  local vlines=nil
  if box.wrap then
    local tabRepl=string.rep(" ",box.tabSize)
    local function build(width)
      local vl={}
      for li,line in ipairs(lines) do
        local exp=line:gsub("\t",tabRepl)
        local len=unicode.wlen(exp)
        if len==0 then vl[#vl+1]={li=li,text="",startVC=0}
        else
          for pos=1,len,width do
            vl[#vl+1]={li=li,text=unicode.sub(exp,pos,math.min(pos+width-1,len)),startVC=pos-1}
          end
        end
      end
      return vl
    end
    vlines=build(mw)
    if box.showScroll and not scrollActive and #vlines>box.size2.sizeY then
      scrollActive=true mw=math.max(1,box.size2.sizeX-lnw-1) vlines=build(mw)
    end
  end
  layout={text=box.text,width=box.size2.sizeX,height=box.size2.sizeY,tabSize=box.tabSize,
    showScroll=box.showScroll,lineNumbers=box.lineNumbers,wrap=box.wrap,
    lineCount=#lines,lnw=lnw,mw=mw,scrollActive=scrollActive,vlines=vlines,
    lines=lines}
  box._layout=layout
  return layout
end
local function renderInputHighlight(box,layout)
  local mark=box.highlight
  if not mark or mark.width<=0 then return end
  local r=tgl.sys.renderer
  local function draw(row,startVC,text)
    local left=math.max(mark.startVC,startVC)
    local right=math.min(mark.startVC+mark.width,startVC+layout.mw)
    if left>=right then return end
    local visible=_iFWidthSub(text,left-startVC,right-left)
    if visible~="" then
      r:set(tgl.Pos2:new(box.size2.x1+layout.lnw+left-startVC,box.size2.y1+row-1),
        visible,box.cursorCol2,box.z_index)
    end
  end
  for row=1,box.size2.sizeY do
    local index=box.viewY+row
    if box.wrap then
      local line=layout.vlines[index]
      if line and line.li==mark.line then draw(row,line.startVC,line.text) end
    elseif index==mark.line and layout.lines[index] then
      draw(row,0,layout.lines[index]:gsub("\t",string.rep(" ",box.tabSize)))
    end
  end
end
---Reveal a logical line/character column; optionally highlight length characters.
function tgl.InputBox:showPosition(line,column,length)
  checkArg(1,line,"number")
  checkArg(2,column,"number","nil")
  checkArg(3,length,"number","nil")
  local layout=inputBoxLayout(self)
  line=math.max(1,math.min(layout.lineCount,line))
  local text=layout.lines[line]
  column=math.max(1,math.min(unicode.len(text)+1,column or 1))
  local before=unicode.sub(text,1,column-1):gsub("\t",string.rep(" ",self.tabSize))
  local vc=unicode.wlen(before)
  local row=line
  if self.wrap then
    for i,part in ipairs(layout.vlines) do
      if part.li==line then
        row=i
        if vc<part.startVC+layout.mw then break end
      end
    end
  end
  local total=self.wrap and #layout.vlines or layout.lineCount
  self.viewY=math.max(0,math.min(row-1,total-self.size2.sizeY))
  self.highlight=nil
  if length and length>0 then
    local found=unicode.sub(text,column,column+length-1):gsub("\t",string.rep(" ",self.tabSize))
    self.highlight={line=line,startVC=vc,width=unicode.wlen(found)}
  end
end
function tgl.InputBox:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return end
  local r=tgl.sys.renderer
  local maxH=self.size2.sizeY
  local tabRepl=string.rep(" ",self.tabSize)

  if self.wrap then
    local layout=inputBoxLayout(self)
    local lnw=layout.lnw
    local lnCol2=lnw>0 and (self.lineNumCol2 or tgl.Color2:new(tgl.defaults.colors16.darkgray,col2[2])) or nil
    local mw,vlines,scrollActive=layout.mw,layout.vlines,layout.scrollActive
    if scrollActive then
      if not self._scrollbar then
        self._scrollbar=tgl.Scrollbar:new(
          tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,maxH))
        if self.enabled then self._scrollbar:enable() end
      end
      self._scrollbar.size2:moveToPos2(tgl.Pos2:new(self.size2.x2,self.size2.y1))
      self._scrollbar.owner=self
      self._scrollbar.col2=self.scrollcol2
      self._scrollbar.trackChar=self.scrollTrackChar
      self._scrollbar.thumbChar=self.scrollThumbChar
      self._scrollbar.inputContext=self.inputContext
      self._scrollbar.focused=self.focused
      self._scrollbar.focusCol2=self.focusCol2
      self._scrollbar.hitArea=self.size2
      self._scrollbar.z_index=self.z_index
      self._scrollbar.maxScroll=math.max(0,#vlines-maxH)
      self._scrollbar.visibleSize=maxH
      self._scrollbar.scroll=self.viewY
      self._scrollbar.onChange=function(s)
        self.viewY=s
        local rr=tgl.sys.renderer
        rr:stop() self:render() rr:flush()
      end
    else
      if self._scrollbar then
        self._scrollbar:destroy()
        self._scrollbar=nil
      end
      self.viewY=0
    end
    if lnw>0 then
      r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,lnw,maxH)," ",lnCol2,self.z_index)
    end
    local textX=self.size2.x1+lnw
    local textW=scrollActive and mw or (self.size2.sizeX-lnw)
    r:fill(tgl.Size2:newFromSize(textX,self.size2.y1,textW,maxH)," ",col2,self.z_index)
    local y=self.size2.y1
    for vi=self.viewY+1,#vlines do
      if y>self.size2.y2 then break end
      local vl=vlines[vi]
      if lnw>0 then
        local numStr=vl.startVC==0 and string.format("%"..(lnw-1).."d ",vl.li) or string.rep(" ",lnw)
        r:set(tgl.Pos2:new(self.size2.x1,y),numStr,lnCol2,self.z_index)
      end
      if #vl.text>0 then
        r:set(tgl.Pos2:new(textX,y),vl.text,col2,self.z_index)
      end
      y=y+1
    end
    renderInputHighlight(self,layout)
    if scrollActive then self._scrollbar:render() end
    return
  end

  local layout=inputBoxLayout(self)
  local lineCount=layout.lineCount
  local scrollActive=layout.scrollActive
  if scrollActive then
    if not self._scrollbar then
      self._scrollbar=tgl.Scrollbar:new(
        tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,maxH))
      if self.enabled then self._scrollbar:enable() end
    end
    self._scrollbar.size2:moveToPos2(tgl.Pos2:new(self.size2.x2,self.size2.y1))
    self._scrollbar.owner=self
    self._scrollbar.col2=self.scrollcol2
    self._scrollbar.trackChar=self.scrollTrackChar
    self._scrollbar.thumbChar=self.scrollThumbChar
    self._scrollbar.inputContext=self.inputContext
    self._scrollbar.focused=self.focused
    self._scrollbar.focusCol2=self.focusCol2
    self._scrollbar.hitArea=self.size2
    self._scrollbar.z_index=self.z_index
    self._scrollbar.maxScroll=lineCount-maxH
    self._scrollbar.visibleSize=maxH
    self._scrollbar.scroll=self.viewY
    self._scrollbar.onChange=function(s)
      self.viewY=s
      local rr=tgl.sys.renderer
      rr:stop() self:render() rr:flush()
    end
  else
    if self._scrollbar then
      self._scrollbar:destroy()
      self._scrollbar=nil
    end
    self.viewY=0
  end
  local lnw=self.lineNumbers and (#tostring(lineCount)+1) or 0
  local lnCol2=lnw>0 and (self.lineNumCol2 or tgl.Color2:new(tgl.defaults.colors16.darkgray,col2[2])) or nil
  local textMaxW=layout.mw
  local textX=self.size2.x1+lnw
  if lnw>0 then
    r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,lnw,maxH)," ",lnCol2,self.z_index)
  end
  local textW=scrollActive and textMaxW or (self.size2.sizeX-lnw)
  r:fill(tgl.Size2:newFromSize(textX,self.size2.y1,textW,maxH)," ",col2,self.z_index)
  local y=self.size2.y1
  for lineN=self.viewY+1,math.min(lineCount,self.viewY+maxH) do
    local line=layout.lines[lineN]
    if lnw>0 then
      r:set(tgl.Pos2:new(self.size2.x1,y),string.format("%"..(lnw-1).."d ",lineN),lnCol2,self.z_index)
    end
    line=line:gsub("\t",tabRepl)
    if unicode.wlen(line)>textMaxW then line=unicode.sub(line,1,textMaxW) end
    if #line>0 then r:set(tgl.Pos2:new(textX,y),line,col2,self.z_index) end
    y=y+1
  end
  renderInputHighlight(self,layout)
  if scrollActive then self._scrollbar:render() end
end
function tgl.InputBox:input(startX,startY)
  checkArg(1,startX,"number","nil")
  checkArg(2,startY,"number","nil")
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed then return false end
  self.highlight=nil
  self._layout=nil
  local r=tgl.sys.renderer
  local lines={}
  for line in (self.text.."\n"):gmatch("([^\n]*)\n") do lines[#lines+1]=line end
  if #lines==0 then lines={""} end
  local maxH=self.size2.sizeY
  local tabRepl=string.rep(" ",self.tabSize)

  local function getLNW()
    if not self.lineNumbers then return 0 end
    return #tostring(#lines)+1
  end
  local function getMaxW()
    return self.size2.sizeX-(self._scrollbar and 1 or 0)-getLNW()
  end

  local function visualToCol(line,vx)
    local x=0
    for i=1,unicode.wlen(line) do
      local ch=unicode.sub(line,i,i)
      local w=(ch=="\t") and self.tabSize or unicode.charWidth(ch)
      if x+w>vx then return i end
      x=x+w
    end
    return unicode.wlen(line)+1
  end

  local function expandedVColToCol(origLine,totalVC)
    local acc=0
    for i=1,unicode.wlen(origLine) do
      local ch=unicode.sub(origLine,i,i)
      local w=(ch=="\t") and self.tabSize or unicode.charWidth(ch)
      if acc+w>totalVC then return i end
      acc=acc+w
    end
    return unicode.wlen(origLine)+1
  end

  local ln=1
  local col=1
  if self.inputContext and self.inputContext.enabled then
    ln=math.max(1,math.min(#lines,self.cursorLine or 1))
    col=math.max(1,math.min(unicode.wlen(lines[ln])+1,self.cursorColumn or 1))
  end
  local vlines={}

  local function buildVL()
    local mw=getMaxW()
    local vl={}
    for li,line in ipairs(lines) do
      local exp=line:gsub("\t",tabRepl)
      local len=unicode.wlen(exp)
      if len==0 then
        vl[#vl+1]={li=li,text="",startVC=0}
      else
        local pos=1
        while pos<=len do
          vl[#vl+1]={li=li,text=unicode.sub(exp,pos,math.min(pos+mw-1,len)),startVC=pos-1}
          pos=pos+mw
        end
      end
    end
    return vl
  end

  local function cursorVPos()
    local mw=getMaxW()
    local vc=0
    for i=1,col-1 do
      local ch=unicode.sub(lines[ln],i,i)
      vc=vc+(ch=="\t" and self.tabSize or unicode.charWidth(ch))
    end
    for vi,vl in ipairs(vlines) do
      if vl.li==ln then
        local isLast=(vi==#vlines) or (vlines[vi+1].li~=ln)
        if isLast or vc<vl.startVC+mw then
          return vi,vc-vl.startVC
        end
      end
    end
    return math.max(1,#vlines),0
  end

  if self.wrap then vlines=buildVL() end

  if startX and startY then
    local effStartX=math.max(0,startX-self.size2.x1-getLNW())
    if self.wrap then
      local vi=startY-self.size2.y1+self.viewY+1
      vi=math.max(1,math.min(#vlines,vi))
      local vl=vlines[vi]
      ln=vl.li
      local totalVC=vl.startVC+effStartX
      col=expandedVColToCol(lines[ln],totalVC)
      col=math.max(1,math.min(col,unicode.wlen(lines[ln])+1))
    else
      ln=math.max(1,math.min(#lines,startY-self.size2.y1+self.viewY+1))
      col=visualToCol(lines[ln],effStartX)
    end
  end
  if self.clearOnClick and (not (self.inputContext and self.inputContext.enabled) or startX and startY) then
    lines={""}
    ln=1 col=1
    self.viewY=0
    if self.wrap then vlines=buildVL() end
  end

  local function ensureVisible()
    if self.wrap then
      local vi,_=cursorVPos()
      local vr=vi-1
      if vr<self.viewY then self.viewY=vr end
      if vr>=self.viewY+maxH then self.viewY=vr-maxH+1 end
    else
      if ln-1<self.viewY then self.viewY=ln-1 end
      if ln-1>=self.viewY+maxH then self.viewY=ln-maxH end
    end
    if self._scrollbar then self._scrollbar.scroll=self.viewY end
  end

  local function renderEdit()
    local maxW=getMaxW()
    local lnw=getLNW()
    local lnCol2=lnw>0 and (self.lineNumCol2 or tgl.Color2:new(tgl.defaults.colors16.darkgray,col2[2])) or nil
    local textX=self.size2.x1+lnw
    if lnw>0 then
      r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,lnw,maxH)," ",lnCol2,self.z_index)
    end
    local textW=self._scrollbar and maxW or (self.size2.sizeX-lnw)
    r:fill(tgl.Size2:newFromSize(textX,self.size2.y1,textW,maxH)," ",col2,self.z_index)
    if self.wrap then
      for i=1,maxH do
        local vi=i+self.viewY
        if vi>#vlines then break end
        local vl=vlines[vi]
        if lnw>0 then
          local numStr=vl.startVC==0 and string.format("%"..(lnw-1).."d ",vl.li) or string.rep(" ",lnw)
          r:set(tgl.Pos2:new(self.size2.x1,self.size2.y1+i-1),numStr,lnCol2,self.z_index)
        end
        if #vl.text>0 then
          r:set(tgl.Pos2:new(textX,self.size2.y1+i-1),vl.text,col2,self.z_index)
        end
      end
      local vi,vcx=cursorVPos()
      local cy=vi-self.viewY
      if cy>=1 and cy<=maxH and vcx<maxW then
        local vl=vlines[vi]
        local rawChar=unicode.sub(vl.text,vcx+1,vcx+1)
        local dispChar=(rawChar=="" or rawChar=="\t") and " " or rawChar
        r:set(tgl.Pos2:new(textX+vcx,self.size2.y1+cy-1),dispChar,self.cursorCol2,self.z_index+1)
      end
    else
      for i=1,maxH do
        local li=i+self.viewY
        if li>#lines then break end
        if lnw>0 then
          r:set(tgl.Pos2:new(self.size2.x1,self.size2.y1+i-1),string.format("%"..(lnw-1).."d ",li),lnCol2,self.z_index)
        end
        local line=lines[li]:gsub("\t",tabRepl)
        if unicode.wlen(line)>maxW then line=unicode.sub(line,1,maxW) end
        if #line>0 then
          r:set(tgl.Pos2:new(textX,self.size2.y1+i-1),line,col2,self.z_index)
        end
      end
      local cy=ln-self.viewY
      if cy>=1 and cy<=maxH then
        local prefix=unicode.sub(lines[ln],1,col-1):gsub("\t",tabRepl)
        local cx=unicode.wlen(prefix)
        if cx<maxW then
          local rawChar=unicode.sub(lines[ln],col,col)
          local dispChar=(rawChar=="" or rawChar=="\t") and " " or rawChar
          r:set(tgl.Pos2:new(textX+cx,self.size2.y1+cy-1),dispChar,self.cursorCol2,self.z_index+1)
        end
      end
    end
    if self._scrollbar then
      self._scrollbar.z_index=self.z_index
      self._scrollbar:render()
    end
    r:flush()
  end

  renderEdit=tgl.sys.clipInput(self,renderEdit)

  local function updateScrollbar()
    local totalRows=self.wrap and #vlines or #lines
    local needScroll=self.showScroll and totalRows>maxH
    if needScroll then
      if not self._scrollbar then
        self._scrollbar=tgl.Scrollbar:new(
          tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,maxH))
        self._scrollbar.owner=self
        self._scrollbar.col2=self.scrollcol2
        self._scrollbar.trackChar=self.scrollTrackChar
        self._scrollbar.thumbChar=self.scrollThumbChar
        self._scrollbar.inputContext=self.inputContext
        self._scrollbar.focused=self.focused
        self._scrollbar.focusCol2=self.focusCol2
        self._scrollbar.hitArea=self.size2
        self._scrollbar.z_index=self.z_index
        self._scrollbar.events:listen("scroll",self._scrollbar.scrollHandler)
        if self.inputContext and self.inputContext.enabled then self._scrollbar:enable() end
        if self.wrap then vlines=buildVL() totalRows=#vlines end
      end
      self._scrollbar.maxScroll=math.max(0,totalRows-maxH)
      self._scrollbar.visibleSize=maxH
      self._scrollbar.scroll=self.viewY
      self._scrollbar.onChange=function(s)
        self.viewY=s renderEdit()
      end
    else
      if self._scrollbar then
        self._scrollbar:destroy()
        self._scrollbar=nil
        if self.wrap then vlines=buildVL() end
        self.viewY=0
      end
    end
  end

  --re-register scroll handler (disable() removed it; touch handled inline below)
  if self._scrollbar then
    self._scrollbar.events:listen("scroll",self._scrollbar.scrollHandler)
    self._scrollbar.onChange=function(s) self.viewY=s renderEdit() end
  end

  updateScrollbar()
  ensureVisible()
  renderEdit()

  self._inputActive=true
  while true do
    local id,_,a1,a2=self:pullInput("interrupted","key_down","touch",self.stopEventName,self.destroyEventName)
    if self._leaveInput or self.destroyed or id=="interrupted" or id==self.stopEventName then break end

    if id=="touch" then
      local tx,ty=a1,a2
      local wm=tgl.sys.wm
      local managed=wm and self._parentFrame and wm:getManagedWindow(self._parentFrame)
      if managed and wm:getWindowAt(tx,ty)~=managed then
        if self.stopOnClickOutside then break else goto continue end
      end
      if self._scrollbar and tx==self._scrollbar.size2.x1
      and ty>=self._scrollbar.size2.y1 and ty<=self._scrollbar.size2.y2 then
        local startScroll=self._scrollbar.scroll
        local trackH=self._scrollbar.size2.sizeY
        while true do
          local did,_,_,dy=self:pullInput("drag","drop",self.destroyEventName)
          if self._leaveInput or self.destroyed or did=="drop" then break end
          self._scrollbar:setScroll(startScroll+math.floor((dy-ty)*self._scrollbar.maxScroll/trackH))
        end
        if self._leaveInput or self.destroyed then break end
        goto continue
      elseif tgl.util.pointInSize2(tx,ty,self.size2) then
        local effX=math.max(0,tx-self.size2.x1-getLNW())
        if self.wrap then
          local vi=ty-self.size2.y1+self.viewY+1
          vi=math.max(1,math.min(#vlines,vi))
          local vl=vlines[vi]
          ln=vl.li
          local totalVC=vl.startVC+effX
          col=expandedVColToCol(lines[ln],totalVC)
          col=math.max(1,math.min(col,unicode.wlen(lines[ln])+1))
        else
          ln=math.max(1,math.min(#lines,ty-self.size2.y1+self.viewY+1))
          col=visualToCol(lines[ln],effX)
        end
      elseif self.stopOnClickOutside then
        break
      else
        goto continue  -- touch outside, nothing changed: skip render
      end
    else  --key_down
      local key,key2=a1,a2
      if self._leaveInput or (self.onKeyDown and self.onKeyDown(key,key2)) or self._leaveInput then break
      elseif key==tgl.defaults.keys.esc or key2==1 then
        break
      elseif key2==tgl.defaults.keys2.arrow_left then
        if col>1 then col=col-1
        elseif ln>1 then ln=ln-1 col=unicode.wlen(lines[ln])+1 end
      elseif key2==tgl.defaults.keys2.arrow_right then
        if col<=unicode.wlen(lines[ln]) then col=col+1
        elseif ln<#lines then ln=ln+1 col=1 end
      elseif key2==tgl.defaults.keys2.arrow_up then
        if ln>1 then ln=ln-1 col=math.min(col,unicode.wlen(lines[ln])+1) end
      elseif key2==tgl.defaults.keys2.arrow_down then
        if ln<#lines then ln=ln+1 col=math.min(col,unicode.wlen(lines[ln])+1) end
      elseif key==tgl.defaults.keys.enter then
        local before=unicode.sub(lines[ln],1,col-1)
        local after=unicode.sub(lines[ln],col)
        lines[ln]=before
        table.insert(lines,ln+1,after)
        ln=ln+1 col=1
      elseif key==tgl.defaults.keys.backspace then
        if col>1 then
          lines[ln]=unicode.sub(lines[ln],1,col-2)..unicode.sub(lines[ln],col)
          col=col-1
        elseif ln>1 then
          local prevLen=unicode.wlen(lines[ln-1])
          lines[ln-1]=lines[ln-1]..lines[ln]
          table.remove(lines,ln)
          ln=ln-1 col=prevLen+1
        end
      elseif key==tgl.defaults.keys.delete then
        if col<=unicode.wlen(lines[ln]) then
          lines[ln]=unicode.sub(lines[ln],1,col-1)..unicode.sub(lines[ln],col+1)
        elseif ln<#lines then
          lines[ln]=lines[ln]..lines[ln+1]
          table.remove(lines,ln+1)
        end
      elseif key==tgl.defaults.keys.tab then
        local sp=string.rep(" ",self.tabSize)
        lines[ln]=unicode.sub(lines[ln],1,col-1)..sp..unicode.sub(lines[ln],col)
        col=col+self.tabSize
      elseif key>=32 then
        local ch=unicode.char(key)
        lines[ln]=unicode.sub(lines[ln],1,col-1)..ch..unicode.sub(lines[ln],col)
        col=col+unicode.charWidth(ch)
      end
    end
    if self.wrap then vlines=buildVL() end
    updateScrollbar()
    ensureVisible()
    renderEdit()
    ::continue::
  end

  if self._scrollbar then
    self._scrollbar.events:ignore("scroll",self._scrollbar.scrollHandler)
    self._scrollbar.onChange=nil
  end
  self._inputActive=nil
  self.text=table.concat(lines,"\n")
  self.cursorLine=ln self.cursorColumn=col
  if not self.destroyed and not (self.inputContext and (self.inputContext.redraw==false or self.inputContext.editing~=self))
  and not (self._parentFrame and self._parentFrame.hidden) then
    local wm=tgl.sys.wm
    local managed=wm and self._parentFrame and wm:getManagedWindow(self._parentFrame)
    if managed then wm:renderRegions({self.size2})
    else
      r:stop()
      self:render()  --preserves self.viewY, re-arms onChange for non-edit scrolling
      r:flush()
    end
  end
end

---2D Box frame
---@class tgl.Frame:tgl.BoxObject
---@field objects table<string|integer, table> Objects can have relpos2 field, represents their position inside the frame
---@field borderType string Frame border type(`"inline"/"outline"`, default=`"inline"`)
---@field borders string|nil
---@field translate function
---@field enableAll function
---@field disableAll function
---@field open function
---@field close function
tgl.Frame=setmetatable({},{__index=tgl.BoxObject})
tgl.Frame.__index=tgl.Frame
---@param objects table<string|integer, tgl.UIObject|tgl.LineObject|tgl.BoxObject>
---@param size2 tgl.Size2
---@param col2? tgl.Color2
---@return tgl.Frame
function tgl.Frame:new(objects,size2,col2)
  checkArg(1,objects,"table")
  checkArg(2,size2,"table")
  checkArg(3,col2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="Frame"
  obj.z_index=0
  obj.objects=objects
  for _,object in pairs(objects) do
    if not canOwn(obj,object) then return nil end
  end
  obj.size2=size2
  obj.col2=col2 or tgl.sys.themeColor("frame")
  obj.borderType="inline"
  --translate objects
  obj:translate()
  return obj
end
---move objects from relative positions to absolute ones in frame(TODO REWORK)
function tgl.Frame:translate()
  for _,object in pairs(self.objects) do
    if object.type then
      object._parentFrame=self
      if object.size2 then
        if not object.relsize2 then
          object.relsize2=tgl.Size2:newFromPoint(object.size2.x1,object.size2.y1,object.size2.x2,object.size2.y2)
        end
        local newPos=tgl.Pos2:new(object.relsize2.x1+self.size2.x1-1,object.relsize2.y1+self.size2.y1-1)
        if newPos then
          object:moveToPos2(newPos)
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"Frame/translate")
        end
      else
        if not object.relpos2 then object.relpos2=object.pos2 end
        local t_pos2=object.relpos2
        if t_pos2 then
          object.pos2=tgl.Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1)
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"Frame/translate")
        end
      end
    end
  end
end
function tgl.Frame:render()
  if self.destroyed or self.hidden then return false end
  local r=tgl.sys.renderer
  local s=self.size2
  local col2=self.col2
  local z=self.z_index
  --frame
  if self.gradient then r:gradient(s,self.gradient,col2,z)
  else r:fill(s," ",col2,z) end
  --border
  if type(self.borders)=="string" and unicode.wlen(self.borders)>=6 then
    local bt=self.borderType or "inline"
    local h=unicode.sub(self.borders,1,1)
    local v=unicode.sub(self.borders,2,2)
    local lt=unicode.sub(self.borders,3,3)
    local rt=unicode.sub(self.borders,4,4)
    local lb=unicode.sub(self.borders,5,5)
    local rb=unicode.sub(self.borders,6,6)
    local x1,y1=0,0
    local x2,y2=0,0
    local hl,vl=0,0
    local drawBorder=true
    if bt=="outline" then
      x1,y1=s.x1-1,s.y1-1
      x2,y2=s.x2+1,s.y2+1
      hl,vl=s.sizeX,s.sizeY
    elseif bt=="inline" then
      x1,y1=s.x1,s.y1
      x2,y2=s.x2,s.y2
      hl,vl=s.sizeX-2,s.sizeY-2
    else
      tgl.util.log("Invalid border type: "..tostring(self.borderType),"Frame/render/borders")
      drawBorder=false
    end
    if drawBorder then
      --top & bottom
      r:setPoint(x1+1,y1,h:rep(hl),col2,z)
      r:setPoint(x1+1,y2,h:rep(hl),col2,z)
      --left & right
      r:setPoint(x1,y1+1,v:rep(vl),col2,z,true)
      r:setPoint(x2,y1+1,v:rep(vl),col2,z,true)
      --corners
      r:setPoint(x1,y1,lt,col2,z)
      r:setPoint(x2,y1,rt,col2,z)
      r:setPoint(x1,y2,lb,col2,z)
      r:setPoint(x2,y2,rb,col2,z)
    end
  end
  --objects
  for _,object in pairs(self.objects) do
    if object.type then
      -- Store original z_index as relative if not already stored
      if not object.relativeZ then
        object.relativeZ=object.z_index
      end
      -- Calculate absolute z_index based on frame's z_index
      object.z_index=self.z_index+object.relativeZ
      r:withClip(self.size2,object.render,object)
    end
  end
end
---Move frame and all its contents
---@param pos2 tgl.Pos2
function tgl.Frame:moveToPos2(pos2)
  checkArg(1,pos2,"table","nil")
  if not pos2 then return false end
  self.size2:moveToPos2(pos2)
  self:translate()
end
---Render only a specific region of the frame
---@param clipRegion tgl.Size2
function tgl.Frame:renderRegion(clipRegion)
  checkArg(1,clipRegion,"table","nil")
  if self.destroyed or self.hidden then return false end
  if not clipRegion or clipRegion.type~="Size2" then return false end
  local r=tgl.sys.renderer
  r:withClip(clipRegion,self.render,self)
  return true
end
function tgl.Frame:enableAll()
  if self.destroyed then return false end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
      if tgl.sys.enableAllTypes[object.type] then object:enableAll() end
    end
  end
end
function tgl.Frame:disableAll()
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:disable() end
      if tgl.sys.enableAllTypes[object.type] then object:disableAll() end
    end
  end
end
---Add an object to frame(with translating)
---@param object tgl.UIObject
---@param name? string
---@return boolean
function tgl.Frame:add(object,name)
  checkArg(1,object,"table","nil")
  checkArg(2,name,"string","number","nil")
  if not self.destroyed and canOwn(self,object) then
    for key,child in pairs(self.objects) do
      if child==object then return key==name end
    end
    if name and self.objects[name] then self:remove(name) end
    object._parentFrame=self
    if not name then
      table.insert(self.objects,object)
    else
      self.objects[name]=object
    end
    self:translate()
    if self.inputContext and self.inputContext.enabled then self.inputContext:controls() end
    return true
  end
  return false
end
---Detach and disable an object for reuse. Returns it without destroying it.
---@param elem integer|string object name
function tgl.Frame:remove(elem)
  checkArg(1,elem,"string","number","nil")
  local object=self.objects[elem]
  if object then
    if object.inputContext then object.inputContext:release(object) end
    if tgl.sys.enableTypes[object.type] then
      object:disable()
    end
    if tgl.sys.enableAllTypes[object.type] then
      object:disableAll()
    end
    self.objects[elem]=nil
    if object._parentFrame==self then object._parentFrame=nil end
  end
  return object
end

---Saves a box from screen
---@class tgl.ScreenSave:tgl.BoxObject
---@field data string[] packed character/color rows for RAM snapshots
---@field savedZ string[] packed per-cell z rows
---@field buf integer|nil
---@field save function
---@field dump function
tgl.ScreenSave=setmetatable({},{__index=tgl.BoxObject})
tgl.ScreenSave.__index=tgl.ScreenSave
--Packed rows keep RAM snapshots small; restoration emits color runs at execution.
tgl.Renderer.cmd.screensave=function(r,cmd)
  local cell={cmd="set",buffer=0,clipRegion=cmd.clipRegion,pos2={},col2={}}
  for row,data in ipairs(cmd.data) do
    local pos,x=1,cmd.size2.x1
    local run,start,fg,bg,z={},x,nil,nil,nil
    local function draw()
      if #run==0 then return end
      cell.pos2.x=start cell.pos2.y=cmd.size2.y1+row-1
      cell.value=table.concat(run) cell.col2[1]=fg cell.col2[2]=bg cell.z_index=z
      r:execCmd(cell)
      run={}
    end
    local column=1
    while pos<=#data do
      local f,b,char,nextPos=string.unpack(">I4I4s1",data,pos)
      local depth=cmd.savedZ[row] and string.unpack(">d",cmd.savedZ[row],(column-1)*8+1) or cmd.z_index
      local width=unicode.wlen(char)
      if fg~=f or bg~=b or z~=depth or width~=1 then draw() start=x end
      fg,bg,z=f,b,depth
      run[#run+1]=char
      if width~=1 then draw() start=x+1 end
      x=x+1 column=column+1 pos=nextPos
    end
    draw()
  end
  return true
end

---Save the chars from `self.size2` region to packed rows in `self.data`.
function tgl.ScreenSave:save(useBuffer)
  checkArg(1,useBuffer,"boolean","nil")
  if self.destroyed then return false end
  self:unload()
  self.data={}
  self.savedZ={}
  local r=tgl.sys.renderer
  if useBuffer then
    local success,buf=r:allocateBuffer(self.size2.sizeX,self.size2.sizeY)
    if success then
      self.buf=buf
      r:bufcopy(0,buf,tgl.Size2:new(1,1,self.size2.sizeX,self.size2.sizeY),self.z_index,self.size2.pos1)
      r:addCmd({cmd="savez",size2=self.size2,savedZ=self.savedZ,z_index=self.z_index})
      return
    end
  end
  --Read back the screen only after queued drawing and restores have completed.
  r:flush()
  local active=r.gpu.getActiveBuffer()
  r.gpu.setActiveBuffer(0)
  local ok,err=pcall(function()
    for y=self.size2.y1,self.size2.y2 do
      local row,depth={},{}
      for x=self.size2.x1,self.size2.x2 do
        local char,fg,bg=r.gpu.get(x,y)
        row[#row+1]=string.pack(">I4I4s1",fg,bg,char)
        depth[#depth+1]=string.pack(">d",r:getZ(x,y))
      end
      self.data[#self.data+1]=table.concat(row)
      self.savedZ[#self.savedZ+1]=table.concat(depth)
    end
  end)
  r.gpu.setActiveBuffer(active)
  if not ok then error(err,0) end
end
---Save an area from screen
---@param size2 tgl.Size2
---@param useBuffer? boolean
---@return tgl.ScreenSave
function tgl.ScreenSave:new(size2,useBuffer)
  checkArg(1,size2,"table","nil")
  checkArg(2,useBuffer,"boolean","nil")
  if not size2 then size2=tgl.Size2:newFromPoint(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY) end
  local x1,y1=math.max(1,size2.x1),math.max(1,size2.y1)
  local x2,y2=math.min(tgl.defaults.screenSizeX,size2.x2),math.min(tgl.defaults.screenSizeY,size2.y2)
  if x1>x2 or y1>y2 then return nil end
  size2=tgl.Size2:newFromPoint(x1,y1,x2,y2)
  if useBuffer==nil then useBuffer=true end
  local obj=setmetatable({},self)
  obj.z_index=0
  obj.size2=size2
  obj.data={}
  obj.buf=0
  obj.type="ScreenSave"
  obj:save(useBuffer)
  return obj
end
function tgl.ScreenSave:unload()
  if self.buf and self.buf>0 then
    tgl.sys.renderer:freeBuffer(self.buf)
    self.buf=0
  end
end
function tgl.ScreenSave:destroy()
  if not tgl.UIObject.destroy(self) then return false end
  self.data={}
  self.savedZ={}
  return true
end
function tgl.ScreenSave:render()
  if self.destroyed then return false end
  if (not self.buf or self.buf==0) and not next(self.data) then return false end
  local r=tgl.sys.renderer
  if self.buf and self.buf>0 then
    r:addCmd({cmd="bufcopy",src=self.buf,dst=0,size2=self.size2,bufpos2={x=1,y=1},
      z_index=self.z_index,savedZ=self.savedZ})
    r:freeBuffer(self.buf)
    self.buf=0
    r:resetCursor()
  else
    r:addCmd({cmd="screensave",data=self.data,savedZ=self.savedZ,size2=self.size2,z_index=self.z_index or 0})
  end
  self.data={}
  self.savedZ={}
end
---Dump saved data to file
---@param filename? string default=`"screensave.st"`
---@return boolean
function tgl.ScreenSave:dump(filename)
  checkArg(1,filename,"string","nil")
  if not filename then filename="screensave.st" end
  local file=io.open(filename,"w")
  if not file then
    tgl.util.log("Couldn't open file: "..tostring(filename),"ScreenSave/dump")
    return false
  end
  file:write(require("serialization").serialize({self.size2.x1,self.size2.y1,self.size2.x2,self.size2.y2}))
  file:write("\n")
  file:write(require("serialization").serialize({rows=self.data,z=self.savedZ})):close()
  return true
end
function tgl.ScreenSave:load(filename)
  checkArg(1,filename,"string","nil")
  if not filename then filename="screensave.st" end
  local file=io.open(filename)
  if not file then
    tgl.util.log("Couldn't open file: "..tostring(filename),"ScreenSave/load")
    return false
  end
  local size_raw=require("serialization").unserialize(file:read("*l"))
  if size_raw then
    local load_size2=tgl.Size2:newFromPoint(size_raw[1],size_raw[2],size_raw[3],size_raw[4])
    if load_size2 then
      local data=require("serialization").unserialize(file:read("*l"))
      if data then
        local obj=setmetatable({},tgl.ScreenSave)
        obj.type="ScreenSave"
        obj.buf=0
        obj.size2=load_size2
        obj.data=data.rows or {}
        obj.savedZ=data.z or {}
        obj.z_index=0
        if not data.rows then
          --Read older dumps stored as data[x][y]={char,Color2}.
          for y=load_size2.y1,load_size2.y2 do
            local row={}
            for x=load_size2.x1,load_size2.x2 do
              local cell=data[x][y]
              row[#row+1]=string.pack(">I4I4s1",cell[2][1],cell[2][2],cell[1])
            end
            obj.data[#obj.data+1]=table.concat(row)
          end
        end
        file:close()
        return obj
      end
    end
  end
  file:close()
  return nil
end

---Display the frame, enableAll.
---@param ignore_ss? boolean Ignore saving screen behind frame
function tgl.Frame:open(ignore_ss)
  checkArg(1,ignore_ss,"boolean","nil")
  if self.destroyed then return false end
  self.hidden=false
  if not ignore_ss and not self.ss then self.ss=tgl.ScreenSave:new(self.size2) end
  self:render()
  self:enableAll()
end
---Closes frame and disableAll. If screensave was stored, displayes saved screen
function tgl.Frame:close()
  self.hidden=true
  self:disableAll()
  if self.ss then self.ss:render() self.ss=nil end
end

---Display the frame, enableAll.
---if object has `ignoreOpen=true`, then it is not opened recursively
---@param ignore_ss? boolean Ignore saving screen behind frame
function tgl.Frame:openAll(ignore_ss)
  checkArg(1,ignore_ss,"boolean","nil")
  if self.destroyed then return false end
  self.hidden=false
  if not ignore_ss and not self.ss then self.ss=tgl.ScreenSave:new(self.size2) end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] and not object.ignoreOpen then object:open() end
    end
  end
  self:render()
  self:enableAll()
end
---Closes frame and disableAll. If screensave was stored, displayes saved screen
function tgl.Frame:closeAll()
  self.hidden=true
  self:disableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] then object:close() end
    end
  end
  if self.ss then self.ss:render() self.ss=nil end
end

---Scrollable Frame
---@class tgl.ScrollFrame:tgl.Frame
---@field showScroll boolean show scrollbar when maxScroll>0 (default=true)
---@field scroll integer current scroll position
---@field maxScroll integer max scroll value (set by caller)
---@field enabled boolean
---@field _scrollbar tgl.Scrollbar|nil
---@field scrollcol2 tgl.Color2 col2 for scrollbar (fg=thumb, bg=track)
tgl.ScrollFrame=setmetatable({},{__index=tgl.Frame})
tgl.ScrollFrame.__index=tgl.ScrollFrame
---@param objects table<string|integer, tgl.BoxObject|tgl.LineObject|tgl.UIObject>
---@param size2 tgl.Size2
---@param col2? tgl.Color2
---@param scrollcol2? tgl.Color2 scrollbar col2 (fg=thumb, bg=track)
---@return tgl.ScrollFrame
function tgl.ScrollFrame:new(objects,size2,col2,scrollcol2)
  checkArg(1,objects,"table","nil")
  checkArg(2,size2,"table","nil")
  checkArg(3,col2,"table","nil")
  checkArg(4,scrollcol2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="ScrollFrame"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.z_index=0
  obj.objects=objects or {}
  for _,object in pairs(obj.objects) do
    if not canOwn(obj,object) then return nil end
  end
  obj.size2=size2 or tgl.Size2:newFromSize(1,1,10,10)
  obj.col2=col2 or tgl.sys.themeColor("input")
  obj.scrollcol2=scrollcol2 or tgl.sys.themeColor("scrollbar")
  obj.scrollTrackChar=tgl.sys.themeChar("scrollbarTrack")
  obj.scrollThumbChar=tgl.sys.themeChar("scrollbarThumb")
  obj.showScroll=true
  obj.maxScroll=5
  obj.scroll=0
  obj._scrollbar=nil
  obj.enabled=false
  obj:translate()
  return obj
end
function tgl.ScrollFrame:translate()
  for _,object in pairs(self.objects) do
    if object.type then
      object._parentFrame=self
      if object.size2 then
        if not object.relsize2 then
          object.relsize2=tgl.Size2:newFromPoint(object.size2.x1,object.size2.y1,object.size2.x2,object.size2.y2)
        end
        local newPos=tgl.Pos2:new(object.relsize2.x1+self.size2.x1-1,object.relsize2.y1+self.size2.y1-1)
        if newPos then
          object:moveToPos2(newPos)
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"ScrollFrame/translate")
        end
      else
        if not object.relpos2 then object.relpos2=object.pos2 end
        local t_pos2=object.relpos2
        if t_pos2 then
          object.pos2=tgl.Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1)
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"ScrollFrame/translate")
        end
      end
    end
  end
end

function tgl.ScrollFrame:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return false end
  local r=tgl.sys.renderer
  local scrollActive=self.showScroll and self.maxScroll>0
  if scrollActive then
    if not self._scrollbar then
      self._scrollbar=tgl.Scrollbar:new(
        tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,self.size2.sizeY),
        self.scrollcol2)
      if self.enabled then self._scrollbar:enable() end
    end
    self._scrollbar.size2:moveToPos2(tgl.Pos2:new(self.size2.x2,self.size2.y1))
    self._scrollbar.owner=self
    self._scrollbar.col2=self.scrollcol2
    self._scrollbar.trackChar=self.scrollTrackChar
    self._scrollbar.thumbChar=self.scrollThumbChar
    self._scrollbar.inputContext=self.inputContext
    self._scrollbar.focused=self.focused
    self._scrollbar.focusCol2=self.focusCol2
    self._scrollbar.hitArea=self.size2
    self._scrollbar.z_index=self.z_index
    self._scrollbar.maxScroll=self.maxScroll
    self._scrollbar.visibleSize=self.size2.sizeY
    self._scrollbar.scroll=self.scroll
    self._scrollbar.onChange=function(s)
      self.scroll=s
      self:render()
    end
  else
    if self._scrollbar then
      self._scrollbar:destroy()
      self._scrollbar=nil
    end
    self.scroll=0
  end
  local contentX2=scrollActive and self.size2.x2-1 or self.size2.x2
  local contentSize2=scrollActive
    and tgl.Size2:newFromPoint(self.size2.x1,self.size2.y1,contentX2,self.size2.y2)
    or self.size2
  if self.gradient then
    r:withClip(contentSize2,r.gradient,r,self.size2,self.gradient,col2,self.z_index)
  else r:fill(contentSize2," ",col2,self.z_index) end
  for _,object in pairs(self.objects) do
    if object.type then
      if not object.relativeZ then object.relativeZ=object.z_index end
      object.z_index=self.z_index+object.relativeZ
      if object.relpos2 then
        if object.relpos2.y>self.scroll and object.relpos2.y<=self.size2.sizeY+self.scroll then
          object.pos2=tgl.Pos2:new(object.relpos2.x+self.size2.x1-1,object.relpos2.y+self.size2.y1-self.scroll-1)
          r:withClip(contentSize2,object.render,object)
        end
      elseif object.relsize2 then
        local absX=object.relsize2.x1+self.size2.x1-1
        local absY=object.relsize2.y1+self.size2.y1-self.scroll-1
        if absY+object.relsize2.sizeY-1>=self.size2.y1 and absY<=self.size2.y2 then
          object:moveToPos2(tgl.Pos2:new(absX,absY))
          r:withClip(contentSize2,object.render,object)
        end
      else
        tgl.util.log("Corrupted object(no relpos2/relsize2): "..object.type,"ScrollFrame/render")
        tgl.util.objectInfo(object)
      end
    end
  end
  if scrollActive then self._scrollbar:render() end
end

function tgl.ScrollFrame:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  if self._scrollbar then self._scrollbar:enable() end
end
function tgl.ScrollFrame:disable()
  self.enabled=false
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  if self._scrollbar then self._scrollbar:disable() end
end

function tgl.ScrollFrame:keyDown(char,code)
  if self._scrollbar then return self._scrollbar:keyDown(char,code) end
  return false
end
function tgl.ScrollFrame:enableAll()
  if self.destroyed then return false end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
      if tgl.sys.enableAllTypes[object.type] then object:enableAll() end
    end
  end
end
function tgl.ScrollFrame:disableAll()
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:disable() end
      if tgl.sys.enableAllTypes[object.type] then object:disableAll() end
    end
  end
end
---Add an object to frame(with translating)
---@param object tgl.UIObject
---@param name? string
---@return boolean
function tgl.ScrollFrame:add(object,name)
  return tgl.Frame.add(self,object,name)
end
---Remove (and disable) an object
---@param elem integer|string object name
function tgl.ScrollFrame:remove(elem)
  return tgl.Frame.remove(self,elem)
end
---Display the frame, enableAll.
---if object has `ignoreOpen=true`, then it is not opened recursively
---@param ignore_ss? boolean Ignore saving screen behind frame
function tgl.ScrollFrame:open(ignore_ss)
  checkArg(1,ignore_ss,"boolean","nil")
  if self.destroyed then return false end
  self.hidden=false
  if not ignore_ss and not self.ss then self.ss=tgl.ScreenSave:new(self.size2) end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] and not object.ignoreOpen then object:open() end
    end
  end
  self:render()
  self:enableAll()
end
---Closes frame and disableAll. If screensave was stored, displayes saved screen
function tgl.ScrollFrame:close()
  self.hidden=true
  self:disableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] then object:close() end
    end
  end
  if self.ss then self.ss:render() self.ss=nil end
end
for _,class in ipairs({tgl.Text,tgl.MultiText,tgl.Button,tgl.InputField,tgl.Scrollbar,
  tgl.TextBox,tgl.InputBox,tgl.Frame,tgl.ScrollFrame}) do
  tgl.sys.wrapRender(class)
end
return tgl end
