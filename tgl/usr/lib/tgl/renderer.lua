local unicode=require("unicode")
local event=require("event")
return function(tgl)
tgl.sys.renderer=nil --where system renderer is stored
tgl.sys.renderThread=nil --renderthread
tgl.sys.resetKeybind=18 --Ctrl+R for reset
---@class tgl.Renderer
---@field type string
---@field gpu table
---@field queue table
---@field nextQueue table
---@field dirty boolean
---@field stopped boolean
---@field rendering boolean
---@field activeBuffer integer
---@field frameCounter integer
---@field frameFreq number
---@field resetKeybindEnabled boolean
tgl.Renderer={}
tgl.Renderer.cmd={}
tgl.Renderer.__index=tgl.Renderer
---@param frequency number
function tgl.Renderer:init(frequency)
  if type(tgl.sys.renderer)=="table" then
    tgl.util.log("Couldn't init new renderer - already present","Renderer")
    return
  end
  local obj=setmetatable({},self)
  obj.type="Renderer"
  obj.gpu=require("component").gpu
  obj.queue={}
  obj.nextQueue={}
  obj.frameCounter=0
  obj.frameFreq=tonumber(frequency) or (1/20)
  obj.dirty=false
  obj.stopped=false
  obj.rendering=false
  obj.activeBuffer=obj.gpu.getActiveBuffer()
  obj.resetKeybindEnabled=true
  tgl.sys.renderer=obj
end
---internal functions

---If enabled, Ctrl+R will reset
function tgl.Renderer.resetKeybind(_,_,key1,key2)
  if key1==tgl.sys.resetKeybind then
    tgl.sys.renderer:resetCursor()
  end
end

function tgl.Renderer:start()
  if self.timer then return end
  self.timer=event.timer(self.frameFreq,function()
    if self.stopped then return end
    if self.dirty and not self.rendering then
      self:render()
    end
  end,math.huge)
  if self.resetKeybindEnabled then event.listen("key_down",self.resetKeybind) end
end
function tgl.Renderer:stop() self.stopped=true end --??
function tgl.Renderer:resume() self.stopped=false end
function tgl.Renderer:finish()
  if not self.timer then return false end
  self:freeAllBuffers()
  if self.resetKeybindEnabled then event.ignore("key_down",self.resetKeybind) end
  return event.cancel(self.timer)
end
function tgl.Renderer:addCmd(cmd)
  if type(cmd)~="table" then
    tgl.util.log("Corrupted command add: "..type(cmd))
    return false
  end
  if not cmd.z_index then cmd.z_index=0 end
  if not cmd.buffer then cmd.buffer=0 end
  if cmd.cmd=="bufcopy" then cmd.buffer=nil end
  self.frameCounter=self.frameCounter+1
  cmd.order=self.frameCounter
  if not self.rendering then
    table.insert(self.queue,cmd)
  else
    table.insert(self.nextQueue,cmd)
  end
  self.dirty=true
  return true
end
---@private
function tgl.Renderer:execCmd(cmd)
  if not cmd then return false end
  if not cmd.cmd then return false end
  if cmd.col2 then tgl.changeToColor2(cmd.col2,true) end
  if cmd.buffer then
    if cmd.buffer~=self.activeBuffer then
      if not self.gpu.buffers()[cmd.buffer] and cmd.buffer~=0 then
        tgl.util.log("Trying to write on non-allocated buffer! ("..cmd.buffer..")","Renderer")
        return false
      else
        self.activeBuffer=cmd.buffer
        self.gpu.setActiveBuffer(cmd.buffer)
      end
    end
  end
  if cmd.cmd=="set" then
    if not cmd.vertical then
      return self.gpu.set(cmd.pos2.x,cmd.pos2.y,cmd.value)
    end
    --vertical
    local len=unicode.wlen(cmd.value)
    for i=1,len do
      self.gpu.set(cmd.pos2.x,cmd.pos2.y+i-1,unicode.sub(cmd.value,i,i))
    end
    return true
  elseif cmd.cmd=="fill" then
    return self.gpu.fill(cmd.size2.x1,cmd.size2.y1,cmd.size2.sizeX,cmd.size2.sizeY,cmd.char)
  elseif cmd.cmd=="copy" then
    return self.gpu.copy(cmd.src.x1,cmd.src.y1,cmd.src.sizeX,cmd.src.sizeY,cmd.dst.x,cmd.dst.y)
  elseif cmd.cmd=="bufcopy" then
    return self.gpu.bitblt(cmd.dst,cmd.size2.x1,cmd.size2.y1,cmd.size2.sizeX,cmd.size2.sizeY,cmd.src,cmd.bufpos2.x,cmd.bufpos2.y)
  elseif cmd.cmd=="reset" then
    tgl.changeToColor2(cmd.col2)
    self.gpu.setActiveBuffer(0)
    return true
  elseif cmd.cmd=="freebuffer" then
    return self.gpu.freeBuffer(cmd.id)
  elseif cmd.cmd=="freebuffers" then
    self.gpu.freeAllBuffers() return true
  else
    tgl.util.log("Unknown cmd: "..require("serialization").serialize(cmd),"Renderer")
  end
end
---@private
function tgl.Renderer:sortQueue()
  if #self.nextQueue>0 then
    for i=1,#self.nextQueue do
      table.insert(self.queue,self.nextQueue[i])
    end
    self.nextQueue={}
  end
  table.sort(self.queue,function(a,b)
    if a.z_index~=b.z_index then
      return a.z_index<b.z_index
    end
    return a.order<b.order
  end)
end
---@private
function tgl.Renderer:render()
  self.rendering=true
  self:sortQueue()
  local prev_pos2,prev_col2=tgl.getCursorState()
  local success, err=pcall(function()
    for i=1,#self.queue do
      if not self:execCmd(self.queue[i]) then
        tgl.util.log("Failed executing: "..require("serialization").serialize(self.queue[i]),"Renderer")
      end
    end
  end)
  if not success then
    tgl.util.log("ERROR rendering frame: "..err,"Renderer")
  end
  self.gpu.setActiveBuffer(self.activeBuffer)
  tgl.setCursorState(prev_pos2,prev_col2,true)
  self.frameCounter=0
  self.queue={}
  self.dirty=false
  self.rendering=false
  event.push("renderDone")
end

function tgl.Renderer:waitForAll()
  event.pull("renderDone")
end

---public functions

---alias for gpu.set 
---@param x integer
---@param y integer
---@param value string
---@param col2? tgl.Color2
---@param z_index? integer
---@param buf? integer
---@return boolean
function tgl.Renderer:setPoint(x,y,value,col2,z_index,vertical,buf)
  if type(x)~="number" or type(y)~="number" or not value then
    tgl.util.log("Illegal setPoint command: x="..tostring(x).." y="..tostring(y).." "..tostring(value),"Renderer")
    return false
  end
  self:addCmd({cmd="set",pos2=tgl.Pos2:new(x,y),value=value,col2=col2,z_index=z_index or 0,vertical=vertical,buffer=buf})
  return true
end

---Write text to string
---@param pos2 tgl.Pos2
---@param text string
---@param col2? tgl.Color2
---@param z_index? integer
---@param vertical? boolean Defaults to false
---@param buf? integer 
---@return boolean
function tgl.Renderer:set(pos2,text,col2,z_index,vertical,buf)
  if type(pos2)~="table" or not text then
    tgl.util.log("Illegal text command: pos2.type="..type(pos2).." "..tostring(text),"Renderer")
    return false
  end
  self:addCmd({cmd="set",pos2=pos2,value=text,col2=col2,z_index=z_index,vertical=vertical,buffer=buf})
  return true
end

---Fills an area
---@param size2 tgl.Size2
---@param char string
---@param col2 tgl.Color2
---@param z_index? integer
---@param buf? integer
---@return boolean
function tgl.Renderer:fill(size2,char,col2,z_index,buf)
  if not char then char=" " end
  if type(size2)~="table" or type(char)~="string" then
    tgl.util.log("Illegal fill command: size2.type="..type(size2).." c="..tostring(char),"Renderer")
    return false
  end
  self:addCmd({cmd="fill",size2=size2,char=char,col2=col2,z_index=z_index,buffer=buf})
  return true
end

---Copy from buffer to buffer
---@param src integer
---@param dst integer
---@param copySize2 tgl.Size2
---@param bufpos2? tgl.Pos2
---@param z_index? integer
---@return boolean
function tgl.Renderer:bufcopy(src,dst,copySize2,z_index,bufpos2)
  if type(src)~="number" or type(dst)~="number" or type(copySize2)~="table" then
    tgl.util.log("Illegal buffer copy(bitblt)","Renderer")
    return false
  end
  if not bufpos2 then bufpos2=tgl.Pos2:new(1,1) end
  self:addCmd({cmd="bufcopy",src=src,dst=dst,size2=copySize2,bufpos2=bufpos2,z_index=z_index})
  return true
end

---Screen copy
---@param src_size2 tgl.Size2
---@param dst_pos2 tgl.Pos2
---@param buf? integer
---@return boolean
function tgl.Renderer:copy(src_size2,dst_pos2,buf)
  if type(src_size2)~="table" or type(dst_pos2)~="table" then 
    tgl.util.log("Illegal copy command: src_size2.type="..type(src_size2).." dst_pos2.type="..type(dst_pos2),"Renderer")
    return false
  end
  self:addCmd({cmd="copy",src=src_size2,dst=dst_pos2,buffer=buf})
  return true
end

---@param pos2 tgl.Pos2
---@param buf? integer
---@return string
---@return tgl.Color2
function tgl.Renderer:get(pos2,buf)
  if type(pos2)~="table" then
    return nil,nil
  end
  if buf then
    if not self.gpu.buffers()[buf] then
      tgl.util.log("Getting from nil buffer: "..buf,"Renderer")
      return nil,nil
    end
    self.gpu.setActiveBuffer(buf)
  end
  local char,fg_col,bg_col=self.gpu.get(pos2.x,pos2.y)
  if buf then
    self.gpu.setActiveBuffer(self.activeBuffer)
  end
  return char,tgl.Color2:new(fg_col,bg_col)
end

function tgl.Renderer:getPoint(x,y,buf)
  if type(x)~="number" or type(y)~="number" then
    return nil,nil
  end
  if buf then
    if not self.gpu.buffers()[buf] then
      tgl.util.log("Getting from nil buffer: "..buf,"Renderer")
      return nil,nil
    end
    self.gpu.setActiveBuffer(buf)
  end
  local char,fg_col,bg_col=self.gpu.get(x,y)
  if buf then
    self.gpu.setActiveBuffer(self.activeBuffer)
  end
  return char,tgl.Color2:new(fg_col,bg_col)
end

---Buffers

---Allocate new buffer
---@param sizeX integer
---@param sizeY integer
---@return boolean,integer|nil
function tgl.Renderer:allocateBuffer(sizeX,sizeY)
  if type(sizeX)~="number" and type(sizeY)~="number" then
    tgl.util.log("Unvalid buffer allocation: "..tostring(sizeX).." x "..tostring(sizeY),"Renderer")
    return false
  end
  local size=sizeX*sizeY
  if self.gpu.freeMemory()<size then
    tgl.util.log("Couldn't allocate buffer: free="..self.gpu.freeMemory().." requested="..size,"Renderer")
    return false
  end
  local buf=self.gpu.allocateBuffer(sizeX,sizeY)
  return true,buf
end

---@param id integer
---@return boolean
function tgl.Renderer:freeBuffer(id)
  if id>0 and self:buffers()[id] then
    self:addCmd({cmd="freebuffer",id=id})
    return true
  end
  return false
end

function tgl.Renderer:buffers()
  return self.gpu.buffers()
end

function tgl.Renderer:freeAllBuffers()
  self:addCmd({cmd="freebuffers"})
end

function tgl.Renderer:resetCursor(col2)
  self:addCmd({cmd="reset",col2=col2 or tgl.defaults.colors2.black})
end

return tgl end
---tgl.sys.renderer:set(1,1,"hello",col2,z_index)