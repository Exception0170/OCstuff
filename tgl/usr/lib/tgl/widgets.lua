local event=require("event")
local unicode=require("unicode")
return function(tgl)
---Checkbox with separate checked and unchecked glyphs.
---@class tgl.CheckBox:tgl.LineObjectInteractable
---@field char string Checked glyph
---@field uncheckedChar string Unchecked glyph
---@field width integer Minimum width in screen cells
---@field value boolean
---@field text string Rendered glyph with padding
tgl.CheckBox=setmetatable({},{__index=tgl.LineObjectInteractable})
tgl.CheckBox.__index=tgl.CheckBox
---@param pos2? tgl.Pos2
---@param col2? tgl.Color2
---@param width? integer Minimum width; expands to fit both glyphs
---@param char? string Checked glyph; explicit legacy glyphs keep a blank unchecked state
---@param uncheckedChar? string
---@return tgl.CheckBox
function tgl.CheckBox:new(pos2,col2,width,char,uncheckedChar)
  checkArg(1,pos2,"table","nil")
  checkArg(2,col2,"table","nil")
  checkArg(3,width,"number","nil")
  checkArg(4,char,"string","nil")
  checkArg(5,uncheckedChar,"string","nil")
  local obj=setmetatable({},self)
  obj.type="CheckBox"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.events=tgl.Event:new()
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.col2=col2 or tgl.sys.themeColor("button")
  obj.char=char or tgl.sys.themeChar("checkboxChecked")
  obj.uncheckedChar=uncheckedChar or (char and " " or tgl.sys.themeChar("checkboxUnchecked"))
  obj.enabled=false
  obj.value=false
  obj.z_index=0
  obj.width=math.max(width or 0,unicode.wlen(obj.char),unicode.wlen(obj.uncheckedChar))
  local padding=obj.width-unicode.wlen(obj.uncheckedChar)
  obj.text=string.rep(" ",math.floor(padding/2))..obj.uncheckedChar..string.rep(" ",math.ceil(padding/2))
  obj.checkRendered=true
  obj.handler=function(_,_,x,y)
    if obj.destroyed then return end
    if x>=obj.pos2.x and x<obj.pos2.x+obj.width and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      if obj.checkRendered and tgl.sys.renderer:getZ(x,y)>obj.z_index then return end
      obj:toggle()
    end
  end
  obj.pointerDown=obj.handler
  obj.handler=tgl.sys.wrapInput(obj,obj.handler)
  return obj
end
function tgl.CheckBox:enable()
  if self.destroyed or self.hidden or self.enabled then return end
  self.enabled=true
  self.events:listen("touch",self.handler)
end
function tgl.CheckBox:disable()
  self.enabled=false
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  self.events:ignore("touch",self.handler)
end
function tgl.CheckBox:render()
  if self.destroyed or self.hidden then return end
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  self.width=math.max(self.width,unicode.wlen(self.char),unicode.wlen(self.uncheckedChar))
  local glyph=self.value and self.char or self.uncheckedChar
  local padding=self.width-unicode.wlen(glyph)
  self.text=string.rep(" ",math.floor(padding/2))..glyph..string.rep(" ",math.ceil(padding/2))
  tgl.sys.renderer:set(self.pos2,self.text,col2,self.z_index)
end
function tgl.CheckBox:setValue(value,render)
  checkArg(1,value,"boolean")
  checkArg(2,render,"boolean","nil")
  if self.destroyed or self.value==value then return false end
  self.value=value
  if render then self:render() end
  return true
end
function tgl.CheckBox:toggle()
  return self:setValue(not self.value,true)
end
function tgl.CheckBox:activate()
  return self:toggle()
end

---Radio buttons share a group table; selecting one clears the others.
---@class tgl.RadioButton:tgl.CheckBox
---@field group tgl.RadioButton[]
tgl.RadioButton=setmetatable({},{__index=tgl.CheckBox})
tgl.RadioButton.__index=tgl.RadioButton
---@param pos2? tgl.Pos2
---@param col2? tgl.Color2
---@param group? tgl.RadioButton[] Shared table; omitted means an independent button
---@param width? integer
---@param char? string Selected glyph
---@param uncheckedChar? string Unselected glyph
---@return tgl.RadioButton
function tgl.RadioButton:new(pos2,col2,group,width,char,uncheckedChar)
  checkArg(1,pos2,"table","nil")
  checkArg(2,col2,"table","nil")
  checkArg(3,group,"table","nil")
  checkArg(4,width,"number","nil")
  checkArg(5,char,"string","nil")
  checkArg(6,uncheckedChar,"string","nil")
  local obj=tgl.CheckBox.new(self,pos2,col2,width,char or tgl.sys.themeChar("radioSelected"),
    uncheckedChar or tgl.sys.themeChar("radioUnselected"))
  obj.type="RadioButton"
  obj.group=group or {}
  obj.group[#obj.group+1]=obj
  return obj
end
function tgl.RadioButton:setValue(value,render)
  checkArg(1,value,"boolean")
  checkArg(2,render,"boolean","nil")
  if self.destroyed then return false end
  if value then
    for _,other in ipairs(self.group) do
      if other~=self then tgl.CheckBox.setValue(other,false,render) end
    end
  end
  return tgl.CheckBox.setValue(self,value,render)
end
function tgl.RadioButton:toggle()
  return self:setValue(true,true)
end
function tgl.RadioButton:keyDown(char,code,shift,ctrl)
  if ctrl or (code~=200 and code~=208 and code~=203 and code~=205) then return false end
  local index
  for i,other in ipairs(self.group) do if other==self then index=i break end end
  if not index then return false end
  local step=(code==200 or code==203) and -1 or 1
  for offset=1,#self.group do
    local other=self.group[(index-1+step*offset)%#self.group+1]
    if other.enabled and not other.hidden and not other.destroyed
    and (not self.inputContext or self.inputContext:focus(other)) then
      other:setValue(true,true)
      return true
    end
  end
  return false
end
function tgl.RadioButton:destroy()
  if self.destroyed then return false end
  for i,other in ipairs(self.group) do
    if other==self then table.remove(self.group,i) break end
  end
  self.group=nil
  return tgl.UIObject.destroy(self)
end

---Progressbar LineObject
---@class tgl.Progressbar:tgl.LineObject
---@field width integer
---@field text string
---@field value number Percentage, from 0 to 1
---@field setValue function 
tgl.Progressbar=setmetatable({},{__index=tgl.LineObject})
tgl.Progressbar.__index=tgl.Progressbar
---@param pos2? tgl.Pos2
---@param width? integer defaults to 10
---@param col2? tgl.Color2 defaults to the progressbar theme role
---@return tgl.Progressbar
function tgl.Progressbar:new(pos2,width,col2)
  checkArg(1,pos2,"table","nil")
  checkArg(2,width,"number","string","nil")
  checkArg(3,col2,"table","nil")
  local obj=setmetatable({},tgl.Progressbar)
  obj.type="Progressbar"
  obj.z_index=0
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.width=tonumber(width) or 10
  obj.col2=col2 or tgl.sys.themeColor("progressbar")
  obj.text=string.rep(" ",obj.width)
  obj.value=0
  return obj
end
function tgl.Progressbar:render()
  if self.destroyed or self.hidden then return end
  local fill=math.floor(self.width*self.value)
  local half=self.width*self.value-fill>=0.5 and fill<self.width
  self.text=string.rep(tgl.defaults.chars.full,fill)..(half and "▌" or "")
    ..string.rep(" ",self.width-fill-(half and 1 or 0))
  local r=tgl.sys.renderer
  if self.gradient then
    local area=tgl.Size2:new(self.pos2.x,self.pos2.y,self.width,1)
    r:fill(area," ",self.col2,self.z_index)
    if fill>0 then
      local filled=tgl.Size2:new(self.pos2.x,self.pos2.y,fill,1)
      r:withClip(filled,r.gradient,r,area,self.gradient,self.col2,self.z_index)
    end
    if half then
      r:addCmd({cmd="gradienttext",pos2={x=self.pos2.x+fill,y=self.pos2.y},value="▌",
        gradient=self.gradient,area=area,col2=self.col2,z_index=self.z_index,foreground=true})
    end
  else r:set(self.pos2,self.text,self.col2,self.z_index) end
end
---Set progressbar to percentage
---@param num number Percent from 0 to 1
---@param render boolean Should it render immediately
---@return boolean
function tgl.Progressbar:setValue(num,render)
  checkArg(1,num,"number","string")
  checkArg(2,render,"boolean","nil")
  num=tonumber(num)
  if not num or num~=num or num>1 or num<0 then return false end
  self.value=num
  if render then self:render() end
  return true
end

---@class tgl.DropdownMenu:tgl.LineObjectInteractable
---@field text string
---@field menuCol2 tgl.Color2
---@field width integer
---@field options string[]
---@field value string
---@field handler function
---@field opened boolean
---@field closeOnDefocus boolean
---@field icons string icons to use
---@field eventName string event to fire
---@field defaultText string
tgl.DropdownMenu=setmetatable({},{__index=tgl.LineObjectInteractable})
tgl.DropdownMenu.__index=tgl.DropdownMenu
---@param pos2 tgl.Pos2
---@param width integer
---@param col2? tgl.Color2 defaults to the button theme role
---@param options string[]
---@param eventName? string
---@param menuCol2? tgl.Color2
---@return tgl.DropdownMenu
function tgl.DropdownMenu:new(pos2,width,col2,options,eventName,menuCol2)
  checkArg(1,pos2,"table")
  checkArg(2,width,"number")
  checkArg(3,col2,"table","nil")
  checkArg(4,options,"table","nil")
  checkArg(5,eventName,"string","nil")
  checkArg(6,menuCol2,"table","nil")
  local obj=setmetatable({},self)
  obj.type="DropdownMenu"
  obj.focusable=true
  obj.focusCol2=tgl.sys.themeColor("focus")
  obj.events=tgl.Event:new()
  obj.z_index=0
  obj.pos2=pos2
  obj.width=width
  obj.col2=col2 or tgl.sys.themeColor("button")
  obj.menuCol2=menuCol2 or obj.col2
  obj.options=options or {"Select","Empty1","Empty2"}
  obj.value=obj.options[1]
  obj.text=obj.value
  obj.checkRendered=true
  obj.opened=false
  obj.closeOnDefocus=true
  obj.icons="▾▴"
  obj.eventName=eventName or ""
  obj.defaultText=nil
  obj.handler=function(_,_,x,y)
    if obj.destroyed then return end
    if x>=obj.pos2.x and x<obj.pos2.x+obj.width and y==obj.pos2.y
    and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
      --open/close
      if obj.checkRendered then
        local col2=obj.focused and (obj.focusCol2 or tgl.defaults.colors2.focus) or obj.col2
        if tgl.util.getLineMatched(obj.pos2,obj.text,col2)/unicode.wlen(obj.value)<0.6 then
          return
        end
      end
      if obj.opened==false then
        obj.opened=true
        obj:showOptions()
        obj:render()
      else
        obj.opened=false
        obj:hideOptions()
        obj:render()
      end
    elseif obj.opened==true then
      if x>=obj.pos2.x and x<obj.pos2.x+obj.width
      and y>obj.pos2.y and y<=obj.pos2.y+#obj.options
      and tgl.util.pointInSize2(x,y,tgl.sys.activeArea) then
        --click
        local chosen=y-obj.pos2.y
        if not obj.options[chosen] then
          tgl.util.log("Fatal: no such option: '"..chosen.."', undefined behavior!","DropdownMenu/handler")
        else
          obj.value=obj.options[chosen]
          if obj.eventName~="" then
            event.push(obj.eventName,obj.value)
          end
        end
        obj.opened=false
        obj:hideOptions()
        obj:render()
      elseif obj.closeOnDefocus then
        obj.opened=false
        obj:hideOptions()
        obj:render()
      end
    end
  end
  obj.pointerDown=obj.handler
  obj.handler=tgl.sys.wrapInput(obj,obj.handler)
  return obj
end
function tgl.DropdownMenu:showOptions()
  if self.destroyed or self.hidden then return end
  return tgl.sys.drawObject(self,function()
    local r=tgl.sys.renderer
    local x1,y1=self.pos2.x,self.pos2.y+1
    local x2,y2=x1+self.width-1,y1+#self.options-1
    local clip=r:getClipRegion()
    x1=math.max(1,x1,clip and clip.x1 or 1)
    y1=math.max(1,y1,clip and clip.y1 or 1)
    x2=math.min(tgl.defaults.screenSizeX,x2,clip and clip.x2 or tgl.defaults.screenSizeX)
    y2=math.min(tgl.defaults.screenSizeY,y2,clip and clip.y2 or tgl.defaults.screenSizeY)
    if x1>x2 or y1>y2 then return false end
    local area=tgl.Size2:newFromPoint(x1,y1,x2,y2)
    if self.ss then
      local saved=self.ss.size2
      if saved.x1~=x1 or saved.y1~=y1 or saved.x2~=x2 or saved.y2~=y2 then
        self.ss:render()
        self.ss=nil
      end
    end
    if not self.ss then self.ss=tgl.ScreenSave:new(area) end
    r:withClip(area,function()
      r:fill(area," ",self.menuCol2,self.z_index)
      for i=1,#self.options do
        local y=self.pos2.y+i
        if y>=y1 and y<=y2 then
          local text=self.options[i]
          if unicode.wlen(text)>self.width then text=unicode.sub(text,1,self.width-2)..".." end
          local col2=self.selected==i and (self.focusCol2 or tgl.defaults.colors2.focus) or self.menuCol2
          r:fill(tgl.Size2:new(self.pos2.x,y,self.width,1)," ",col2,self.z_index)
          r:setPoint(self.pos2.x,y,text,col2,self.z_index)
        end
      end
    end)
  end)
end
function tgl.DropdownMenu:hideOptions()
  self.selected=nil
  if self.ss then
    self.ss:render()
    self.ss=nil
  end
end
function tgl.DropdownMenu:render()
  local col2=self.focused and (self.focusCol2 or tgl.defaults.colors2.focus) or self.col2
  if self.destroyed or self.hidden then return end
  if self.defaultText then
    self.text=self.defaultText
  else
    local icon=""
    if self.opened then icon=unicode.sub(self.icons,2,2)
    else icon=unicode.sub(self.icons,1,1) end
    self.text=self.value
    if unicode.wlen(self.text)>=self.width then
      self.text=unicode.sub(self.text,1,self.width-3)..".."..icon
    else
      self.text=self.text..string.rep(" ",self.width-unicode.wlen(self.text)-1)..icon
    end
  end
  tgl.sys.renderer:set(self.pos2,self.text,col2,self.z_index)
end
function tgl.DropdownMenu:enable()
  if self.destroyed or self.enabled==true or self.hidden==true then return end
  self.enabled=true
  self.events:listen("touch",self.handler)
end
function tgl.DropdownMenu:disable()
  self.enabled=false
  if self.inputContext then self.inputContext:cancelPointer(self,"disabled") end
  self.events:ignore("touch",self.handler)
  if self.opened==true then
    self.opened=false
    self.ss:unload()
    self.ss=nil
  end
end

function tgl.DropdownMenu:keyDown(char,code,shift,ctrl)
  if ctrl or #self.options==0 then return false end
  if code==200 or code==208 then
    if not self.selected then
      self.selected=1
      for i,value in ipairs(self.options) do if value==self.value then self.selected=i break end end
    end
    self.selected=(self.selected-1+(code==200 and -1 or 1))%#self.options+1
    self.opened=true
    self:showOptions()
    self:render()
    return true
  elseif char==13 or char==32 or code==28 or code==156 or code==57 then
    if self.opened then
      self.pointerDown("touch",nil,self.pos2.x,self.pos2.y+(self.selected or 1),0)
    else
      self.selected=1
      for i,value in ipairs(self.options) do if value==self.value then self.selected=i break end end
      self.opened=true
      self:showOptions()
      self:render()
    end
    return true
  end
  return false
end

for _,class in ipairs({tgl.CheckBox,tgl.Progressbar,tgl.DropdownMenu}) do
  tgl.sys.wrapRender(class)
end

--add new objects
tgl.sys.enableTypes["CheckBox"]=true
tgl.sys.enableTypes["RadioButton"]=true
tgl.sys.enableTypes["DropdownMenu"]=true
return tgl end
