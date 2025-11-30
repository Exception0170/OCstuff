--Tgl UI Elements
local tgl=require("tgl")
local event=require("event")
local gpu=require("component").gpu
local unicode=require("unicode")
local tui={}
tui.ver="1.0"
--moved from tgl.defaults

---Checkbox object
---@class CheckBox:LineObjectInteractable
---@field char string Clicked character
---@field width integer Length
---@field handler function
---@field toggle function
---@field value boolean Checked/not
---@field text string
CheckBox=setmetatable({},{__index=LineObjectInteractable})
CheckBox.__index=CheckBox
---@param pos2? Pos2
---@param col2? Color2
---@param width? integer
---@param char? string
---@return CheckBox
function CheckBox:new(pos2,col2,width,char)
  local obj=setmetatable({},CheckBox)
  obj.type="CheckBox"
  obj.pos2=pos2 or Pos2:new()
  obj.col2=col2 or Color2:new()
  obj.char=char or "*"
  obj.enabled=false
  obj.value=false
  obj.width=width or 1
  obj.text=string.rep(" ",1)
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
      obj:toggle()
    end
  end
  return obj
end
function CheckBox:enable()
  self.enabled=true
  event.listen("touch",self.handler)
end
function CheckBox:disable()
  self.enabled=false
  event.ignore("touch",self.handler)
end
function CheckBox:render()
  if self.hidden then return end
  local prev=tgl.changeToColor2(self.col2)
  gpu.set(self.pos2.x,self.pos2.y,self.text)
  tgl.changeToColor2(prev,true)
end
function CheckBox:toggle()
  self:disable()
  if self.value==true then
    self.value=false
    self.text=string.rep(" ",self.width)
  else
    self.value=true
    local size=math.floor((self.width-unicode.wlen(self.char))/2)
    local size2=math.ceil((self.width-unicode.wlen(self.char))/2)
    self.text=string.rep(" ",size)..self.char..string.rep(" ",size2)
  end
  self:render()
  os.sleep(.5)
  self:enable()
end

---Progressbar LineObject
---@class Progressbar:LineObject
---@field width integer
---@field text string
---@field value number Percentage, from 0 to 1
---@field setValue function 
Progressbar={}
Progressbar.__index=Progressbar
---@param pos2? Pos2
---@param width? integer defaults to 10
---@param col2? Color2 defaults to `tgl.defaults.colors2.progressbar`
---@return Progressbar
function Progressbar:new(pos2,width,col2)
  local obj=setmetatable({},Progressbar)
  obj.type="Progressbar"
  obj.pos2=pos2 or Pos2:new()
  obj.width=tonumber(width) or 10
  obj.col2=col2 or tgl.defaults.colors2.progressbar
  obj.text=string.rep(" ",obj.width)
  obj.value=0
  return obj
end
function Progressbar:render()
  local fill=math.floor(self.width*self.value)
  self.text=string.rep(tgl.defaults.chars.full,fill)..string.rep(" ",self.width-fill)
  local prev=tgl.changeToColor2(self.col2)
  gpu.set(self.pos2.x,self.pos2.y,self.text)
  tgl.changeToColor2(prev,true)
end
---Set progressbar to percentage
---@param num number Percent from 0 to 1
---@param render boolean Should it render immediately
---@return boolean
function Progressbar:setValue(num,render)
  if not tonumber(num) then return false end
  if num>1 or num<0 then return false end
  self.value=num
  if render then self:render() end
  return true
end

---Create a simple window with a topbar, title and a close button.
---`window.objects.topbar.objects.close_button` fires `"close"..title` event.
---@param size2 Size2
---@param title? string Defaults to `"Untitled"`
---@param barcol? Color2 Color2 of topbar frame
---@param framecol? Color2 of window background
---@return Frame
function tui.window(size2,title,barcol,framecol)
  if not size2 then return nil end
  if not title then title="Untitled" end
  if not barcol then barcol=Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue) end
  if not framecol then framecol=tgl.defaults.colors2.white end
  local close_button=tgl.EventButton(" X ","close"..title,nil,Pos2:new(size2.sizeX-2,1),tgl.defaults.colors2.close)
  local title_text=Text:new(title,barcol,Pos2:new((size2.sizeX-unicode.wlen(title))/2,1))
  local topbar=Frame:new({title_text=title_text,close_button=close_button},Size2:new(1,1,size2.sizeX,1),barcol)
  local frame=Frame:new({topbar=topbar},size2,framecol)
  return frame
end
---Same as tui.window(), but with outlined window.
---`window.objects.topbar.objects.close_button` fires "close"..title event.
---@param size2 Size2
---@param title? string Defaults to Untitled
---@param borders? string Defaults to `tgl.defaults.boxes.signle`
---@param barcol? Color2 Color2 of topbar frame
---@param framecol? Color2 of window background
---@return Frame
function tui.window_outlined(size2,title,borders,barcol,framecol)
  if not size2 then return nil end
  if not title then title="Untitled" end
  if not borders then borders=tgl.defaults.boxes.signle end
  if not barcol then barcol=Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue) end
  if not framecol then framecol=tgl.defaults.colors2.white end
  local close_button=tgl.EventButton(" X ","close"..title,nil,Pos2:new(size2.sizeX-2,1),tgl.defaults.colors2.close)
  local title_text=Text:new(title,barcol,Pos2:new((size2.sizeX-unicode.wlen(title))/2,1))
  local topbar=Frame:new({title_text=title_text,close_button=close_button},Size2:new(1,1,size2.sizeX,1),barcol)
  local frame=Frame:new({topbar=topbar},size2,framecol)
  frame.borders=borders
  return frame
end
---Same as tui.window(), but with returns a notification window with text and OK button
---`window.objects.close_button` fires "close"..title event.
---@param size2 Size2
---@param title? string Defaults to Untitled
---@param text? any 
---@param barcol? Color2 Color2 of topbar frame
---@param framecol? Color2 of window background
---@return Frame
function tui.notificationWindow(size2,title,text,barcol,framecol)
  if not size2 then return nil end
  if not title then title="Untitled" end
  if not text then text="Empty text" end
  if not barcol then barcol=Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue) end
  if not framecol then framecol=tgl.defaults.colors2.white end
  local close_button=tgl.EventButton(" OK ","close"..title,nil,Pos2:new((size2.sizeX-4)/2,size2.sizeY-1),Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue))
  local info_icon=Text:new("i",Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue),Pos2:new((size2.sizeX-unicode.wlen(text))/2-2,3))
  local text_label=Text:new(text,framecol,Pos2:new((size2.sizeX-unicode.wlen(text))/2,3))
  local title_text=Text:new(title,barcol,Pos2:new((size2.sizeX-unicode.wlen(title))/2,1))
  local topbar=Frame:new({title_text=title_text},Size2:new(1,1,size2.sizeX,1),barcol)
  local frame=Frame:new({topbar=topbar,icon=info_icon,text=text_label,close_button=close_button},size2,framecol)
  return frame
end

return tui
--[[
action window-> return result
file select
color select
tab function: file|edit: select menu -> "string"
]]