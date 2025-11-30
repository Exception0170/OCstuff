---Tui Graphics Library
---@version 0.7.0
---@diagnostic disable: return-type-mismatch
local gpu=require("component").gpu
local thread=require("thread")
local event=require("event")
local term=require("term")
local unicode=require("unicode")
local tgl={}
tgl.ver="0.7.1"
tgl.debug=true
tgl.logfile="" --file to log
---Utility methods
tgl.util={}
---Frequently used symbols, colors
tgl.defaults={
  foregroundColor=0xFFFFFF,
  backgroundColor=0,
  ---4bit color palette
  colors16={},
  ---Frequently used characters
  chars={
    full="█",darkshade="▓",mediumshade="▒",
    lightshade="░",sqrt="√",check="✔",
    cross="❌",save="💾",folder="📁",
    fileempty="🗋",file="🗎",email="📧"
  },
  ---For box art
  boxes={
    double="═║╔╗╚╝╠╣╦╩╬",
    signle="─│┌┐└┘├┤┬┴┼",
    round= "─│╭╮╰╯├┤┬┴┼"
  },
  ---Key values for input reading
  keys={
    backspace=8,delete=127,null=0,
    enter=13,space=32,ctrlz=26,
    ctrlc=3,ctrlv=22,esc=27
  }
}
if gpu.getDepth()==8 then --different bitdepth results in different 16 colors palette
  tgl.defaults.colors16={
    white=0xFFFFFF,gold=0xFFDB40,magenta=0xCC6DBF,lightblue=0X6692FF,
    yellow=0xFFFF00,lime=0x00FF00,pink=0xFF6D80,darkgray=0x2D2D2D,
    lightgray=0xD2D2D2,cyan=0x336D80,purple=0x9924BF,darkblue=0x332480,
    brown=0x662400,darkgreen=0x336D00,red=0xFF0000,black=0x0
  }
else
  tgl.defaults.colors16={
    white=0xFFFFFF,gold=0xFFCC33,magenta=0xCC66CC,lightblue=0x6699FF,
    yellow=0xFFFF33,lime=0x33CC33,pink=0xFF6699,darkgray=0x333333,
    lightgray=0xCCCCCC,cyan=0x336699,purple=0x9933CC,darkblue=0x333399,
    brown=0x663300,darkgreen=0x336600,red=0xFF3333,black=0x0
  }
end
tgl.defaults.screenSizeX,tgl.defaults.screenSizeY=gpu.getResolution()
tgl.sys={}
---Classes with `:enable()` and `:disable()` methods
tgl.sys.enableTypes={Button=true,EventButton=true,CheckBox=true,InputField=true,ScrollFrame=true}
---Classes with `:enableAll()` and `:disableAll()` methods 
tgl.sys.enableAllTypes={Frame=true,Bar=true,ScrollFrame=true}
---Classes with `:open()` and `:close()` methods
tgl.sys.openTypes={Frame=true,ScrollFrame=true}
---Active area at screen which defines where elements are interactable
---@type Size2|nil
tgl.sys.activeArea=nil
---Sets new active area
---@param size2 Size2
function tgl.sys.setActiveArea(size2)
  if size2.type=="Size2" then
    tgl.sys.activeArea=size2
    return true
  end
  return false
end
function tgl.sys.getActiveArea()
  return tgl.sys.activeArea
end
function tgl.sys.resetActiveArea()
  tgl.sys.activeArea=Size2:newFromSize(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY)
end

---@param pos2 Pos2
---@param size2 Size2
function tgl.util.pos2InSize2(pos2,size2)
  if size2.type~="Size2" or pos2.type~="Pos2" then return false end
  if pos2.x>=size2.x1 and pos2.x<=size2.x2 and
     pos2.y>=size2.y1 and pos2.y<=size2.y2 then return true
  else return false end
end
function tgl.util.pointInSize2(x,y,size2)
  if size2.type~="Size2" or type(x)~="number" or type(y)~="number" then return false end
  if x>=size2.x1 and x<=size2.x2 and y>=size2.y1 and y<= size2.y2 then return true 
  else return false end
end
---@param text string
---@param mod? string module name(default=`"MAIN"`)
function tgl.util.log(text,mod)
  if tgl.debug then
    local c=require("component")
    if not mod then mod="MAIN" end
    local s="["..require("computer").uptime().."][TGL]["..mod.."] "..text
    if c.isAvailable("ocelot") then
      c.ocelot.log(s)
    elseif tgl.logfile~="" then
      local file=io.open(tgl.logfile,"a")
      if file then
        file:write(s.."\n")
        file:close()
      end
    end
  end
end
function tgl.util.printColors16(nextLine)
  for name,col in pairs(tgl.defaults.colors16) do
    Text:new(name,Color2:new(col)):render(nextLine)
    if not nextLine then term.write(" ") end
  end
  if not nextLine then term.write("\n") end
end
---Gets line of desired length starting at pos2
---@param pos2 Pos2
---@param len integer
---@return string
function tgl.util.getLine(pos2,len)
  local s=""
  for i=1,len+1 do
    local char=gpu.get(pos2.x+i-1,pos2.y)
    s=s..char
  end
  return s
end
---Checks if line at pos2 is matches text[and same color as col2, if given]
---@param pos2 Pos2
---@param text string
---@param col2? Color2
function tgl.util.getLineMatched(pos2,text,col2)
  if type(pos2)~="table" then return end
  if not text then return end
  local matched=0
  local dolog=true
  for i=1,unicode.wlen(text) do
    local char,fgcol,bgcol=gpu.get(pos2.x+i-1,pos2.y)
    if char==unicode.sub(text,i,i) then
      if col2 then
        if fgcol==col2[1] and bgcol==col2[2] then
          matched=matched+1
        else
          --tgl.util.log("Color mismatch: "..tostring(bgcol).." "..tostring(col2[2]),"Util/getLineMatched")
          if gpu.getDepth()==4 and dolog then tgl.util.log("4bit color problem, refer to tgl.defaults.colors16","Util/getLineMatched") end
          dolog=false
        end
      else matched=matched+1
      end
    else
      --tgl.util.log(char.."!="..unicode.sub(text,i,i),"Util/getLineMatched")
    end
  end
  return matched
end

function tgl.util.objectInfo(object)
  if not object then tgl.util.log("Nil object","util/objectInfo") return end
  if type(object)~="table" then tgl.util.log("Non-table object: "..tostring(object),"util/objectInfo") return end
  tgl.util.log("Object type: "..object.type,"util/objectInfo")
  if object.type=="Pos2" then tgl.util.log("Linear: Pos2("..object.x.." "..object.y..")","util/objectInfo") end
  if object.type=="Size2" then tgl.util.log("2-D: Size2("..object.pos1.x.." "..object.pos1.y..
  " "..object.sizeX.."x"..object.sizeY..")","util/objectInfo") end
  if object.pos2 and object.type~="Size2" then tgl.util.objectInfo(object.pos2) end
  if object.size2 then tgl.util.objectInfo(object.size2) end
  if object.type=="Text" or object.type=="Button" or object.type=="InputField" then tgl.util.log("Text: "..object.text,"util/objectInfo") end
  if object.objects then tgl.util.log("Contains objects","util/objectInfo") end
end

function tgl.createObject(obj_type,properties)
  if type(obj_type)~="string" then
    tgl.util.log("Tried to create object with '"..tostring(obj_type).."' type","main/createObject")
    return nil
  end
  local new_obj=nil
  if obj_type=="Text" then new_obj=Text:new()
  elseif obj_type=="MultiText" then new_obj=MultiText:new()
  elseif obj_type=="Button" then new_obj=Button:new()
  elseif obj_type=="EventButton" then new_obj=EventButton:new()
  elseif obj_type=="CheckBox" then new_obj=CheckBox:new()
  elseif obj_type=="Bar" then new_obj=Bar:new()
  elseif obj_type=="Progressbar" then new_obj=Progressbar:new()
  elseif obj_type=="Frame" then new_obj=Frame:new()
  elseif obj_type=="Pos2" then new_obj=Pos2:new()
  elseif obj_type=="Color2" then new_obj=Color2:new()
  elseif obj_type=="Size2" then new_obj=Size2:new()
  elseif obj_type=="InputField" then new_obj=InputField:new()
  else tgl.util.log("Unknown type of object: "..obj_type,"main/createObject")
  end
  if type(properties)=="table" then
    new_obj=tgl.util.setProperties(new_obj,properties)
  end
  return new_obj
end

function tgl.util.setProperties(obj,args)
  if type(obj)~="table" or type(args)~="table" then
    tgl.util.log("Invalid parameters","util/setProperties")
    return obj
  end
  for key,value in pairs(args) do
    if key=="objects" and type(value)=="table" then
      for obj_name,props in pairs(value) do
        if type(props)=="table" then
          local new_obj=tgl.createObject(props.type,props)
          if new_obj then
            obj[key][obj_name]=new_obj
          else
            tgl.util.log("Couldn't create object during setting properties!","util/setProperties")
          end
        end
      end
    else
      obj[key]=value
    end
  end
  return obj
end
--[[example Frame object
Frame:new({Text:new("Hello",nil,Pos2:new(2,2))},Size2:new(2,2,10,10),Color2:new(0,0xFFFFFF))
tgl.createObject("Frame",{type="Frame",size2=Size2:new(2,2,10,10),col2=Color2:new(0,0xFFFFFF),objects={{type="Text",text="Hello",pos2=Pos2:new(2,2)}}})
]]

function tgl.util.getProperties(obj,ignore)
  if ignore==nil then ignore=true end
  local res={}
  local ignored={
    objects=true,
    pos2=true, size2=true,
    relpos2=true, type=true,
    x1=true, x2=true,
    y1=true, y2=true,
    pos1=true, len=true,
    handler=true,
    onClick=true,
    hidden=true,
    callback=true,
  }
  for key,value in pairs(obj) do
    if ignore then
      if not ignored[key] then res[key]=value end
    else
      res[key]=value
    end
  end
  return res
end

---Color object, 1st elem is foreground color, 2nd is background color
---@class Color2
Color2={}
Color2.__index=Color2
---@param col1? integer foreground color
---@param col2? integer background color
---@return Color2
function Color2:new(col1,col2)
  if not col1 then col1=tgl.defaults.foregroundColor end
  if not col2 then col2=tgl.defaults.backgroundColor end
  col1=tonumber(col1)
  col2=tonumber(col2)
  if col1 and col2 then
    if col1>=0 and col1<16777216 and col2>=0 and col2<16777216 then
      return setmetatable({col1,col2,type="Color2"},Color2)
    end
  end
  return nil
end

---Frequently used Color2 objects
tgl.defaults.colors2={}
tgl.defaults.colors2.error=Color2:new(tgl.defaults.colors16.red,0)
tgl.defaults.colors2.black=Color2:new(0xFFFFFF,0)
tgl.defaults.colors2.white=Color2:new(0,0xFFFFFF)
tgl.defaults.colors2.close=Color2:new(0xFFFFFF,tgl.defaults.colors16.red)
tgl.defaults.colors2.progressbar=Color2:new(tgl.defaults.colors16.lime,0xFFFFFF)

---Gets current cursor color2
---@return Color2
function tgl.getCurrentColor2()
  return Color2:new(gpu.getForeground(),gpu.getBackground())
end

---Changes cursor color to given Color2
---@param col2 Color2
---@param ignore? boolean if function should ignore previous color
---@return Color2|false|nil
function tgl.changeToColor2(col2,ignore)
  if not col2 then return false end
  if not ignore then
    local old=tgl.getCurrentColor2()
    gpu.setForeground(col2[1])
    gpu.setBackground(col2[2])
    return old
  end
  gpu.setForeground(col2[1])
  gpu.setBackground(col2[2])
end

---Colored print function
---@param col2? Color2 default: `tgl.defaults.colors2.error`
function tgl.cprint(text,col2)
  if not col2 then col2=tgl.defaults.colors2.error end
  local p=tgl.changeToColor2(col2,false)
  print(text)
  tgl.changeToColor2(p,true)
end

---2D Position object
---@class Pos2
---@field type string
---@field x integer
---@field y integer
Pos2={}
Pos2.__index=Pos2

---@param x? integer
---@param y? integer
---@return Pos2
function Pos2:new(x,y)
  if not x then x=1 end
  if not y then y=1 end
  x=tonumber(x)
  y=tonumber(y)
  if x and y then
    if x>0 and y>0 and x<161 and y<=100 then
      local obj=setmetatable({},Pos2)
      obj.type="Pos2"
      obj[1]=x
      obj[2]=y
      obj.x=x
      obj.y=y
      return obj
    end
  end
  return nil
end

---Set cursor to Pos2
---@param pos2 Pos2
---@param ignore? boolean if set to `false|nil`, returns previous cursor Pos2
---@param offsetX? integer offset x from pos2 
function tgl.changeToPos2(pos2,ignore,offsetX)
  if not pos2 then return false end
  if not offsetX then offsetX=0 end
  if not ignore then
    local old=Pos2:new(term.getCursor())
    term.setCursor(pos2.x+offsetX,pos2.y)
    return old
  end
  term.setCursor(pos2.x+offsetX,pos2.y)
end

---Size2 class defines BoxObject's position and size
---@class Size2
---@field type string
---@field x1 integer
---@field x2 integer
---@field y1 integer
---@field y2 integer
---@field pos1 Pos2
---@field pos2 Pos2
---@field sizeX integer
---@field sizeY integer
Size2={}
Size2.__index=Size2
---Creates Size2 from 4 coordinates
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
---@return Size2
function Size2:newFromPoint(x1,y1,x2,y2)
  if type(x1)~="number" or type(x2)~="number"
  or type(y1)~="number" or type(y2)~="number" then return nil end
  local pos1=Pos2:new(x1,y1)
  local pos2=Pos2:new(x2,y2)
  if pos1 and pos2 then
    local obj=setmetatable({},Size2)
    obj.type="Size2"
    obj.x1=x1
    obj.y1=y1
    obj.x2=x2
    obj.y2=y2
    obj.pos1=pos1
    obj.pos2=pos2
    obj.sizeX=math.abs(x2-x1+1)
    obj.sizeY=math.abs(y2-y1+1)
    return obj
  end
  return nil
end
---Creates Size2 from two Pos2
---@param pos1 Pos2 top left
---@param pos2 Pos2 bottom right
---@return Size2
function Size2:newFromPos2(pos1,pos2)
  if pos1.type and pos2.type then
    local obj=setmetatable({},Size2)
    obj.type="Size2"
    obj.x1=pos1.x
    obj.y1=pos1.y
    obj.x2=pos2.x
    obj.y2=pos2.y
    obj.pos1=pos1
    obj.pos2=pos2
    obj.sizeX=math.abs(obj.x2-obj.x1+1)
    obj.sizeY=math.abs(obj.y2-obj.y1+1)
    return obj
  end
  return nil
end
---Creates Size2 from a point and sizes
---@param x integer
---@param y integer
---@param sizeX integer
---@param sizeY integer
---@return Size2
function Size2:newFromSize(x,y,sizeX,sizeY)
  local pos1=Pos2:new(x,y)
  if pos1 and tonumber(sizeX) and tonumber(sizeY) then
    local obj=setmetatable({},Size2)
    obj.type="Size2"
    obj.x1=x
    obj.y1=y
    obj.x2=x+sizeX-1
    obj.y2=y+sizeY-1
    obj.sizeX=sizeX
    obj.sizeY=sizeY
    obj.pos1=pos1
    obj.pos2=Pos2:new(obj.x2,obj.y2)
    return obj
  end
  return nil
end
function Size2:moveToPos2(pos2)
  if not pos2 then return false end
  self.x1=pos2.x
  self.y1=pos2.y
  self.x2=self.x1+self.sizeX
  self.y2=self.y1+self.sizeY
  self.pos1=pos2
  self.pos2=Pos2:new(self.x2,self.y2)
  return true
end
---alias for `Size2:newFromSize()`
function Size2:new(x,y,sizeX,sizeY)
  return Size2:newFromSize(x,y,sizeX,sizeY)
end

---Fills area with char
---@param size2 Size2
---@param col2 Color2
---@param char? string default is space
function tgl.fillSize2(size2,col2,char)
  if not size2 then tgl.util.log("no size2 given","fillSize2") return end
  if not char then char=" " end
  local prev=tgl.changeToColor2(col2)
  gpu.fill(size2.x1,size2.y1,size2.sizeX,size2.sizeY,char)
  tgl.changeToColor2(prev,true)
end

---Base for TGL UI objects
---@class UIObject
---@field type string
---@field hidden boolean if object is hidden
---@field new function(self,...):UIObject Constructor
---@field render function Render function
UIObject={}
UIObject.__index=UIObject

---Base for all single-line objects
---@class LineObject:UIObject
---@field pos2 Pos2
---@field col2 Color2
LineObject=setmetatable({},{__index=UIObject})
LineObject.__index=LineObject

---Base for all single-line interactable objects
---@class LineObjectInteractable:LineObject
---@field enabled boolean If object is active
---@field enable function Enable object
---@field disable function Disable object
---@field checkRendered boolean Check if object is actually rendered(default=true)
LineObjectInteractable=setmetatable({},{__index=LineObject})
LineObjectInteractable.__index=LineObjectInteractable

---Single line text object
---@class Text:LineObject
---@field text string
---@field maxLength integer Max text length, -1 for unlimeted
Text=setmetatable({},{__index=LineObject})
Text.__index=Text

---@param text string
---@param col2? Color2
---@param pos2? Pos2
---@return Text
function Text:new(text,col2,pos2)
  local obj=setmetatable({},Text)
  obj.type="Text"
  obj.text=text
  obj.col2=col2 or Color2:new()
  obj.pos2=pos2 or nil --Intended: pos2 can be nil, text will displayed on current cursor pos
  obj.maxLength=-1
  return obj
end

---@param nextLine? boolean change to next line after rendering
function Text:render(nextLine)
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
  local prev=tgl.changeToColor2(self.col2)
  if not self.pos2 then
    term.write(self.text)
    tgl.changeToColor2(prev,true)
    if nextLine then term.write("\n") end
    return true
  end
  gpu.set(self.pos2.x,self.pos2.y,self.text)
  tgl.changeToColor2(prev,true)
  return true
end
---Clear text field and render new text
function Text:updateText(text)
  self.text=string.rep(" ",unicode.wlen(self.text))
  self:render()
  self.text=tostring(text)
  self:render()
end

---A special object to store multiple Text objects and render at same time
---@class MultiText:UIObject
---@field objects Text[]
---@field pos2 Pos2
MultiText={}
MultiText.__index=MultiText
---@param objects Text[]
---@param pos2? Pos2
---@return MultiText|UIObject
function MultiText:new(objects,pos2)
  if type(objects)=="table" then
    local obj=setmetatable({},self)
    obj.type="MultiText"
    obj.objects={}
    for k,object in pairs(objects) do
      if type(object)=="table" then
        if object.type=="Text" then
          if not tonumber(k) then obj.objects[k]=object
          else table.insert(obj.objects,object) end
        end
      end
    end
    obj.pos2=pos2 or Pos2:new()
    return obj
  end
end
function MultiText:render()
  if self.hidden then return end
  local startX=self.pos2.x
  for _,object in pairs(self.objects) do
    if object.pos2 then object:render()
    else
      object.pos2=Pos2:new(startX,self.pos2.y)
      startX=startX+unicode.wlen(object.text)
      object:render()
    end
  end
end

---Single-line text button, runs callback function
---@class Button:LineObjectInteractable
---@field callback function Function to run on click
---@field text string
---@field handler function Button handler, main button logic(is set by default)
---@field onClick function handles graphic like color change on press
Button=setmetatable({},{__index=LineObjectInteractable})
Button.__index=Button
---@param text string
---@param callback function
---@param pos2? Pos2
---@param color2? Color2
---@return Button
function Button:new(text,callback,pos2,color2)
  ---@type Button
  local obj=setmetatable({},self)
  obj.type="Button"
  obj.text=text or "[New Button]"
  if type(callback)~="function" then
  	callback=function() tgl.util.log("Empty Button!","Button/callback") end
  end
  obj.enabled=false
  obj.callback=callback
  obj.pos2=pos2 or Pos2:new()
  obj.col2=color2 or Color2:new()
  obj.checkRendered=true -- check if button is on screen
  obj.handler=function (_,_,x,y)
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
      local success,err=pcall(obj.callback)
      if not success then
        tgl.util.log("Button handler error: "..err,"Button/handler")
      end
    end
  end
  obj.onClick=function()
    obj:disable()
    local invert=Color2:new(obj.col2[2],obj.col2[1])
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
function Button:enable()
  self.enabled=true
  event.listen("touch",self.handler)
end
function Button:disable()
  self.enabled=false
  event.ignore("touch",self.handler)
end
function Button:render()
  if self.hidden then return end
  local prev=tgl.changeToColor2(self.col2)
  gpu.set(self.pos2.x,self.pos2.y,self.text)
  tgl.changeToColor2(prev,true)
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
---@class InputField:LineObjectInteractable
---@field defaultText string Default display string
---@field eventName string Event to push after input is done
---@field charCol2 Color2 Cursor Color2, uses background color(default - lime)
---@field erase boolean If erase field after input is done
---@field secret boolean If use password protection
---@field handler function Function is called on user click
InputField=setmetatable({},{__index=LineObjectInteractable})
InputField.__index=InputField
function InputField:new(text,pos2,col2)
  ---@type InputField
  local obj=setmetatable({},self)
  obj.type="InputField"
  obj.text=""
  obj.secret=false
  obj.defaultText=text or "[______]"
  obj.pos2=pos2 or Pos2:new()
  obj.col2=col2 or Color2:new()
  obj.eventName="InputEvent"
  obj.checkRendered=true
  obj.charCol2=Color2:new(0,tgl.defaults.colors16["lime"])
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
function InputField:input()
  local prev=tgl.changeToPos2(self.pos2)
  local prevCol=tgl.changeToColor2(self.col2)
  local printChar=Text:new(" ",self.charCol2)
  tgl.sys.setActiveArea(Size2:newFromPos2(self.pos2,Pos2:new(self.pos2.x+unicode.wlen(self.text),self.pos2.y)))
  local offsetX=0
  if self.erase then
    if self.text=="" then gpu.fill(self.pos2.x,self.pos2.y,unicode.wlen(self.defaultText)+1,1," ")
    else gpu.fill(self.pos2.x,self.pos2.y,unicode.wlen(self.text)+1,1," ") end
    self.text=""
  else
    if self.text=="" then gpu.fill(self.pos2.x,self.pos2.y,unicode.wlen(self.defaultText)+1,1," ") offsetX=0
    else offsetX=unicode.wlen(self.text) end
  end
  ---@private
  local function printChr()
    printChar.pos2=Pos2:new(self.pos2.x+offsetX,self.pos2.y)
    printChar:render()
  end
  printChr()
  while true do
    local id,_,key,key2=event.pullMultiple("interrupted","key_down")
    if offsetX<0 then offsetX=0 tgl.util.log("Input going offbounds","DIF/input") end
    if key==tgl.defaults.keys.enter or id=="interrupted" then
      break
    elseif (key==tgl.defaults.keys.backspace or key==tgl.defaults.keys.delete) and unicode.wlen(self.text)>0 then
      local textLen=unicode.wlen(self.text)
      gpu.fill(self.pos2.x,self.pos2.y,textLen+1,1," ")
      offsetX=offsetX-unicode.charWidth(unicode.sub(self.text,textLen))
      self.text=unicode.sub(self.text,1,textLen-1)
      if textLen-1>0 then self:render()
      else gpu.fill(self.pos2.x,self.pos2.y,unicode.wlen(self.text)+1,1," ") end
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
  tgl.changeToPos2(prev,true)
  tgl.changeToColor2(prevCol,true)
  printChar.col2=self.col2
  printChr()
  self:render()
  tgl.sys.resetActiveArea()
end
function InputField:render()
  if self.hidden then return false end
  local prev=tgl.changeToColor2(self.col2)
  if self.text=="" then gpu.set(self.pos2.x,self.pos2.y,self.defaultText)
  else
    if not self.secret then
      gpu.set(self.pos2.x,self.pos2.y,self.text)
    else
      gpu.set(self.pos2.x,self.pos2.y,tgl.util.strgen("*",unicode.wlen(self.text)))
    end
  end
  tgl.changeToColor2(prev,true)
end
function InputField:enable()
  event.listen("touch",self.handler)
end
function InputField:disable()
  event.ignore("touch",self.handler)
end

---One-line Bar object, for menus.
---If you use objectColor2, LineObjects can have boolean customCol2 to keep object's col2.
---LineObjects can also have integer customX for positioning.
---@deprecated
---@class Bar:LineObject
---@field objects LineObject[]
---@field objectColor2 Color2|nil Recolor objects
---@field space integer Space between objects(when automatic positioning)
---@field sizeX integer Bar length
---@field centerMode boolean WIP, default=false
Bar=setmetatable({},{__index=LineObject})
Bar.__index=Bar
function Bar:new(pos2,objects,col2,objDefaultCol2)
  local obj=setmetatable({},self)
  obj.type="Bar"
  obj.pos2=pos2 or Pos2:new()
  obj.col2=col2 or Color2:new()
  obj.objectColor2=objDefaultCol2 or nil
  obj.objects=objects or {}
  obj.space=0
  obj.sizeX=tgl.defaults.screenSizeX
  obj.centerMode=false
  return obj
end
function Bar:render()
  if self.hidden then return false end
  local prev=tgl.changeToColor2(self.col2)
  gpu.fill(self.pos2.x,self.pos2.y,self.sizeX,1," ")
  if self.centerMode then
    local object=self.objects[1]
    if object.type then
      local len=unicode.wlen(object.text)
      local startX=self.pos2.x+(self.sizeX-len)/2
      tgl.util.log("Bar start X:"..startX,"Bar/render")
      object.pos2=Pos2:new(startX,self.pos2.y)
      if not object.customCol2 and self.objectColor2 then
        object.col2=self.objectColor2
      end
      object:render()
    end
  else
    local startX=self.pos2.x
    for _,object in pairs(self.objects) do
      if startX>self.pos2.x+self.sizeX then
        tgl.util.log("Bar: out of bounds: "..startX,"Bar/render")
        break
      end
      if object.type then
        if not object.customX then
          object.pos2=Pos2:new(startX,self.pos2.y)
          startX=startX+unicode.wlen(object.text)+self.space
        else
          object.pos2=Pos2:new(self.pos2.x+object.customX-1,self.pos2.y)
        end
        if not object.customCol2 and self.objectColor2 then
          object.col2=self.objectColor2
        end
        object:render()
      end
    end
  end
  tgl.changeToColor2(prev,true)
  return true
end
function Bar:enableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
    end
  end
end
function Bar:disableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:disable() end
    end
  end
end
function Bar:add(object,customX,name,customcol)
  if object.type then
    object.customX=tonumber(customX)
    object.customCol2=customcol or nil
    if not name then
      table.insert(self.objects,object)
    else
      self.objects[name]=object
    end
    return true
  end
  return false
end

---Base BoxObject
---@class BoxObject:UIObject
---@field size2 Size2
---@field col2 Color2
BoxObject=setmetatable({},{__index=UIObject})
BoxObject.__index=BoxObject

---2D Box frame
---@class Frame:BoxObject
---@field objects table<string|integer, table> Objects can have relpos2 field, represents their position inside the frame
---@field borderType string Frame border type(`"inline"/"outline"`, default=`"inline"`)
---@field borders string|nil
---@field translate function
---@field enableAll function
---@field disableAll function
---@field open function
---@field close function
Frame=setmetatable({},{__index=BoxObject})
Frame.__index=Frame
---@param objects table<string|integer, UIObject|LineObject|BoxObject>
---@param size2 Size2
---@param col2? Color2
---@return Frame
function Frame:new(objects,size2,col2)
  local obj=setmetatable({},self)
  obj.type="Frame"
  obj.objects=objects
  obj.size2=size2
  obj.col2=col2 or Color2:new()
  obj.borderType="inline"
  --translate objects
  obj:translate()
  return obj
end
---move objects from relative positions to absolute ones in frame
function Frame:translate()
  for _,object in pairs(self.objects) do
    if object.type then
      if object.type~="Frame" and object.type~="ScrollFrame" then
        if not object.relpos2 then object.relpos2=object.pos2 end
        local t_pos2=object.relpos2
        if t_pos2 then
          object.pos2=Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1) --offset
          if object.type=="Bar" then
            if object.pos2.x+object.sizeX>self.size2.sizeX then
              object.sizeX=self.size2.sizeX-object.pos2.x+self.size2.x1
            end
          end
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"Frame/translate")
        end
      else ---WIP
        if not object.relsize2 then object.relsize2=Size2:newFromPos2(object.size2.pos1,object.size2.pos2) end
        local t_pos2=object.relsize2.pos1
        if t_pos2 then
          object.size2:moveToPos2(Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1))
          object:translate() --test
        else
          tgl.util.log("Corrupted frame!","Frame/translate")
        end
      end
    end
  end
end
function Frame:render()
  if self.hidden then return false end
  --frame
  tgl.fillSize2(self.size2,self.col2)
  --border
  if type(self.borders)=="string" and unicode.wlen(self.borders)>=6 then
    if not self.borderType then self.borderType="inline" end
    if self.borderType=="outline" then
      local horizontal=unicode.sub(self.borders,1,1)
      local vertical=unicode.sub(self.borders,2,2)
      local right_top=unicode.sub(self.borders,4,4)
      local left_bottom=unicode.sub(self.borders,5,5)
      local right_bottom=unicode.sub(self.borders,6,6)
      gpu.set(self.size2.x1+1,self.size2.y2+1,left_bottom)
      gpu.set(self.size2.x2+1,self.size2.y1,right_top)
      gpu.set(self.size2.x2+1,self.size2.y2+1,right_bottom)
      for i=self.size2.x1+2,self.size2.x2 do
        gpu.set(i,self.size2.y2+1,horizontal)
      end
      for i=self.size2.y1+1,self.size2.y2 do
        gpu.set(self.size2.x2+1,i,vertical)
      end
    elseif self.borderType=="inline" then
      local horizontal=unicode.sub(self.borders,1,1)
      local vertical=unicode.sub(self.borders,2,2)
      local left_top=unicode.sub(self.borders,3,3)
      local right_top=unicode.sub(self.borders,4,4)
      local left_bottom=unicode.sub(self.borders,5,5)
      local right_bottom=unicode.sub(self.borders,6,6)
      local prev=tgl.changeToColor2(self.col2)
      for i=self.size2.x1+1,self.size2.x2-1 do
        gpu.set(i,self.size2.y1,horizontal)
        gpu.set(i,self.size2.y2,horizontal)
      end
      for i=self.size2.y1+1,self.size2.y2-1 do
        gpu.set(self.size2.x1,i,vertical)
        gpu.set(self.size2.x2,i,vertical)
      end
      gpu.set(self.size2.x1,self.size2.y1,left_top)
      gpu.set(self.size2.x1,self.size2.y2,left_bottom)
      gpu.set(self.size2.x2,self.size2.y1,right_top)
      gpu.set(self.size2.x2,self.size2.y2,right_bottom)
      tgl.changeToColor2(prev,true)
    else
      tgl.util.log("Invalid border type: "..tostring(self.borderType),"Frame/render/borders")
    end
  end
  --objects
  for _,object in pairs(self.objects) do
    if object.type then
      object:render()
    end
  end
end
---Move frame and all its contents
---@param pos2 Pos2
function Frame:moveToPos2(pos2)
  if not pos2 then return false end
  self.size2:moveToPos2(pos2)
  self:translate()
end
function Frame:enableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
      if tgl.sys.enableAllTypes[object.type] then object:enableAll() end
    end
  end
end
function Frame:disableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:disable() end
      if tgl.sys.enableAllTypes[object.type] then object:disableAll() end
    end
  end
end
---Add an object to frame(with translating)
---@param object UIObject
---@param name? string
---@return boolean
function Frame:add(object,name)
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
function Frame:remove(elem)
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

---Saves a box from screen
---@class ScreenSave:BoxObject
---@field data table
---@field save function
---@field dump function
ScreenSave=setmetatable({},{__index=BoxObject})
ScreenSave.__index=ScreenSave
---Save the chars from `self.size2` region to `self.data`
function ScreenSave:save()
  for x=self.size2.x1,self.size2.x2 do
    self.data[x]={}
    for y=self.size2.y1,self.size2.y2 do
      local char,fgcol,bgcol=gpu.get(x,y)
      self.data[x][y]={char,fgcol,bgcol}
    end
  end
end
function ScreenSave:new(size2)
  if not size2 then size2=Size2:newFromPoint(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY) end
  local obj=setmetatable({},ScreenSave)
  obj.size2=size2
  obj.data={}
  obj.type="ScreenSave"
  obj:save()
  return obj
end
function ScreenSave:render()
  for x=self.size2.x1,self.size2.x2 do
    for y=self.size2.y1,self.size2.y2 do
      if not self.data[x][y] then return false end
      gpu.setForeground(self.data[x][y][2])
      gpu.setBackground(self.data[x][y][3])
      gpu.set(x,y,self.data[x][y][1])
    end
  end
end
---Dump saved data to file
---@param filename? string default=`"screensave.st"`
---@return boolean
function ScreenSave:dump(filename)
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
function ScreenSave:load(filename)
  if not filename then filename="screensave.st" end
  local file=io.open(filename)
  if not file then
    tgl.util.log("Couldn't open file: "..tostring(filename),"ScreenSave/load")
    return false
  end
  local size_raw=require("serialization").unserialize(file:read("*l"))
  if size_raw then
    local load_size2=Size2:newFromPoint(size_raw[1],size_raw[2],size_raw[3],size_raw[4])
    if load_size2 then
      local data=require("serialization").unserialize(file:read("*l"))
      if data then
        local obj=setmetatable({},ScreenSave)
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
function Frame:open(ignore_ss)
  self.hidden=false
  if not ignore_ss then self.ss=ScreenSave:new(self.size2) end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] and not object.ignoreOpen then object:open() end
    end
  end
  self:render()
  self:enableAll()
end
---Closes frame and disableAll. If screensave was stored, displayes saved screen
function Frame:close()
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
---@class ScrollFrame:Frame
---@field showScroll boolean NotImplemented: Show scrollbar(default=true)
---@field scroll integer Current scroll
---@field maxScroll integer
---@field isDragging boolean
---@field lastDragY integer
---@field handler function
---@field handleDragEvents function
---@field enable function
---@field disable function
---@field scrollbarCol2 Color2 Color2 of side scroller
ScrollFrame=setmetatable({},{__index=Frame})
ScrollFrame.__index=ScrollFrame
---@param objects table<string|integer, BoxObject|LineObject|UIObject>
---@param size2 Size2
---@param col2? Color2
---@param scrollcol2? Color2
---@return ScrollFrame
function ScrollFrame:new(objects,size2,col2,scrollcol2)
  local obj=setmetatable({},ScrollFrame)
  obj.type="ScrollFrame"
  obj.objects=objects or {}
  obj.size2=size2 or Size2:newFromSize(1,1,10,10)
  obj.col2=col2 or tgl.defaults.colors2.white
  obj.showScroll=true
  obj.maxScroll=5
  obj.scroll=0
  obj.scrollbarCol2=scrollcol2 or Color2:new(0xFFFFFF,tgl.defaults.colors16.lightgray)
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
function ScrollFrame:translate()
  for _,object in pairs(self.objects) do
    if object.type then
      if object.type~="Frame" and object.type~="ScrollFrame" then
        if not object.relpos2 then object.relpos2=object.pos2 end
        local t_pos2=object.relpos2
        if t_pos2 then
          object.pos2=Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1) --offset
          if object.type=="Bar" then
            if object.pos2.x+object.sizeX>self.size2.sizeX then
              --tgl.util.log("Bar Rescale: "..object.sizeX.." -> "..self.size2.sizeX.." - "..object.pos2.x.." + "..self.size2.x1,"Frame/translate:Bar")
              object.sizeX=self.size2.sizeX-object.pos2.x+self.size2.x1
            end
          end
        else
          tgl.util.log("Corrupted object! Type: "..tostring(object.type),"ScrollFrame/translate")
        end
      else
        if not object.relsize2 then object.relsize2=object.size2 end
        local t_pos2=object.size2.pos1
        if t_pos2 then
          object.size2:moveToPos2(Pos2:new(t_pos2.x+self.size2.x1-1,t_pos2.y+self.size2.y1-1))
        else
          tgl.util.log("Corrupted frame!","ScrollFrame/translate")
        end
      end
    end
  end
end

function ScrollFrame:render()
  if self.hidden then return false end
  --frame
  tgl.fillSize2(self.size2,self.col2)
  --scrollbar
  if self.showScroll and self.maxScroll > 0 then
    local scrollbar_x = self.size2.x2-1
    -- Calculate scrollbar metrics
    local visible_height = self.size2.sizeY
    local total_height = visible_height + self.maxScroll
    local scrollbar_height = math.max(1, math.floor(visible_height * visible_height / total_height))
    local scrollbar_pos = math.floor(self.scroll * (visible_height - scrollbar_height) / self.maxScroll)
    local prex,prey=term.getCursor()
    local precol2=tgl.changeToColor2(self.scrollbarCol2)
    gpu.fill(scrollbar_x,self.size2.y1,1,visible_height," ")
    -- Draw scrollbar thumb
    if scrollbar_height > 0 then
      local thumb_y=self.size2.y1+scrollbar_pos
      gpu.fill(scrollbar_x,thumb_y,1,scrollbar_height, "█")
    end
    term.setCursor(prex,prey)
    tgl.changeToColor2(precol2,true)
  end
  --objects
  for _,object in pairs(self.objects) do
    if object.type then
      --check if should render
      if object.relpos2 then
        if object.relpos2.y>self.scroll and object.relpos2.y<=self.size2.sizeY+self.scroll then
          --translate
          object.pos2=Pos2:new(object.relpos2.x+self.size2.x1-1,object.relpos2.y+self.size2.y1-self.scroll-1)
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

function ScrollFrame:enable()
  event.listen("scroll",self.handler)
  event.listen("touch",self.handler)
end
function ScrollFrame:disable()
  event.ignore("scroll",self.handler)
  event.ignore("touch",self.handler)
end
function ScrollFrame:enableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:enable() end
      if tgl.sys.enableAllTypes[object.type] then object:enableAll() end
    end
  end
end
function ScrollFrame:disableAll()
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.enableTypes[object.type] then object:disable() end
      if tgl.sys.enableAllTypes[object.type] then object:disableAll() end
    end
  end
end
---Add an object to frame(with translating)
---@param object UIObject
---@param name? string
---@return boolean
function ScrollFrame:add(object,name)
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
function ScrollFrame:remove(elem)
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
function ScrollFrame:open(ignore_ss)
  self.hidden=false
  if not ignore_ss then self.ss=ScreenSave:new(self.size2) end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] and not object.ignoreOpen then object:open() end
    end
  end
  self:render()
  self:enableAll()
end
---Closes frame and disableAll. If screensave was stored, displayes saved screen
function ScrollFrame:close()
  self.hidden=true
  self:disableAll()
  if self.ss then self.ss:render() self.ss=nil end
  for _,object in pairs(self.objects) do
    if object.type then
      if tgl.sys.openTypes[object.type] then object:close() end
    end
  end
end
---WIP Object dumps to text
tgl.dump={}
function tgl.dump.encodeObject(obj)
  if not obj then return nil end
  local ser=require("serialization")
  local dump={}
  dump.type="Dump"
  dump.obj_type=obj.type
  if obj.hidden then dump.hidden=obj.hidden end
  if obj.type=="Pos2" or obj.type=="Color2" or obj.type=="Size2" then
    return ser.serialize(obj)
  elseif tgl.sys.enableAllTypes[obj.type] then
    dump.objects={}
    for name,obj2 in pairs(obj.objects) do
      dump.objects[name]=tgl.dump.encodeObject(obj2)
    end
    dump.col2=tgl.dump.encodeObject(obj.col2)
    if obj.type=="Bar" then
      if obj.relpos2 then obj.pos2=obj.relpos2 end --reset
      dump.pos2=tgl.dump.encodeObject(obj.pos2)
      if obj.objectColor2 then dump.objectColor2=tgl.dump.encodeObject(obj.objectColor2) end
      dump.centerMode=obj.centerMode
      dump.sizeX=obj.sizeX
      dump.space=obj.space
      dump.centerMode=obj.centerMode
    else
      dump.size2=tgl.dump.encodeObject(obj.size2)
      if obj.type=="Frame" then
        dump.borderType=obj.borderType
        dump.borders=obj.borders
      else
        --scrollframe
      end
    end
  else
    if obj.relpos2 then obj.pos2=obj.relpos2 end --reset
    -- for bar
    if obj.customX then dump.customX=obj.customX end
    if obj.customCol2 then dump.customCol2=obj.customCol2 end

    dump.pos2=tgl.dump.encodeObject(obj.pos2)
    dump.col2=tgl.dump.encodeObject(obj.col2)
    if obj.type=="Text" then
      dump.text=obj.text
      dump.maxLength=obj.maxLength
    elseif obj.type=="InputField" then
      dump.text=obj.text
      dump.defaultText=obj.text
      dump.eventName=obj.eventName
      dump.checkRendered=obj.checkRendered
      dump.erase=obj.erase
      dump.charCol2=tgl.dump.encodeObject(obj.charCol2)
    elseif obj.type=="MultiText" then
      dump.objects={}
      for name,obj2 in pairs(obj.objects) do
        dump.objects[name]=tgl.dump.encodeObject(obj2)
      end
      dump.col2=nil
    elseif obj.type=="Progressbar" then
      dump.len=obj.len
      dump.text=obj.text
      dump.value=obj.value
    elseif obj.type=="Button" then
      --ugh
      dump.text=obj.text
      dump.checkRendered=obj.checkRendered
      if obj.functionName then dump.functionName=obj.functionName
      else tgl.util.log("Button with no functionName - will be dumped as empty","dump/encodeObject") end
    elseif obj.type=="ScreenSave" then
      tgl.util.log("Unsupported object type for dumping: ScreenSave","dump/encodeObject")
      return nil
    end
  end
  return ser.serialize(dump)
end
function tgl.dump.decodeObject(dump)
  if not dump then return nil end
  local ser=require("serialization")
  if type(dump)=="string" then dump=ser.unserialize(dump) end
  if dump.type=="Pos2" or dump.type=="Color2" or dump.type=="Size2" then
    return dump
  elseif tgl.sys.enableAllTypes[dump.obj_type] then
    local objects={}
    for name,obj2 in pairs(dump.objects) do
      objects[name]=tgl.dump.decodeObject(obj2)
    end
    local col2=tgl.dump.decodeObject(dump.col2)
    if dump.obj_type=="Frame" then
      local obj=Frame:new(objects,tgl.dump.decodeObject(dump.size2),col2)
      obj.borders=dump.borders
      obj.borderType=dump.borderType
      return obj
    elseif dump.obj_type=="Bar" then
      local pos2=tgl.dump.decodeObject(dump.pos2)
      local col2=tgl.dump.decodeObject(dump.col2)
      local objcol2=nil
      if dump.objectColor2 then objcol2=tgl.dump.decodeObject(dump.objectColor2) end
      local obj=Bar:new(pos2,objects,col2,objcol2)
      obj.space=dump.space
      obj.sizeX=dump.sizeX
      obj.centerMode=dump.centerMode
      return obj
    end
  else
    local pos2=tgl.dump.decodeObject(dump.pos2)
    local col2=tgl.dump.decodeObject(dump.col2)
    if dump.obj_type=="Text" then
      local obj=Text:new(dump.text,col2,pos2)
      obj.maxLength=dump.maxLength
      return obj
    elseif dump.obj_type=="InputField" then
      local obj=InputField:new(dump.text,pos2,col2)
      obj.defaultText=dump.text
      obj.eventName=dump.eventName
      obj.checkRendered=dump.checkRendered
      obj.erase=dump.erase
      obj.charCol2=tgl.dump.decodeObject(dump.charCol2)
      return obj
    elseif dump.obj_type=="Progressbar" then
      local obj=Progressbar:new(pos2,dump.len,col2)
      obj.value=dump.value
      obj.text=dump.text
      return obj
    elseif dump.obj_type=="MultiText" then
      local objects={}
      for name,obj2 in pairs(dump.objects) do
        objects[name]=tgl.dump.decodeObject(obj2)
      end
      local obj=MultiText:new(objects,pos2)
      return obj
    elseif dump.obj_type=="Button" then
      local obj=Button:new(dump.text,function() end,pos2,col2)
      obj.checkRendered=dump.checkRendered
      obj.functionName=dump.functionName
      --logic
      return obj
    end
  end
  return nil
end
function tgl.dump.dumpToFile(obj,filename)
  if type(obj)~="table" then return false end
  if not obj.type then return false end
  local file=io.open(filename,"w")
  if not file then return false end
  local success,dump=pcall(tgl.dump.encodeObject,obj)
  if not success then tgl.util.log("Couldn't dump an object: "..dump,"dump/toFile") return false end
  file:write(dump):close()
  return true
end
function tgl.dump.loadFromFile(filename)
  local file=io.open(filename)
  if not file then return false end
  local data=file:read("l")
  if string.len(data)<2 then return false end
  local success,obj=pcall(tgl.dump.decodeObject,data)
  if not success then tgl.util.log("Couldn't decode an object: "..obj,"dump/loadFile") return false end
  return obj
end

tgl.sys.resetActiveArea()
tgl.util.log("TGL version "..tgl.ver.." loaded")
return tgl