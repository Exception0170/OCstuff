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
---@field clipRegion tgl.Size2|nil
---@field _zbuf table z-index of last write per screen cell, indexed (y-1)*_sw+x
---@field _sw integer screen width captured at init
tgl.Renderer={}
tgl.Renderer.cmd={}
tgl.Renderer.customCommands=true
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
  obj.clipRegion=nil
  obj._sw=tgl.defaults.screenSizeX
  obj._zbuf={}
  tgl.sys.renderer=obj
end
---internal functions

---If enabled, Ctrl+R will reset
function tgl.Renderer.resetKeybind(_,_,key1,key2)
  if key1==tgl.sys.resetKeybind and tgl.sys.renderer.resetKeybindEnabled then
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
  event.listen("key_down",self.resetKeybind)
end
function tgl.Renderer:stop() self.stopped=true end
function tgl.Renderer:resume() self.stopped=false end
---Resume and immediately execute any queued commands.
function tgl.Renderer:flush(buffered)
  if buffered then self._buffered=true end
  if self._deferFlush then return end
  self.stopped=false
  if self.dirty and not self.rendering then
    self:render()
  end
end
function tgl.Renderer:finish()
  if not self.timer then return false end
  event.ignore("key_down",self.resetKeybind)
  local ok=event.cancel(self.timer)
  self.timer=nil
  self.stopped=false
  self.queue={}
  self.nextQueue={}
  self.dirty=false
  self.gpu.freeAllBuffers()
  self.activeBuffer=0
  return ok
end
function tgl.Renderer:addCmd(cmd)
  if type(cmd)~="table" then
    tgl.util.log("Corrupted command add: "..type(cmd))
    return false
  end
  if not cmd.z_index then cmd.z_index=0 end
  if not cmd.buffer then cmd.buffer=0 end
  if cmd.cmd=="bufcopy" then cmd.buffer=nil end
  cmd.clipRegion=self.clipRegion
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
  -- Reject invisible draws before switching buffers or issuing GPU color calls.
  local clip=cmd.clipRegion
  if clip and cmd.cmd=="fill" then
    local s=cmd.size2
    if s.x2<clip.x1 or s.x1>clip.x2 or s.y2<clip.y1 or s.y1>clip.y2 then return true end
  elseif clip and cmd.cmd=="set" then
    local x,y=cmd.pos2.x,cmd.pos2.y
    if not cmd.vertical then
      if y<clip.y1 or y>clip.y2 or x>clip.x2
      or (x<clip.x1 and x+unicode.wlen(cmd.value)-1<clip.x1) then return true end
    elseif x>clip.x2 or y>clip.y2 or y+unicode.len(cmd.value)-1<clip.y1 then return true end
  end
  local buffer=cmd.buffer
  if buffer==0 and self._drawBuffer then buffer=self._drawBuffer end
  if buffer then
    if buffer~=self.activeBuffer then
      if not self:hasBuffer(buffer) then
        tgl.util.log("Trying to write on non-allocated buffer! ("..cmd.buffer..")","Renderer")
        return false
      else
        self.activeBuffer=buffer
        self.gpu.setActiveBuffer(buffer)
      end
    end
  end
  if cmd.col2 then tgl.changeToColor2(cmd.col2,true) end
  if cmd.cmd=="set" then
    local x,y=cmd.pos2.x,cmd.pos2.y
    local value=cmd.value
    local clip=cmd.clipRegion
    if not cmd.vertical then
      if clip then
        if y<clip.y1 or y>clip.y2 then return true end
        local chars={}
        local startX=math.max(x,clip.x1)
        for i=1,unicode.len(value) do
          local char=unicode.sub(value,i,i)
          local width=unicode.wlen(char)
          if x>clip.x2 then break end
          if x>=clip.x1 and x+width-1<=clip.x2 then
            table.insert(chars,char)
          elseif x+width-1>=clip.x1 then
            -- A wide character crossing the edge leaves blank cells.
            table.insert(chars,string.rep(" ",math.min(x+width-1,clip.x2)-math.max(x,clip.x1)+1))
          end
          x=x+width
        end
        x=startX
        value=table.concat(chars)
      end
      if value=="" then return true end
      local ok=self.gpu.set(x,y,value)
      if ok and cmd.buffer==0 then
        local z=cmd.z_index or 0
        local len=unicode.wlen(value)
        for i=0,len-1 do
          if x+i>=1 and x+i<=self._sw then self._zbuf[(y-1)*self._sw+x+i]=z end
        end
      end
      return ok
    end
    --vertical: one character per row, including wide characters
    for i=1,unicode.len(value) do
      local cy=y+i-1
      local char=unicode.sub(value,i,i)
      local width=unicode.wlen(char)
      if not clip or (cy>=clip.y1 and cy<=clip.y2 and x>=clip.x1 and x+width-1<=clip.x2) then
        local ok=self.gpu.set(x,cy,char)
        if ok and cmd.buffer==0 then
          for dx=0,width-1 do
            if x+dx>=1 and x+dx<=self._sw then self._zbuf[(cy-1)*self._sw+x+dx]=cmd.z_index or 0 end
          end
        end
      end
    end
    return true
  elseif cmd.cmd=="fill" then
    local ok,ix1,iy1,ix2,iy2
    if cmd.clipRegion then
      ix1=math.max(cmd.size2.x1,cmd.clipRegion.x1)
      iy1=math.max(cmd.size2.y1,cmd.clipRegion.y1)
      ix2=math.min(cmd.size2.x2,cmd.clipRegion.x2)
      iy2=math.min(cmd.size2.y2,cmd.clipRegion.y2)
      if ix1>ix2 or iy1>iy2 then return true end
      ok=self.gpu.fill(ix1,iy1,ix2-ix1+1,iy2-iy1+1,cmd.char)
    else
      ix1=cmd.size2.x1 iy1=cmd.size2.y1 ix2=cmd.size2.x2 iy2=cmd.size2.y2
      ok=self.gpu.fill(ix1,iy1,cmd.size2.sizeX,cmd.size2.sizeY,cmd.char)
    end
    if cmd.buffer==0 then
      local z=cmd.z_index or 0
      for y=iy1,iy2 do
        for x=ix1,ix2 do self._zbuf[(y-1)*self._sw+x]=z end
      end
    end
    return ok
  elseif cmd.cmd=="copy" then
    return self.gpu.copy(cmd.src.x1,cmd.src.y1,cmd.src.sizeX,cmd.src.sizeY,cmd.dst.x,cmd.dst.y)
  elseif cmd.cmd=="bufcopy" then
    local dst=cmd.dst==0 and self._drawBuffer or cmd.dst
    local src=cmd.src==0 and self._drawBuffer or cmd.src
    return self.gpu.bitblt(dst,cmd.size2.x1,cmd.size2.y1,cmd.size2.sizeX,cmd.size2.sizeY,src,cmd.bufpos2.x,cmd.bufpos2.y)
  elseif cmd.cmd=="reset" then
    tgl.changeToColor2(cmd.col2)
    self.gpu.setActiveBuffer(0)
    self.activeBuffer=0
    return true
  elseif cmd.cmd=="freebuffer" then
    local ok=self.gpu.freeBuffer(cmd.id)
    self.activeBuffer=self.gpu.getActiveBuffer()
    return ok
  elseif cmd.cmd=="setbuffer" then
    self.gpu.setActiveBuffer(cmd.id)
    self.activeBuffer=cmd.id
    return true
  elseif cmd.cmd=="freebuffers" then
    self.gpu.freeAllBuffers()
    self.activeBuffer=0
    return true
  elseif type(tgl.Renderer.cmd[cmd.cmd])=="function" then
    return tgl.Renderer.cmd[cmd.cmd](self,cmd)
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
-- Clipped text/fills need only their damaged screen area preserved and presented.
-- Copies and custom commands keep the full-screen path because they may read elsewhere.
local function presentationRegion(renderer)
  local sw,sh=renderer._sw,tgl.defaults.screenSizeY
  local region=nil
  for _,cmd in ipairs(renderer.queue) do
    if cmd.buffer==0 or (cmd.cmd=="bufcopy" and (cmd.src==0 or cmd.dst==0)) then
      if cmd.cmd~="set" and cmd.cmd~="fill" then
        return {x1=1,y1=1,x2=sw,y2=sh}
      end
      local clip=cmd.clipRegion
      if not clip then
        if cmd.cmd=="fill" then clip=cmd.size2
        else
          local x,y=cmd.pos2.x,cmd.pos2.y
          clip={x1=x,y1=y,x2=x+unicode.wlen(cmd.value)-1,
            y2=y+(cmd.vertical and unicode.len(cmd.value) or 1)-1}
        end
      end
      local x1,y1=math.max(1,clip.x1),math.max(1,clip.y1)
      local x2,y2=math.min(sw,clip.x2),math.min(sh,clip.y2)
      if x1<=x2 and y1<=y2 then
        if not region then region={x1=x1,y1=y1,x2=x2,y2=y2}
        else
          region.x1=math.min(region.x1,x1) region.y1=math.min(region.y1,y1)
          region.x2=math.max(region.x2,x2) region.y2=math.max(region.y2,y2)
        end
      end
    end
  end
  return region
end
---@private
function tgl.Renderer:render()
  self.rendering=true
  self:sortQueue()
  local prev_pos2,prev_col2=tgl.getCursorState()
  local buffered=self._buffered
  self._buffered=nil
  -- A single temporary screen-sized buffer also preserves queued widget updates.
  for _,cmd in ipairs(self.queue) do
    if cmd.cmd=="freebuffers" then buffered=false end
  end
  local present=buffered and presentationRegion(self) or nil
  if present then
    local sw,sh=self.gpu.getResolution()
    local ok,buf=pcall(function()
      if self.gpu.freeMemory()<sw*sh then return nil end
      return self.gpu.allocateBuffer(sw,sh)
    end)
    if ok and type(buf)=="number" and buf>0 then
      self._drawBuffer=buf
    end
  end
  local success, err=pcall(function()
    if self._drawBuffer then
      self.gpu.bitblt(self._drawBuffer,present.x1,present.y1,present.x2-present.x1+1,
        present.y2-present.y1+1,0,present.x1,present.y1)
    end
    for i=1,#self.queue do
      if not self:execCmd(self.queue[i]) then
        tgl.util.log("Failed executing: "..require("serialization").serialize(self.queue[i]),"Renderer")
      end
    end
  end)
  if not success then
    tgl.util.log("ERROR rendering frame: "..err,"Renderer")
  end
  if self._drawBuffer then
    local buf=self._drawBuffer
    self._drawBuffer=nil
    local ok,copyErr=pcall(function()
      if success then
        self.gpu.bitblt(0,present.x1,present.y1,present.x2-present.x1+1,
          present.y2-present.y1+1,buf,present.x1,present.y1)
      end
    end)
    self.gpu.freeBuffer(buf)
    self.activeBuffer=self.gpu.getActiveBuffer()
    if not ok then tgl.util.log("ERROR presenting frame: "..tostring(copyErr),"Renderer") end
  end
  self.gpu.setActiveBuffer(self.activeBuffer)
  tgl.setCursorState(prev_pos2,prev_col2,true)
  self.queue={}
  self.dirty=#self.nextQueue>0
  if not self.dirty then self.frameCounter=0 end
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
    if not self:hasBuffer(buf) then
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

---Returns the z-index of the last command rendered at screen cell (x,y).
---@param x integer
---@param y integer
---@return integer
function tgl.Renderer:getZ(x,y)
  return self._zbuf[(y-1)*self._sw+x] or 0
end

function tgl.Renderer:getPoint(x,y,buf)
  if type(x)~="number" or type(y)~="number" then
    return nil,nil
  end
  if buf then
    if not self:hasBuffer(buf) then
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
  if type(sizeX)~="number" or type(sizeY)~="number" then
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
  if id>0 and self:hasBuffer(id) then
    self:addCmd({cmd="freebuffer",id=id})
    return true
  end
  return false
end

function tgl.Renderer:setBuffer(id)
  if id>=0 and self:hasBuffer(id) then
    self:addCmd({cmd="setbuffer",id=id})
    return true
  end
  tgl.util.log("Trying to set unvalid buffer: "..tostring(id),"Renderer")
  return false
end

---Buffer indexes are values in gpu.buffers(), not table keys.
function tgl.Renderer:hasBuffer(id)
  if id==0 then return true end
  for _,buf in ipairs(self.gpu.buffers()) do
    if buf==id then return true end
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

---Set clipping region for rendering
---@param size2? tgl.Size2 nil to disable clipping
function tgl.Renderer:setClipRegion(size2)
  self.clipRegion=size2
end

---Get current clipping region
---@return tgl.Size2|nil
function tgl.Renderer:getClipRegion()
  return self.clipRegion
end

return tgl end
---tgl.sys.renderer:set(1,1,"hello",col2,z_index)
