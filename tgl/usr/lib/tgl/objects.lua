local unicode=require("unicode")
local thread=require("thread")
local event=require("event")
local term=require("term")
local gpu=require("component").gpu
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


---Single line text object
---@class tgl.Text:tgl.LineObject
---@field text string
---@field maxLength integer Max text length, -1 for unlimeted
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
    r:set(tgl.getCurrentPos2(),text,self.col2,self.z_index)
    return
  end
  if self.maxLength>4 then
    r:set(self.pos2,string.rep(" ",self.maxLength),self.col2,self.z_index)
  end
  gpu.set(self.pos2.x,self.pos2.y,self.text,self.col2,self.z_index)
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
  obj.handler=function (_,_,x,y)
    if x>=obj.pos2.x
    and x<obj.pos2.x+unicode.wlen(obj.text)
    and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if self.text=="" then return end
      if obj.checkRendered then
        if tgl.util.getLineMatched(obj.pos2,obj.text,obj.col2)/unicode.wlen(obj.text)<0.6 then
          return
        end
      end
      if type(obj.onClick)=="function" then
        thread.create(obj.onClick):detach()
      end
      local success,err=pcall(obj.callback)
      if not success then
        tgl.util.log("Button handler error: "..err,"Button/handler")
      end
    end
  end
  obj.onClick=function()
    obj:disable()
    local invert=tgl.Color2:new(obj.col2[2],obj.col2[1])
    local prev=obj.col2
    obj.col2=invert
    obj:render()
    obj.col2=prev
    os.sleep(.1)
    obj:render()
    obj:enable()
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
---@param pos2 Pos2?
---@param col2 Color2?
---@return Button
function tgl.EventButton(text,eventName,callValue,pos2,col2)
  local obj=Button:new(text,function()end,pos2,col2)
  obj.eventName=eventName
  obj.callValue=callValue
  obj.handler=function(_,_,x,y)
    if x>=obj.pos2.x
    and x<obj.pos2.x+unicode.wlen(obj.text)
    and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if tgl.util.getLineMatched(obj.pos2,obj.text,obj.col2)/unicode.wlen(obj.text)<0.6 then
          return
        end
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
  obj.handler=function (_,_,x,y)
    local textLen=unicode.wlen(obj.text)
    if textLen==0 then textLen=unicode.wlen(obj.defaultText) end
    if x>=obj.pos2.x and x<obj.pos2.x+textLen and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered then
        if unicode.wlen(obj.text)>0 then
          if tgl.util.getLineMatched(obj.pos2,obj.text)/textLen<1.0 then
            tgl.util.log(tgl.util.getLineMatched(obj.pos2,obj.text).." "..obj.text.." "..tgl.util.getLine(obj.pos2,textLen),"DIF/handler")
            return
          end
        else
          if tgl.util.getLineMatched(obj.pos2,obj.defaultText)/textLen<1.0 then
            tgl.util.log(tgl.util.getLineMatched(obj.pos2,obj.defaultText).." "..obj.text.." "..tgl.util.getLine(obj.pos2,textLen),"DIF/handler")
            return
          end
        end
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
  tgl.sys.setActiveArea(tgl.Size2:newFromPos2(self.pos2,Pos2:new(self.pos2.x+unicode.wlen(self.text),self.pos2.y)))
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
    printChar:render()
  end
  printChr()
  while true do
    local id,_,key,key2=event.pullMultiple("interrupted","key_down")
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
  printChar.col2=self.col2
  printChr()
  self:render()
  tgl.sys.resetActiveArea()
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

---2D Text
---@class tgl.TextBox:tgl.BoxObject
---@field text string
tgl.TextBox=setmetatable({},{__index=tgl.BoxObject})
tgl.TextBox.__index=tgl.TextBox
---@param text string
---@param size2 tgl.Size2
---@param col2? tgl.Color2
function tgl.TextBox:new(text,size2,col2)
  if not text or type("size2")~="table" then return nil end
  local obj=setmetatable({},self)
  obj.type="TextBox"
  obj.z_index=0
  obj.text=text
  obj.size2=size2
  obj.col2=col2 or tgl.defaults.colors2.white
  return obj
end
function tgl.TextBox:render()
  tgl.sys.renderer:fill(self.size2," ",self.col2,self.z_index)
  tgl.sys.renderer:set(self.size2.pos1,self.text,self.col2,self.z_index)--!
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
      if object.type~="Frame" and object.type~="ScrollFrame" then
        if not object.relpos2 then object.relpos2=object.pos2 end
        local t_pos2=object.relpos2
        if t_pos2 then
          object.pos2=tgl.Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1) --offset
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"Frame/translate")
        end
      else ---WIP
        if not object.relsize2 then object.relsize2=tgl.Size2:newFromPos2(object.size2.pos1,object.size2.pos2) end
        local t_pos2=object.relsize2.pos1
        if t_pos2 then
          object.size2:moveToPos2(tgl.Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1))
          object:translate() --test
        else
          tgl.util.log("Corrupted frame!","Frame/translate")
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
  --objects
  for _,object in pairs(self.objects) do
    if object.type then
      object:render()
    end
  end
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
      return
    end
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
---Move frame and all its contents
---@param pos2 tgl.Pos2
function tgl.Frame:moveToPos2(pos2)
  if not pos2 then return false end
  self.size2:moveToPos2(pos2)
  self:translate()
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
---@field save function
---@field dump function
tgl.ScreenSave=setmetatable({},{__index=tgl.BoxObject})
tgl.ScreenSave.__index=tgl.ScreenSave
---Save the chars from `self.size2` region to `self.data`
function tgl.ScreenSave:save()
  local r=tgl.sys.renderer
  for x=self.size2.x1,self.size2.x2 do
    self.data[x]={}
    for y=self.size2.y1,self.size2.y2 do
      local char,col2=r:getPoint(x,y)
      self.data[x][y]={char,col2}
    end
  end
end
function tgl.ScreenSave:new(size2)
  if not size2 then size2=tgl.Size2:newFromPoint(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY) end
  local obj=setmetatable({},tgl.ScreenSave)
  obj.z_index=10
  obj.size2=size2
  obj.data={}
  obj.type="ScreenSave"
  obj:save()
  return obj
end
function tgl.ScreenSave:render()
  local r=tgl.sys.renderer
  local z=self.z_index
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
        r:set(buf_x,buf_y,self.data[x][y][1],self.data[x][y][2],z,buf)
        buf_y=buf_y+1
      end
      buf_y=1
      buf_x=buf_x+1
    end
    if ok then r:bufcopy(buf,0,self.size2) end
    r:freeBuffer(buf)
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
---if object has `ignoreOpen=true`, then it is not opened recursively
---@param ignore_ss? boolean Ignore saving screen behind frame
function tgl.Frame:open(ignore_ss)
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
function tgl.Frame:close()
  self.hidden=true
  self:disableAll()
  if self.ss then self.ss:render() self.ss=nil end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] then object:close() end
    end
  end
end

---WIP Scrollable Frame
---@class tgl.ScrollFrame:tgl.Frame
---@field showScroll boolean NotImplemented: Show scrollbar(default=true)
---@field scroll integer Current scroll
---@field maxScroll integer
---@field isDragging boolean
---@field lastDragY integer
---@field handler function
---@field handleDragEvents function
---@field enable function
---@field disable function
---@field enabled boolean
---@field scrollbarCol2 tgl.Color2 Color2 of side scroller
tgl.ScrollFrame=setmetatable({},{__index=tgl.Frame})
tgl.ScrollFrame.__index=tgl.ScrollFrame
---@param objects table<string|integer, tgl.BoxObject|tgl.LineObject|tgl.UIObject>
---@param size2 tgl.Size2
---@param col2? tgl.Color2
---@param scrollcol2? tgl.Color2
---@return tgl.ScrollFrame
function tgl.ScrollFrame:new(objects,size2,col2,scrollcol2)
  local obj=setmetatable({},self)
  obj.type="ScrollFrame"
  obj.z_index=0
  obj.objects=objects or {}
  obj.size2=size2 or tgl.Size2:newFromSize(1,1,10,10)
  obj.col2=col2 or tgl.defaults.colors2.white
  obj.showScroll=true
  obj.maxScroll=5
  obj.scroll=0
  obj.scrollbarCol2=scrollcol2 or tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightgray)
  obj.isDragging=false

  obj.handler=function (id,_,x,y,scr)
    if id=="scroll" then
      if x>=obj.size2.x1 and x<=obj.size2.x2 and
        y>=obj.size2.y1 and y<=obj.size2.y2 then
        if obj.scroll-scr>=0 and obj.scroll-scr<=obj.maxScroll then
          obj.scroll=obj.scroll-scr
          obj:render()
        end
      end
    else
      if obj.showScroll and x==obj.size2.x2-1 and
      y>=obj.size2.y1 and y<=obj.size2.y2 then
        obj.isDragging=true
        obj.lastDragY=y
        obj:handleDragEvents()
      end
    end
  end
  obj.handleDragEvents=function()
    while obj.isDragging do
      local id,_,x,y=event.pullMultiple("drag","drop")
      if id=="drag" then
        -- Update scroll based on drag movement (ignore x, only use y)
        if obj.lastDragY then
          local delta_y=y-obj.lastDragY
          if delta_y~=0 then
            -- Convert screen drag to scroll amount
            local visible_height=obj.size2.sizeY
            local scroll_delta=math.floor(delta_y*obj.maxScroll/visible_height)
            local new_scroll=obj.scroll+scroll_delta
            obj.scroll=math.max(0,math.min(obj.maxScroll,new_scroll))
            obj:render()
          end
          obj.lastDragY = y
        end
      elseif id=="drop" then
        obj.isDragging=false
        obj.lastDragY=nil
        break
      end
    end
  end

  obj:translate()
  return obj
end
function tgl.ScrollFrame:translate()
  for _,object in pairs(self.objects) do
    if object.type then
      if object.type~="Frame" and object.type~="ScrollFrame" then
        if not object.relpos2 then object.relpos2=object.pos2 end
        local t_pos2=object.relpos2
        if t_pos2 then
          object.pos2=tgl.Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1) --offset
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"ScrollFrame/translate")
        end
      else
        if not object.relsize2 then object.relsize2=object.size2 end
        local t_pos2=object.size2.pos1
        if t_pos2 then
          object.size2:moveToPos2(tgl.Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1))
        else
          tgl.util.log("Corrupted frame!","ScrollFrame/translate")
        end
      end
    end
  end
end

function tgl.ScrollFrame:render()
  if self.hidden then return false end
  local r=tgl.sys.renderer
  --frame
  r:fill(self.size2," ",self.col2)
  --scrollbar
  if self.showScroll and self.maxScroll > 0 then
    local scrollbar_x = self.size2.x2-1
    -- Calculate scrollbar metrics
    local visible_height = self.size2.sizeY
    local total_height = visible_height + self.maxScroll
    local scrollbar_height = math.max(1, math.floor(visible_height * visible_height / total_height))
    local scrollbar_pos = math.floor(self.scroll * (visible_height - scrollbar_height) / self.maxScroll)
    r:fill(tgl.Size2:new(scrollbar_x,self.size2.y1,1,visible_height)," ",self.scrollbarCol2)
    -- Draw scrollbar thumb
    if scrollbar_height > 0 then
      local thumb_y=self.size2.y1+scrollbar_pos
      r:fill(tgl.Size2:new(scrollbar_x,thumb_y,1,scrollbar_height),"█",self.scrollbarCol2)
    end
  end
  --objects
  for _,object in pairs(self.objects) do
    if object.type then
      --check if should render
      if object.relpos2 then
        if object.relpos2.y>self.scroll and object.relpos2.y<=self.size2.sizeY+self.scroll then
          --translate
          object.pos2=tgl.Pos2:new(object.relpos2.x+self.size2.x1-1,object.relpos2.y+self.size2.y1-self.scroll-1)
          object:render()
        end
      elseif object.relsize2 then
        --
      else
        tgl.util.log("Corrupted object(no pos2/size2): "..object.type,"ScrollFrame/render")
        tgl.util.objectInfo(object)
      end
    end
  end
end

function tgl.ScrollFrame:enable()
  if self.enabled==true or self.hidden==true then return end
  self.enabled=true
  event.listen("scroll",self.handler)
  event.listen("touch",self.handler)
end
function tgl.ScrollFrame:disable()
  self.enabled=false
  event.ignore("scroll",self.handler)
  event.ignore("touch",self.handler)
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