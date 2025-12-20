--Tgl UI Elements
local tgl=require("tgl")
local event=require("event")
local unicode=require("unicode")
local tui={}
tui.ver="1.2"
--moved from tgl.defaults

---Checkbox object
---@class tui.CheckBox:tgl.LineObjectInteractable
---@field char string Clicked character
---@field width integer Length
---@field handler function
---@field toggle function
---@field value boolean Checked/not
---@field text string
tui.CheckBox=setmetatable({},{__index=tgl.LineObjectInteractable})
tui.CheckBox.__index=tui.CheckBox
---@param pos2? tgl.Pos2
---@param col2? tgl.Color2
---@param width? integer
---@param char? string
---@return tui.CheckBox
function tui.CheckBox:new(pos2,col2,width,char)
  local obj=setmetatable({},self)
  obj.type="CheckBox"
  obj.pos2=pos2 or tui.Pos2:new()
  obj.col2=col2 or tui.Color2:new()
  obj.char=char or "*"
  obj.enabled=false
  obj.value=false
  obj.z_index=0
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
function tui.CheckBox:enable()
  if self.hidden or self.enabled then return end
  self.enabled=true
  event.listen("touch",self.handler)
end
function tui.CheckBox:disable()
  self.enabled=false
  event.ignore("touch",self.handler)
end
function tui.CheckBox:render()
  if self.hidden then return end
  tgl.sys.renderer:set(self.pos2,self.text,self.col2,self.z_index)
end
function tui.CheckBox:toggle()
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
---@class tui.Progressbar:tgl.LineObject
---@field width integer
---@field text string
---@field value number Percentage, from 0 to 1
---@field setValue function 
tui.Progressbar=setmetatable({},{__index=tgl.LineObject})
tui.Progressbar.__index=tui.Progressbar
---@param pos2? tgl.Pos2
---@param width? integer defaults to 10
---@param col2? tgl.Color2 defaults to `tgl.defaults.colors2.progressbar`
---@return tui.Progressbar
function tui.Progressbar:new(pos2,width,col2)
  local obj=setmetatable({},tui.Progressbar)
  obj.type="Progressbar"
  obj.z_index=0
  obj.pos2=pos2 or tgl.Pos2:new()
  obj.width=tonumber(width) or 10
  obj.col2=col2 or tgl.defaults.colors2.progressbar
  obj.text=string.rep(" ",obj.width)
  obj.value=0
  return obj
end
function tui.Progressbar:render()
  local fill=math.floor(self.width*self.value)
  self.text=string.rep(tgl.defaults.chars.full,fill)..string.rep(" ",self.width-fill)
  tgl.sys.rendeerer:set(self.pos2,self.text,self.col2,self.z_index)
end
---Set progressbar to percentage
---@param num number Percent from 0 to 1
---@param render boolean Should it render immediately
---@return boolean
function tui.Progressbar:setValue(num,render)
  if not tonumber(num) then return false end
  if num>1 or num<0 then return false end
  self.value=num
  if render then self:render() end
  return true
end

---Create a simple window with a topbar, title and a close button.
---`window.objects.topbar.objects.close_button` fires `"close"..title` event.
---@param size2 tgl.Size2
---@param title? string Defaults to `"Untitled"`
---@param barcol? tgl.Color2 Color2 of topbar frame
---@param framecol? tgl.Color2 of window background
---@return tgl.Frame
function tui.window(size2,title,barcol,framecol)
  if not size2 then return nil end
  if not title then title="Untitled" end
  if not barcol then barcol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue) end
  if not framecol then framecol=tgl.defaults.colors2.white end
  local close_button=tgl.EventButton(" X ","close"..title,nil,tgl.Pos2:new(size2.sizeX-2,1),tgl.defaults.colors2.close)
  local title_text=tgl.Text:new(title,barcol,tgl.Pos2:new((size2.sizeX-unicode.wlen(title))/2,1))
  local topbar=tgl.Frame:new({title_text=title_text,close_button=close_button},tgl.Size2:new(1,1,size2.sizeX,1),barcol)
  local frame=tgl.Frame:new({topbar=topbar},size2,framecol)
  return frame
end
---Same as tui.window(), but with outlined window.
---`window.objects.topbar.objects.close_button` fires "close"..title event.
---@param size2 tgl.Size2
---@param title? string Defaults to Untitled
---@param borders? string Defaults to `tgl.defaults.boxes.signle`
---@param barcol? tgl.Color2 Color2 of topbar frame
---@param framecol? tgl.Color2 of window background
---@return tgl.Frame
function tui.window_outlined(size2,title,borders,barcol,framecol)
  if not size2 then return nil end
  if not title then title="Untitled" end
  if not borders then borders=tgl.defaults.boxes.signle end
  if not barcol then barcol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue) end
  if not framecol then framecol=tgl.defaults.colors2.white end
  local close_button=tgl.EventButton(" X ","close"..title,nil,tgl.Pos2:new(size2.sizeX-2,1),tgl.defaults.colors2.close)
  local title_text=tgl.Text:new(title,barcol,tgl.Pos2:new((size2.sizeX-unicode.wlen(title))/2,1))
  local topbar=tgl.Frame:new({title_text=title_text,close_button=close_button},tgl.Size2:new(1,1,size2.sizeX,1),barcol)
  local frame=tgl.Frame:new({topbar=topbar},size2,framecol)
  frame.borders=borders
  return frame
end
---Same as tui.window(), but with returns a notification window with text and OK button
---`window.objects.close_button` fires "close"..title event.
---@param size2 tgl.Size2
---@param title? string Defaults to Untitled
---@param text? any 
---@param barcol? tgl.Color2 Color2 of topbar frame
---@param framecol? tgl.Color2 of window background
---@return Frame
function tui.notificationWindow(size2,title,text,barcol,framecol)
  if not size2 then return nil end
  if not title then title="Untitled" end
  if not text then text="Empty text" end
  if not barcol then barcol=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue) end
  if not framecol then framecol=tgl.defaults.colors2.white end
  local close_button=tgl.EventButton(" OK ","close"..title,nil,tgl.Pos2:new((size2.sizeX-4)/2,size2.sizeY-1),tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue))
  local info_icon=tgl.Text:new("i",tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue),tgl.Pos2:new((size2.sizeX-unicode.wlen(text))/2-2,3))
  local text_label=tgl.Text:new(text,framecol,tgl.Pos2:new((size2.sizeX-unicode.wlen(text))/2,3))
  local title_text=tgl.Text:new(title,barcol,tgl.Pos2:new((size2.sizeX-unicode.wlen(title))/2,1))
  local topbar=tgl.Frame:new({title_text=title_text},tgl.Size2:new(1,1,size2.sizeX,1),barcol)
  local frame=tgl.Frame:new({topbar=topbar,icon=info_icon,text=text_label,close_button=close_button},size2,framecol)
  return frame
end

---Create an auto-scaled, centered window size
---@param minW integer   minimal width
---@param minH integer   minimal height
---@param maxW? integer  optional maximum width
---@param maxH? integer  optional maximum height
---@param margin? integer minimal margin from screen edges
---@return tgl.Size2
function tui.autoSize2(minW, minH, maxW, maxH, margin)
  margin = margin or 4   -- distance from edges
  local screenW = tgl.defaults.screenSizeX
  local screenH = tgl.defaults.screenSizeY
  -- target size is 80% of screen, but not smaller than `min`
  local targetW = math.floor(screenW * 0.8)
  local targetH = math.floor(screenH * 0.6)
  -- clamp to min/max if provided
  targetW = math.max(targetW, minW)
  targetH = math.max(targetH, minH)
  if maxW then targetW = math.min(targetW, maxW) end
  if maxH then targetH = math.min(targetH, maxH) end
  -- ensure margins are respected
  targetW = math.min(targetW, screenW - 2 * margin)
  targetH = math.min(targetH, screenH - 2 * margin)
  -- centered position
  local posX = math.floor((screenW - targetW) / 2)
  local posY = math.floor((screenH - targetH) / 2)
  return tgl.Size2:newFromSize(posX, posY, targetW, targetH)
end

---Select a file from filesystem
---@param size2? tgl.Size2 Defaults to `tui.autoSize2(40,20)`
---@param startFolder? string starting folder, defaults to pwd
---@param startFile? string starting file, defaults to ""
---@param allowFolder? boolean Allow selecting folders, default=false
---@return string|nil
function tui.selectFile(size2,startFolder,startFile,allowFolder)
  local fs=require("filesystem")
  local current_dir=""
  local selected_file=startFile or ""
  if not startFolder or not fs.isDirectory(startFolder) then
    current_dir=os.getenv("PWD")
    if not current_dir then current_dir="/" end
  end
  if not allowFolder then allowFolder=false end
  if not size2 then size2=tui.autoSize2(40,20) end
  local gray=0xE1E1E1
  if require("component").gpu.getDepth()==4 then
    gray=tgl.defaults.colors16.lightgray
  end
  local topbar_col=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue)
  local filebg_col=tgl.Color2:new(0,gray)
  local filelua_col=tgl.Color2:new(tgl.defaults.colors16.darkgreen,gray)
  local filetmg_col=tgl.Color2:new(tgl.defaults.colors16.magenta,gray)
  local dir_col=tgl.Color2:new(tgl.defaults.colors16.darkblue,gray)

  local topbar=tgl.Frame:new({title=tgl.Text:new("Select file",topbar_col,tgl.Pos2:new((size2.sizeX-11)/2,1))},
  tgl.Size2:newFromSize(1,1,size2.sizeX,1),topbar_col)
  --!!!TODO: InputField for folder
  local selected_text=tgl.Text:new("Selected: "..current_dir..selected_file,tgl.defaults.colors2.white,tgl.Pos2:new(2,2))
  local file_frame=tgl.ScrollFrame:new({},tgl.Size2:newFromSize(1,3,size2.sizeX,size2.sizeY-3),filebg_col)
  --set default scroll to 0; setup later
  file_frame.maxScroll=0
  local function updateSelectedText()
    selected_text:updateText("Selected: "..fs.concat(current_dir,selected_file))
  end
  local function getFileButton(filename, absolutePath,y,col)
    local isDir=fs.isDirectory(absolutePath)
    local btn=tgl.Button:new(filename,nil,tgl.Pos2:new(1,y),col)
    btn.callback=function ()
      if (selected_file~=filename and not isDir) or (selected_file~=filename and isDir and allowFolder)then
        --select
        selected_file=filename
        updateSelectedText()
      elseif selected_file~=filename and isDir and allowFolder==false then
        --open
        selected_file=""
        current_dir=absolutePath
        event.push("tui_open_dir",absolutePath)
        btn:disable()
      elseif selected_file==filename and isDir then
        --open
        selected_file=""
        current_dir=absolutePath
        event.push("tui_open_dir",absolutePath)
        btn:disable()
      else
        --nothing?
      end
    end
    btn.onClick=function()
      btn:disable()
      os.sleep(.5)
      btn:enable()
    end
    return btn
  end
  local function getFiles()
    --remove old
    for k,v in pairs(file_frame.objects) do
      file_frame:remove(k)
    end
    file_frame:render()
    local list=fs.list(current_dir)
    if not list then
      tgl.util.log("Couldn't list files!","TGL-UI/selectFile")
      return
    end
    --sorting
    local dirs={}
    local files={}
    for file in list do
      if fs.isDirectory(fs.concat(current_dir,file)) then
        table.insert(dirs, file)
      else
        table.insert(files, file)
      end
    end
    table.sort(dirs, function(a,b) return a:lower()<b:lower() end)
    table.sort(files,function(a,b) return a:lower()<b:lower() end)
    --add .. if not root
    local y=1
    if current_dir~="" and current_dir~="/" then
      file_frame:add(getFileButton("..",fs.concat(current_dir,".."),y,dir_col),"..")
      file_frame.objects[".."]:enable()
      y=y+1
    end
    for _,file in pairs(dirs) do
      file_frame:add(getFileButton(file,fs.concat(current_dir,file),y,dir_col),file)
      file_frame.objects[file]:enable()
      y=y+1
    end
    for _,file in pairs(files) do
      local col=filebg_col
      if string.match(file,".lua") then col=filelua_col
      elseif string.match(file,".tmg") then col=filetmg_col end
      file_frame:add(getFileButton(file,fs.concat(current_dir,file),y,col),file)
      file_frame.objects[file]:enable()
      y=y+1
    end
    if y>file_frame.size2.sizeY then
      file_frame.maxScroll=y-file_frame.size2.sizeY
    else file_frame.maxScroll=0 end
    file_frame.scroll=0
    file_frame:render()
    updateSelectedText()
  end

  local new_frame=tui.window(tgl.Size2:new(math.floor((size2.sizeX-20)/2),math.floor(size2.sizeY/2),20,5),"New file")
  new_frame:add(tgl.Text:new("Adding new file",tgl.defaults.colors2.white,tgl.Pos2:new(2,2)))
  new_frame:add(tgl.InputField:new("[ enter filename]",tgl.Pos2:new(2,3),filebg_col),"input")
  new_frame:add(tgl.Text:new("Directory:",tgl.defaults.colors2.white,tgl.Pos2:new(4,4)))
  new_frame:add(tgl.CheckBox:new(tgl.Pos2:new(14,4),tgl.Color2:new(tgl.defaults.colors16.darkgreen,
  tgl.defaults.colors16.lightgray),2,tgl.defaults.chars.check),"checkbox")
  new_frame:add(tgl.EventButton("[Submit]","tgl_file_new_submit",nil,
  tgl.Pos2:new(6,5),tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue)),"submit")
  new_frame.objects.topbar.objects.close_button.onClick=nil
  new_frame.objects.submit.onClick=nil
  new_frame.ignoreOpen=true
  new_frame.hidden=true

  local function getNewFile()
    local prev_aa=tgl.sys.getActiveArea()
    tgl.sys.setActiveArea(new_frame.size2)
    new_frame:open(true) --ignore because file_frame will be rerendered
    local id=event.pullMultiple("tgl_file_new_submit","closeNew file")
    local text=new_frame.objects.input.text
    local isdir=new_frame.objects.checkbox.value
    new_frame:close()
    new_frame.objects.input.text=""
    new_frame.objects.checkbox.value=false
    tgl.sys.setActiveArea(prev_aa)
    if id=="tgl_file_new_submit" then
      return fs.concat(current_dir,text),isdir
    else return nil end
  end

  local new_button=tgl.EventButton("[New]","tui_file_new",nil,
  tgl.Pos2:new(1,size2.sizeY),tgl.defaults.colors2.white)
  local submit_button=tgl.EventButton("[Submit]","tui_file_submit","",
  tgl.Pos2:new((size2.sizeX-17)/2,size2.sizeY),tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue))
  local cancel_button=tgl.EventButton("[Cancel]","tui_file_cancel","",
  tgl.Pos2:new((size2.sizeX-17)/2+9,size2.sizeY),tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.red))
  local main_frame=tgl.Frame:new({
    topbar=topbar,selected_text=selected_text,file_frame=file_frame,
    submit_button=submit_button,cancel_button=cancel_button,
    new_button=new_button,new_frame=new_frame
  },size2,tgl.defaults.colors2.white)
  main_frame:open()
  tgl.sys.setActiveArea(size2)
  local run=true
  local cancel=false
  getFiles()
  while run do
    local id,v=event.pullMultiple("tui_file_submit","tui_file_cancel","tui_open_dir","tui_file_new")
    if id=="tui_file_submit" then
      os.sleep(.5)
      run=false
    elseif id=="tui_file_cancel" then
      os.sleep(.5)
      cancel=true
      run=false
    elseif id=="tui_file_new" then
      file_frame:disable()
      file_frame:disableAll()
      local filename,isdir=getNewFile()
      if filename then
        if isdir then fs.makeDirectory(filename)
        else
          io.open(filename,"w"):write(""):close()
        end
      end
      file_frame:enable()
      file_frame:enableAll()
      getFiles()
      --enable fileframe
    else getFiles()
    end
  end
  --exit
  main_frame:close()
  main_frame=nil
  file_frame:disableAll()
  file_frame=nil
  tgl.sys.resetActiveArea()
  if not cancel then return fs.concat(current_dir,selected_file)
  else return nil end
end
---Select Color2 with input
function tui.selectColor2RGB()

end
---Select Color2 with palette
function tui.selectColor2Palette()

end
return tui
--[[
action window-> return result
file select
color select
tab function: file|edit: select menu -> "string"
]]