local unicode=require("unicode")
local thread=require("thread")
local event=require("event")
return function(tgl)
---Base for TGL UI objects
---@class tgl.UIObject
---@field type string
---@field z_index integer
---@field hidden boolean if object is hidden
---@field new function(self,...):UIObject Constructor
---@field render function Render function
tgl.UIObject={}
tgl.UIObject.__index=tgl.UIObject

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
  local obj=setmetatable({},self)
  obj.type="Text"
  obj.z_index=0
  obj.text=text
  obj.col2=col2 or tgl.Color2:new()
  obj.pos2=pos2 or nil --Intended: pos2 can be nil, text will displayed on current cursor pos
  obj.maxLength=-1
  obj.vertical=false
  return obj
end

---@param nextLine? boolean change to next line after rendering
function tgl.Text:render(nextLine)
  local r=tgl.sys.renderer
  if self.maxLength>=0 then
    if unicode.wlen(self.text)>self.maxLength then
      if self.maxLength>4 then
        self.text=unicode.sub(self.text,1,self.maxLength-2)..".."
      else
        self.text=unicode.sub(self.text,1,self.maxLength)
      end
    end
  end
  if self.hidden then return end
  if not self.pos2 then
    local text=self.text
    if nextLine then text=text.."\n" end
    r:set(tgl.getCurrentPos2(),text,self.col2,self.z_index,self.vertical)
    return
  end
  if self.maxLength>4 then
    r:set(self.pos2,string.rep(" ",self.maxLength),self.col2,self.z_index,self.vertical)
  end
  r:set(self.pos2,self.text,self.col2,self.z_index,self.vertical)
  return
end
---Clear text field and render new text
function tgl.Text:updateText(text)
  self.text=tostring(text)
  self:render()
end

---A special object to store multiple Text objects and render at same time
---@class tgl.MultiText:tgl.UIObject
---@field objects tgl.Text[]
---@field pos2 tgl.Pos2
tgl.MultiText={}
tgl.MultiText.__index=tgl.MultiText
---@param objects tgl.Text[]
---@param pos2? tgl.Pos2
---@return tgl.MultiText|tgl.UIObject
function tgl.MultiText:new(objects,pos2)
  if type(objects)=="table" then
    local obj=setmetatable({},self)
    obj.type="MultiText"
    obj.z_index=0
    obj.objects={}
    for k,object in pairs(objects) do
      if type(object)=="table" then
        if object.type=="Text" then
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
  if self.hidden then return end
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
  ---@type tgl.Button
  local obj=setmetatable({},self)
  obj.type="Button"
  obj.z_index=0
  obj.text=text or "[New Button]"
  if type(callback)~="function" then
  	callback=function() tgl.util.log("Empty Button!","Button/callback") end
  end
  obj.enabled=false
  obj.callback=callback
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.col2=color2 or tgl.Color2:new()
  obj.checkRendered=true -- check if button is on screen
  obj.handler=function (_,_,x,y,b)
    if x>=obj.pos2.x
    and x<obj.pos2.x+unicode.wlen(obj.text)
    and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.text=="" then return end
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(obj.pos2.x,obj.pos2.y)>obj.z_index then return end
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
    if obj.hidden or not obj.enabled then return end
    obj:disable()
    obj._clicking=true
    local prev=obj.col2
    obj.col2=tgl.Color2:new(obj.col2[2],obj.col2[1])
    obj:render()
    obj.col2=prev
    os.sleep(.05)
    if obj._clicking and not obj.hidden then
      obj._clicking=nil
      obj:render()
      obj:enable()
    end
    obj._clicking=nil
  end
  return obj
end
function tgl.Button:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  event.listen("touch",self.handler)
end
function tgl.Button:disable()
  self.enabled=false
  self._clicking=nil  --cancel any pending onClick restore
  event.ignore("touch",self.handler)
end
function tgl.Button:render()
  if self.hidden then return end
  tgl.sys.renderer:set(self.pos2,self.text,self.col2,self.z_index)
end

---Makes a Button which fires an eventName event with callValue value
---@param text string
---@param eventName string Event name to push
---@param callValue? any Value to push event with
---@param pos2 tgl.Pos2?
---@param col2 tgl.Color2?
---@return Button
function tgl.EventButton(text,eventName,callValue,pos2,col2)
  local obj=tgl.Button:new(text,function()end,pos2,col2)
  obj.eventName=eventName
  obj.callValue=callValue
  obj.handler=function(_,_,x,y)
    if x>=obj.pos2.x
    and x<obj.pos2.x+unicode.wlen(obj.text)
    and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(obj.pos2.x,obj.pos2.y)>obj.z_index then return end
      end
      if type(obj.onClick)=="function" then
        thread.create(obj.onClick):detach()
      end
      event.push(obj.eventName,obj.callValue)
    end
  end
  obj.callback=nil
  return obj
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
  ---@type tgl.InputField
  local obj=setmetatable({},self)
  obj.type="InputField"
  obj.z_index=0
  obj.text=""
  obj.secret=false
  obj.defaultText=text or "[______]"
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.col2=col2 or tgl.Color2:new()
  obj.eventName="InputEvent"
  obj.checkRendered=true
  obj.charCol2=tgl.Color2:new(0,tgl.defaults.colors16["lime"])
  obj.erase=true
  obj.stopOnClickOutside=false
  obj.handler=function (_,_,x,y)
    local textLen=unicode.wlen(obj.text)
    if textLen==0 then textLen=unicode.wlen(obj.defaultText) end
    if x>=obj.pos2.x and x<obj.pos2.x+textLen and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if tgl.sys.renderer:getZ(obj.pos2.x,obj.pos2.y)>obj.z_index then return end
      end
      obj:disable()
      obj:input()
      event.push(obj.eventName,obj.text)
      obj:enable()
    end
  end
  return obj
end
---InputField input function
function tgl.InputField:input()
  local r=tgl.sys.renderer
  local printChar=tgl.Text:new(" ",self.charCol2)
  local _prevAA=tgl.sys.getActiveArea()
  tgl.sys.setActiveArea(tgl.Size2:newFromPos2(self.pos2,tgl.Pos2:new(self.pos2.x+unicode.wlen(self.text),self.pos2.y)))
  local offsetX=0
  if self.erase then
    if self.text=="" then r:fill(tgl.Size2:new(self.pos2.x,self.pos2.y,unicode.wlen(self.defaultText)+1,1)," ",self.col2,self.z_index)
    else r:fill(tgl.Size2:new(self.pos2.x,self.pos2.y,unicode.wlen(self.text)+1,1)," ",self.col2,self.z_index) end
    self.text=""
  else
    if self.text=="" then r:fill(tgl.Size2:new(self.pos2.x,self.pos2.y,unicode.wlen(self.defaultText)+1,1)," ",self.col2,self.z_index) offsetX=0
    else offsetX=unicode.wlen(self.text) end
  end
  ---@private
  local function printChr()
    printChar.pos2=tgl.Pos2:new(self.pos2.x+offsetX,self.pos2.y)
    printChar.z_index=self.z_index
    printChar:render()
  end
  printChr()
  local _pull={"interrupted","key_down"}
  if self.stopOnClickOutside then table.insert(_pull,"touch") end
  while true do
    local id,_,a,b=event.pullMultiple(table.unpack(_pull))
    if id=="touch" then
      if not (a>=self.pos2.x and a<self.pos2.x+unicode.wlen(self.defaultText) and b==self.pos2.y) then
        break
      end
    else
      local key=a
      if offsetX<0 then offsetX=0 tgl.util.log("Input going offbounds","InputField/input") end
      if key==tgl.defaults.keys.enter or key==tgl.defaults.keys.esc or id=="interrupted" then
        break
      elseif (key==tgl.defaults.keys.backspace or key==tgl.defaults.keys.delete) and unicode.wlen(self.text)>0 then
        local textLen=unicode.wlen(self.text)
        r:fill(tgl.Size2:new(self.pos2.x,self.pos2.y,textLen+1,1)," ",self.col2,self.z_index)
        offsetX=offsetX-unicode.charWidth(unicode.sub(self.text,textLen))
        self.text=unicode.sub(self.text,1,textLen-1)
        if textLen-1>0 then self:render()
        else r:fill(tgl.Size2:new(self.pos2.x,self.pos2.y,unicode.wlen(self.text)+1,1)," ",self.col2,self.z_index) end
        printChr()
      elseif key>=32 and key~=tgl.defaults.keys.delete then
        if unicode.wlen(self.text)+unicode.charWidth(key)<=unicode.wlen(self.defaultText) then
          self.text=self.text..unicode.char(key)
          self:render()
          offsetX=offsetX+unicode.charWidth(unicode.char(key))
          printChr()
        end
      end
    end
  end
  printChar.col2=self.col2
  printChr()
  self:render()
  if _prevAA then tgl.sys.setActiveArea(_prevAA) else tgl.sys.resetActiveArea() end
end
function tgl.InputField:render()
  if self.hidden then return false end
  local r=tgl.sys.renderer
  if self.text=="" then r:set(self.pos2,self.defaultText,self.col2,self.z_index)
  else
    if not self.secret then
      r:set(self.pos2,self.text,self.col2,self.z_index)
    else
      r:set(self.pos2,string.rep("*",unicode.wlen(self.text)),self.col2,self.z_index)
    end
  end
end
function tgl.InputField:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  event.listen("touch",self.handler)
end
function tgl.InputField:disable()
  self.enabled=false
  event.ignore("touch",self.handler)
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
  if type(size2)~="table" then return nil end
  local obj=setmetatable({},self)
  obj.type="Scrollbar"
  obj.z_index=0
  obj.size2=size2
  obj.col2=col2 or tgl.Color2:new(tgl.defaults.colors16.lightgray,tgl.defaults.colors16.darkgray)
  obj.scroll=0
  obj.maxScroll=0
  obj.scrollSpeed=1
  obj.visibleSize=size2.sizeY
  obj.hitArea=size2
  obj.onChange=nil
  obj.enabled=false
  obj.scrollHandler=function(_,_,x,y,dir)
    dir=dir*obj.scrollSpeed
    if obj.maxScroll<=0 then return end
    if not tgl.util.pointInSize2(x,y,obj.hitArea) then return end
    obj:setScroll(obj.scroll-dir)
  end
  obj.touchHandler=function(_,_,x,y)
    if obj.maxScroll<=0 then return end
    if not (x==obj.size2.x1 and y>=obj.size2.y1 and y<=obj.size2.y2) then return end
    local startY=y
    local startScroll=obj.scroll
    local trackH=obj.size2.sizeY
    while true do
      local id,_,_,dy=event.pullMultiple("drag","drop")
      if id=="drop" then break end
      obj:setScroll(startScroll+math.floor((dy-startY)*obj.maxScroll/trackH))
    end
  end
  return obj
end
---@param n integer
function tgl.Scrollbar:setScroll(n)
  self.scroll=math.max(0,math.min(self.maxScroll,n))
  if type(self.onChange)=="function" then self.onChange(self.scroll) end
  local r=tgl.sys.renderer
  r:stop()
  self:render()
  r:flush()
end
function tgl.Scrollbar:render()
  if self.hidden then return end
  local r=tgl.sys.renderer
  r:fill(self.size2," ",self.col2,self.z_index)
  if self.maxScroll>0 then
    local trackH=self.size2.sizeY
    local thumbH=math.max(1,math.floor(trackH*self.visibleSize/(self.visibleSize+self.maxScroll)))
    local thumbY=math.floor(self.scroll*(trackH-thumbH)/self.maxScroll)
    r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1+thumbY,1,thumbH),"█",self.col2,self.z_index)
  end
end
function tgl.Scrollbar:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  event.listen("scroll",self.scrollHandler)
  event.listen("touch",self.touchHandler)
end
function tgl.Scrollbar:disable()
  self.enabled=false
  event.ignore("scroll",self.scrollHandler)
  event.ignore("touch",self.touchHandler)
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
  if not text or type(size2)~="table" then return nil end
  local obj=setmetatable({},self)
  obj.type="TextBox"
  obj.z_index=0
  obj.tabSize=2
  obj.showScroll=true
  obj.viewY=0
  obj.text=text
  obj.size2=size2
  obj.col2=col2 or tgl.defaults.colors2.white
  obj.enabled=false
  obj._scrollbar=nil
  return obj
end
function tgl.TextBox:render()
  if self.hidden then return end
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
      if self.enabled then self._scrollbar:disable() end
      self._scrollbar=nil
    end
    self.viewY=0
  end
  local fillSize=scrollActive
    and tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,maxW,maxH)
    or self.size2
  r:fill(fillSize," ",self.col2,self.z_index)
  local tabRepl=string.rep(" ",self.tabSize)
  local y=self.size2.y1
  local lineN=0
  for line in (self.text.."\n"):gmatch("([^\n]*)\n") do
    lineN=lineN+1
    if lineN>self.viewY then
      if y>self.size2.y2 then break end
      line=line:gsub("\t",tabRepl)
      if unicode.wlen(line)>maxW then line=unicode.sub(line,1,maxW) end
      if #line>0 then r:set(tgl.Pos2:new(self.size2.x1,y),line,self.col2,self.z_index) end
      y=y+1
    end
  end
  if scrollActive then self._scrollbar:render() end
end
function tgl.TextBox:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  if self._scrollbar then self._scrollbar:enable() end
end
function tgl.TextBox:disable()
  self.enabled=false
  if self._scrollbar then self._scrollbar:disable() end
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
  if not text or type(size2)~="table" then return nil end
  local obj=setmetatable({},self)
  obj.type="InputBox"
  obj.z_index=0
  obj.text=text
  obj.size2=size2
  obj.col2=col2 or tgl.defaults.colors2.white
  obj.tabSize=2
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
      event.push(obj.eventName,obj.text)
      if not obj._keepDisabled then obj:enable() end
      obj._keepDisabled=nil
    end
  end
  return obj
end
function tgl.InputBox:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  event.listen("touch",self.handler)
  if self._scrollbar then self._scrollbar:enable() end
end
function tgl.InputBox:disable()
  self.enabled=false
  if self._inputActive then
    event.push(self.stopEventName)
    self._keepDisabled=true
  end
  event.ignore("touch",self.handler)
  if self._scrollbar then self._scrollbar:disable() end
end
function tgl.InputBox:render()
  if self.hidden then return end
  local r=tgl.sys.renderer
  local maxH=self.size2.sizeY
  local tabRepl=string.rep(" ",self.tabSize)

  if self.wrap then
    local lines={}
    for l in (self.text.."\n"):gmatch("([^\n]*)\n") do lines[#lines+1]=l end
    local lnw=self.lineNumbers and (#tostring(#lines)+1) or 0
    local lnCol2=lnw>0 and (self.lineNumCol2 or tgl.Color2:new(tgl.defaults.colors16.darkgray,self.col2[2])) or nil
    local function buildVL(mw)
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
    local mw=self.size2.sizeX-lnw
    local vlines=buildVL(mw)
    local scrollActive=self.showScroll and #vlines>maxH
    if scrollActive then
      mw=self.size2.sizeX-lnw-1
      vlines=buildVL(mw)
    end
    if scrollActive then
      if not self._scrollbar then
        self._scrollbar=tgl.Scrollbar:new(
          tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,maxH))
        if self.enabled then self._scrollbar:enable() end
      end
      self._scrollbar.size2:moveToPos2(tgl.Pos2:new(self.size2.x2,self.size2.y1))
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
        if self.enabled then self._scrollbar:disable() end
        self._scrollbar=nil
      end
      self.viewY=0
    end
    if lnw>0 then
      r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,lnw,maxH)," ",lnCol2,self.z_index)
    end
    local textX=self.size2.x1+lnw
    local textW=scrollActive and mw or (self.size2.sizeX-lnw)
    r:fill(tgl.Size2:newFromSize(textX,self.size2.y1,textW,maxH)," ",self.col2,self.z_index)
    local y=self.size2.y1
    for vi=self.viewY+1,#vlines do
      if y>self.size2.y2 then break end
      local vl=vlines[vi]
      if lnw>0 then
        local numStr=vl.startVC==0 and string.format("%"..(lnw-1).."d ",vl.li) or string.rep(" ",lnw)
        r:set(tgl.Pos2:new(self.size2.x1,y),numStr,lnCol2,self.z_index)
      end
      if #vl.text>0 then
        r:set(tgl.Pos2:new(textX,y),vl.text,self.col2,self.z_index)
      end
      y=y+1
    end
    if scrollActive then self._scrollbar:render() end
    return
  end

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
      if self.enabled then self._scrollbar:disable() end
      self._scrollbar=nil
    end
    self.viewY=0
  end
  local lnw=self.lineNumbers and (#tostring(lineCount)+1) or 0
  local lnCol2=lnw>0 and (self.lineNumCol2 or tgl.Color2:new(tgl.defaults.colors16.darkgray,self.col2[2])) or nil
  local textMaxW=maxW-lnw
  local textX=self.size2.x1+lnw
  if lnw>0 then
    r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,lnw,maxH)," ",lnCol2,self.z_index)
  end
  local textW=scrollActive and textMaxW or (self.size2.sizeX-lnw)
  r:fill(tgl.Size2:newFromSize(textX,self.size2.y1,textW,maxH)," ",self.col2,self.z_index)
  local y=self.size2.y1
  local lineN=0
  for line in (self.text.."\n"):gmatch("([^\n]*)\n") do
    lineN=lineN+1
    if lineN>self.viewY then
      if y>self.size2.y2 then break end
      if lnw>0 then
        r:set(tgl.Pos2:new(self.size2.x1,y),string.format("%"..(lnw-1).."d ",lineN),lnCol2,self.z_index)
      end
      line=line:gsub("\t",tabRepl)
      if unicode.wlen(line)>textMaxW then line=unicode.sub(line,1,textMaxW) end
      if #line>0 then r:set(tgl.Pos2:new(textX,y),line,self.col2,self.z_index) end
      y=y+1
    end
  end
  if scrollActive then self._scrollbar:render() end
end
function tgl.InputBox:input(startX,startY)
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
  if self.clearOnClick then
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
    local lnCol2=lnw>0 and (self.lineNumCol2 or tgl.Color2:new(tgl.defaults.colors16.darkgray,self.col2[2])) or nil
    local textX=self.size2.x1+lnw
    if lnw>0 then
      r:fill(tgl.Size2:newFromSize(self.size2.x1,self.size2.y1,lnw,maxH)," ",lnCol2,self.z_index)
    end
    local textW=self._scrollbar and maxW or (self.size2.sizeX-lnw)
    r:fill(tgl.Size2:newFromSize(textX,self.size2.y1,textW,maxH)," ",self.col2,self.z_index)
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
          r:set(tgl.Pos2:new(textX,self.size2.y1+i-1),vl.text,self.col2,self.z_index)
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
          r:set(tgl.Pos2:new(textX,self.size2.y1+i-1),line,self.col2,self.z_index)
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

  local function updateScrollbar()
    local totalRows=self.wrap and #vlines or #lines
    local needScroll=self.showScroll and totalRows>maxH
    if needScroll then
      if not self._scrollbar then
        self._scrollbar=tgl.Scrollbar:new(
          tgl.Size2:newFromSize(self.size2.x2,self.size2.y1,1,maxH))
        self._scrollbar.hitArea=self.size2
        self._scrollbar.z_index=self.z_index
        event.listen("scroll",self._scrollbar.scrollHandler)
        if self.wrap then vlines=buildVL() totalRows=#vlines end
      end
      self._scrollbar.maxScroll=math.max(0,totalRows-maxH)
      self._scrollbar.visibleSize=maxH
      self._scrollbar.scroll=self.viewY
      self._scrollbar.onChange=function(s)
        self.viewY=s ensureVisible() renderEdit()
      end
    else
      if self._scrollbar then
        event.ignore("scroll",self._scrollbar.scrollHandler)
        self._scrollbar=nil
        if self.wrap then vlines=buildVL() end
        self.viewY=0
      end
    end
  end

  --re-register scroll handler (disable() removed it; touch handled inline below)
  if self._scrollbar then
    event.listen("scroll",self._scrollbar.scrollHandler)
    self._scrollbar.onChange=function(s) self.viewY=s ensureVisible() renderEdit() end
  end

  updateScrollbar()
  ensureVisible()
  renderEdit()

  self._inputActive=true
  while true do
    local id,_,a1,a2=event.pullMultiple("interrupted","key_down","touch",self.stopEventName)
    if id=="interrupted" or id==self.stopEventName then break end

    if id=="touch" then
      local tx,ty=a1,a2
      if self._scrollbar and tx==self._scrollbar.size2.x1
      and ty>=self._scrollbar.size2.y1 and ty<=self._scrollbar.size2.y2 then
        local startScroll=self._scrollbar.scroll
        local trackH=self._scrollbar.size2.sizeY
        while true do
          local did,_,_,dy=event.pullMultiple("drag","drop")
          if did=="drop" then break end
          self._scrollbar:setScroll(startScroll+math.floor((dy-ty)*self._scrollbar.maxScroll/trackH))
        end
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
      end
    else  --key_down
      local key,key2=a1,a2
      if key==tgl.defaults.keys.esc then
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
  end

  if self._scrollbar then
    event.ignore("scroll",self._scrollbar.scrollHandler)
    self._scrollbar.onChange=nil
  end
  self._inputActive=nil
  self.text=table.concat(lines,"\n")
  r:stop()
  self:render()  --preserves self.viewY, re-arms onChange for non-edit scrolling
  r:flush()
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
  if type(objects)~="table" or type(size2)~="table" then return nil end
  local obj=setmetatable({},self)
  obj.type="Frame"
  obj.z_index=0
  obj.objects=objects
  obj.size2=size2
  obj.col2=col2 or tgl.Color2:new()
  obj.borderType="inline"
  --translate objects
  obj:translate()
  return obj
end
---move objects from relative positions to absolute ones in frame(TODO REWORK)
function tgl.Frame:translate()
  for _,object in pairs(self.objects) do
    if object.type then
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
  if self.hidden then return false end
  local r=tgl.sys.renderer
  local s=self.size2
  local col2=self.col2
  local z=self.z_index
  --frame
  r:fill(s," ",col2,z)
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
      object:render()
    end
  end
end
---Move frame and all its contents
---@param pos2 tgl.Pos2
function tgl.Frame:moveToPos2(pos2)
  if not pos2 then return false end
  self.size2:moveToPos2(pos2)
  self:translate()
end
---Render only a specific region of the frame
---@param clipRegion tgl.Size2
function tgl.Frame:renderRegion(clipRegion)
  if self.hidden then return false end
  if not clipRegion or clipRegion.type~="Size2" then return false end
  local r=tgl.sys.renderer
  local oldClip=r:getClipRegion()
  r:setClipRegion(clipRegion)
  self:render()
  r:setClipRegion(oldClip)
  return true
end
function tgl.Frame:enableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
      if tgl.sys.enableAllTypes[object.type] then object:enableAll() end
    end
  end
end
function tgl.Frame:disableAll()
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
  if object.type then
    if not name then
      table.insert(self.objects,object)
    else
      self.objects[name]=object
    end
    self:translate()
    return true
  end
  return false
end
---Remove (and disable) an object
---@param elem integer|string object name
function tgl.Frame:remove(elem)
  if self.objects[elem] then
    if tgl.sys.enableTypes[self.objects[elem].type] then
      self.objects[elem]:disable()
    end
    if tgl.sys.enableAllTypes[self.objects[elem].type] then
      self.objects[elem]:disableAll()
    end
    self.objects[elem]=nil
  end
end

---Saves a box from screen(TODO:REWORK)
---@class tgl.ScreenSave:tgl.BoxObject
---@field data table
---@field buf integer|nil
---@field save function
---@field dump function
tgl.ScreenSave=setmetatable({},{__index=tgl.BoxObject})
tgl.ScreenSave.__index=tgl.ScreenSave
---Save the chars from `self.size2` region to `self.data`
function tgl.ScreenSave:save(useBuffer)
  local r=tgl.sys.renderer
  if useBuffer then
    local success,buf=r:allocateBuffer(self.size2.sizeX,self.size2.sizeY)
    if success then
      self.buf=buf
      r:bufcopy(0,buf,tgl.Size2:new(1,1,self.size2.sizeX,self.size2.sizeY),self.z_index,self.size2.pos1)
      return
    end
  end
  for x=self.size2.x1,self.size2.x2 do
    self.data[x]={}
    for y=self.size2.y1,self.size2.y2 do
      local char,col2=r:getPoint(x,y)
      self.data[x][y]={char,col2}
    end
  end
end
---Save an area from screen
---@param size2 tgl.Size2
---@param useBuffer? boolean
---@return tgl.ScreenSave
function tgl.ScreenSave:new(size2,useBuffer)
  if not size2 then size2=tgl.Size2:newFromPoint(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY) end
  if not useBuffer then useBuffer=true end
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
  if self.buf>0 then
    tgl.sys.renderer:freeBuffer(self.buf)
    self.buf=0
  end
end
function tgl.ScreenSave:render()
  local r=tgl.sys.renderer
  local z=self.z_index
  if self.buf>0 then --buffered copy
    r:bufcopy(self.buf,0,self.size2,self.z_index)
    r:freeBuffer(self.buf)
    r:resetCursor()
    return
  end
  local success,buf=r:allocateBuffer(self.size2.sizeX,self.size2.sizeY)
  if success then
    local buf_x=1
    local buf_y=1
    local ok=true
    for x=self.size2.x1,self.size2.x2 do
      for y=self.size2.y1,self.size2.y2 do
        if not self.data[x][y] then
          ok=false
          break
        end
        r:setPoint(buf_x,buf_y,self.data[x][y][1],self.data[x][y][2],z,false,buf)
        buf_y=buf_y+1
      end
      buf_y=1
      buf_x=buf_x+1
    end
    if ok then r:bufcopy(buf,0,self.size2,z) end
    r:freeBuffer(buf)
    r:resetCursor()
  else
    tgl.util.log("Using on-screen renderer(slow)","ScreenSave/render")
    for x=self.size2.x1,self.size2.x2 do
      for y=self.size2.y1,self.size2.y2 do
        r:setPoint(x,y,self.data[x][y][1],self.data[x][y][2],z)
      end
    end
  end
end
---Dump saved data to file
---@param filename? string default=`"screensave.st"`
---@return boolean
function tgl.ScreenSave:dump(filename)
  if not filename then filename="screensave.st" end
  local file=io.open(filename,"w")
  if not file then
    tgl.util.log("Couldn't open file: "..tostring(filename),"ScreenSave/dump")
    return false
  end
  file:write(require("serialization").serialize({self.size2.x1,self.size2.y1,self.size2.x2,self.size2.y2}))
  file:write("\n")
  file:write(require("serialization").serialize(self.data)):close()
  return true
end
function tgl.ScreenSave:load(filename)
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
        obj.size2=load_size2
        obj.data=data
        return obj
      end
    end
  end
  return nil
end

---Display the frame, enableAll.
---@param ignore_ss? boolean Ignore saving screen behind frame
function tgl.Frame:open(ignore_ss)
  self.hidden=false
  if not ignore_ss then self.ss=tgl.ScreenSave:new(self.size2) end
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
  self.hidden=false
  if not ignore_ss then self.ss=tgl.ScreenSave:new(self.size2) end
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
  if self.ss then self.ss:render() self.ss=nil end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] then object:close() end
    end
  end
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
  local obj=setmetatable({},self)
  obj.type="ScrollFrame"
  obj.z_index=0
  obj.objects=objects or {}
  obj.size2=size2 or tgl.Size2:newFromSize(1,1,10,10)
  obj.col2=col2 or tgl.defaults.colors2.white
  obj.scrollcol2=scrollcol2 or tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightgray)
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
  if self.hidden then return false end
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
      if self.enabled then self._scrollbar:disable() end
      self._scrollbar=nil
    end
    self.scroll=0
  end
  local contentX2=scrollActive and self.size2.x2-1 or self.size2.x2
  local contentSize2=scrollActive
    and tgl.Size2:newFromPoint(self.size2.x1,self.size2.y1,contentX2,self.size2.y2)
    or self.size2
  r:fill(contentSize2," ",self.col2,self.z_index)
  local prevClip=r:getClipRegion()
  r:setClipRegion(contentSize2)
  for _,object in pairs(self.objects) do
    if object.type then
      if object.relpos2 then
        if object.relpos2.y>self.scroll and object.relpos2.y<=self.size2.sizeY+self.scroll then
          object.pos2=tgl.Pos2:new(object.relpos2.x+self.size2.x1-1,object.relpos2.y+self.size2.y1-self.scroll-1)
          object:render()
        end
      elseif object.relsize2 then
        local absX=object.relsize2.x1+self.size2.x1-1
        local absY=object.relsize2.y1+self.size2.y1-self.scroll-1
        if absY+object.relsize2.sizeY-1>=self.size2.y1 and absY<=self.size2.y2 then
          object:moveToPos2(tgl.Pos2:new(absX,absY))
          object:render()
        end
      else
        tgl.util.log("Corrupted object(no relpos2/relsize2): "..object.type,"ScrollFrame/render")
        tgl.util.objectInfo(object)
      end
    end
  end
  r:setClipRegion(prevClip)
  if scrollActive then self._scrollbar:render() end
end

function tgl.ScrollFrame:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  if self._scrollbar then self._scrollbar:enable() end
end
function tgl.ScrollFrame:disable()
  self.enabled=false
  if self._scrollbar then self._scrollbar:disable() end
end
function tgl.ScrollFrame:enableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
      if tgl.sys.enableAllTypes[object.type] then object:enableAll() end
    end
  end
end
function tgl.ScrollFrame:disableAll()
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
  if type(object)~="table" then return false end
  if object.type then
    if not name then
      table.insert(self.objects,object)
    else
      self.objects[name]=object
    end
    self:translate()
    return true
  end
  return false
end
---Remove (and disable) an object
---@param elem integer|string object name
function tgl.ScrollFrame:remove(elem)
  if self.objects[elem] then
    if tgl.sys.enableTypes[self.objects[elem].type] then
      self.objects[elem]:disable()
    end
    if tgl.sys.enableAllTypes[self.objects[elem].type] then
      self.objects[elem]:disableAll()
    end
    self.objects[elem]=nil
  end
end
---Display the frame, enableAll.
---if object has `ignoreOpen=true`, then it is not opened recursively
---@param ignore_ss? boolean Ignore saving screen behind frame
function tgl.ScrollFrame:open(ignore_ss)
  self.hidden=false
  if not ignore_ss then self.ss=tgl.ScreenSave:new(self.size2) end
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
  if self.ss then self.ss:render() self.ss=nil end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] then object:close() end
    end
  end
end
return tgl end