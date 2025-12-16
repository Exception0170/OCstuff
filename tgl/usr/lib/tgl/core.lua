local gpu=require("component").gpu
local term=require("term")
local unicode=require("unicode")
return function(tgl)
tgl.debug=true
tgl.logfile="" --file to log
tgl.sys={}
---Classes with `:enable()` and `:disable()` methods
tgl.sys.enableTypes={Button=true,EventButton=true,CheckBox=true,InputField=true,ScrollFrame=true}
---Classes with `:enableAll()` and `:disableAll()` methods 
tgl.sys.enableAllTypes={Frame=true,Bar=true,ScrollFrame=true}
---Classes with `:open()` and `:close()` methods
tgl.sys.openTypes={Frame=true,ScrollFrame=true}
---Utility methods
tgl.util={}
---Defaults table(empty for now, filled in defaults.lua)
tgl.defaults={}
---Active area at screen which defines where elements are interactable
---@type tgl.Size2|nil
tgl.sys.activeArea=nil
---Sets new active area
---@param size2 tgl.Size2
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
  tgl.sys.activeArea=tgl.Size2:newFromSize(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY)
end

---Checks is Pos2 is inside Size2
---@param pos2 tgl.Pos2
---@param size2 tgl.Size2
---@return boolean
function tgl.util.pos2InSize2(pos2,size2)
  if size2.type~="Size2" or pos2.type~="Pos2" then return false end
  if pos2.x>=size2.x1 and pos2.x<=size2.x2 and
     pos2.y>=size2.y1 and pos2.y<=size2.y2 then return true
  else return false end
end
---Checks if point is inside Size2
---@param x integer
---@param y integer
---@param size2 Size2
---@return boolean
function tgl.util.pointInSize2(x,y,size2)
  if size2.type~="Size2" or type(x)~="number" or type(y)~="number" then return false end
  if x>=size2.x1 and x<=size2.x2 and y>=size2.y1 and y<= size2.y2 then return true
  else return false end
end
---Checks if size2 is inside size2
---@param size1 Size2
---@param size2 Size2
---@return boolean
function tgl.util.size2InSize2(size1,size2)
  if type(size1)~="table" or type(size2)~="table" then return false end
  if size1.type~="Size2" or size2.type~="Size2" then return false end
  if size2.x1>=size1.x1 and size2.x2<=size2.x2
  and size2.y1>=size2.y1 and size2.y2<=size2.y2 then return true
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
  for i=1,len do
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
  if text=="" then return 0 end
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
---@class tgl.Color2
tgl.Color2={}
tgl.Color2.__index=tgl.Color2
---@param col1? integer foreground color
---@param col2? integer background color
---@return tgl.Color2
function tgl.Color2:new(col1,col2)
  if not col1 then col1=tgl.defaults.foregroundColor end
  if not col2 then col2=tgl.defaults.backgroundColor end
  col1=tonumber(col1)
  col2=tonumber(col2)
  if col1 and col2 then
    if col1>=0 and col1<16777216 and col2>=0 and col2<16777216 then
      return setmetatable({col1,col2,type="Color2"},self)
    end
  end
  return nil
end

---Gets current cursor color2
---@return tgl.Color2
function tgl.getCurrentColor2()
  return tgl.Color2:new(gpu.getForeground(),gpu.getBackground())
end

---Changes cursor color to given Color2
---@param col2 tgl.Color2
---@param ignore? boolean if function should ignore previous color
---@return tgl.Color2|false|nil
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

---Colored term.write function
---@param col2? tgl.Color2 default: `tgl.defaults.colors2.error`
function tgl.cwrite(text,col2)
  if not col2 then col2=tgl.defaults.colors2.error end
  local p=tgl.changeToColor2(col2,false)
  term.write(text)
  tgl.changeToColor2(p,true)
end
---Colored print function
---@param col2? tgl.Color2 default: `tgl.defaults.colors2.error`
function tgl.cprint(text,col2)
  tgl.cwrite(text.."\n",col2)
end

---2D Position object
---@class tgl.Pos2
---@field type string
---@field x integer
---@field y integer
tgl.Pos2={}
tgl.Pos2.__index=tgl.Pos2

---@param x? integer
---@param y? integer
---@return tgl.Pos2
function tgl.Pos2:new(x,y)
  if not x then x=1 end
  if not y then y=1 end
  x=tonumber(x)
  y=tonumber(y)
  if x and y then
    if x>0 and y>0 and x<=tgl.defaults.screenSizeX and y<=tgl.defaults.screenSizeY then
      local obj=setmetatable({},self)
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
---@param pos2 tgl.Pos2
---@param ignore? boolean if set to `false|nil`, returns previous cursor Pos2
---@param offsetX? integer offset x from pos2 
function tgl.changeToPos2(pos2,ignore,offsetX)
  if not pos2 then return false end
  if not offsetX then offsetX=0 end
  if not ignore then
    local old=tgl.Pos2:new(term.getCursor())
    term.setCursor(pos2.x+offsetX,pos2.y)
    return old
  end
  term.setCursor(pos2.x+offsetX,pos2.y)
end

---Size2 class defines BoxObject's position and size
---@class tgl.Size2
---@field type string
---@field x1 integer
---@field x2 integer
---@field y1 integer
---@field y2 integer
---@field pos1 tgl.Pos2
---@field pos2 tgl.Pos2
---@field sizeX integer
---@field sizeY integer
tgl.Size2={}
tgl.Size2.__index=tgl.Size2
---Creates Size2 from 4 coordinates
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
---@return tgl.Size2
function tgl.Size2:newFromPoint(x1,y1,x2,y2)
  if type(x1)~="number" or type(x2)~="number"
  or type(y1)~="number" or type(y2)~="number" then return nil end
  local pos1=tgl.Pos2:new(x1,y1)
  local pos2=tgl.Pos2:new(x2,y2)
  if pos1 and pos2 then
    local obj=setmetatable({},self)
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
---@param pos1 tgl.Pos2 top left
---@param pos2 tgl.Pos2 bottom right
---@return tgl.Size2
function tgl.Size2:newFromPos2(pos1,pos2)
  if pos1.type and pos2.type then
    local obj=setmetatable({},self)
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
---@return tgl.Size2
function tgl.Size2:newFromSize(x,y,sizeX,sizeY)
  local pos1=tgl.Pos2:new(x,y)
  if pos1 and tonumber(sizeX) and tonumber(sizeY) then
    local obj=setmetatable({},self)
    obj.type="Size2"
    obj.x1=x
    obj.y1=y
    obj.x2=x+sizeX-1
    obj.y2=y+sizeY-1
    obj.sizeX=sizeX
    obj.sizeY=sizeY
    obj.pos1=pos1
    obj.pos2=tgl.Pos2:new(obj.x2,obj.y2)
    return obj
  end
  return nil
end
---@param pos2 tgl.Pos2
---@return boolean
function tgl.Size2:moveToPos2(pos2)
  if not pos2 then return false end
  self.x1=pos2.x
  self.y1=pos2.y
  self.x2=self.x1+self.sizeX-1
  self.y2=self.y1+self.sizeY-1
  self.pos1=pos2
  self.pos2=tgl.Pos2:new(self.x2,self.y2)
  return true
end
---alias for `tgl.Size2:newFromSize()`
---@param x integer
---@param y integer
---@param sizeX integer
---@param sizeY integer
---@return tgl.Size2
function tgl.Size2:new(x,y,sizeX,sizeY)
  return tgl.Size2:newFromSize(x,y,sizeX,sizeY)
end

---Fills area with char
---@param size2 tgl.Size2
---@param col2 tgl.Color2
---@param char? string default is space
function tgl.fillSize2(size2,col2,char)
  if not size2 then tgl.util.log("no size2 given","fillSize2") return end
  if not char then char=" " end
  local prev=tgl.changeToColor2(col2)
  gpu.fill(size2.x1,size2.y1,size2.sizeX,size2.sizeY,char)
  tgl.changeToColor2(prev,true)
end
return tgl end