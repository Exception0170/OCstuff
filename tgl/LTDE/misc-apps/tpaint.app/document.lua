--Pixel editing for TMG images, including masks and extended half-blocks.
return function(tmg)
local document={}
document.__index=document
function document:new(width,height)
  local image=tmg.Image:new({sizeX=width,sizeY=height//2},4,"Untitled")
  image.rawdata=string.char(255):rep(width*height//2)
  return self:fromImage(image)
end
function document:fromImage(image)
  if image.size2.sizeX>256 or image.size2.sizeY*2>256 then
    return nil,"Images must be at most 256x256 pixels."
  end
  if image.extended then
    local rows,cells={},{}
    local pos=1
    local bytes=image.depth==4 and 1 or 2
    for i=1,image.size2.sizeX*image.size2.sizeY do
      local first=image.rawdata:byte(pos)
      local len=first and first>=0xC2 and (first<0xE0 and 2 or first<0xF0 and 3 or 4) or 1
      local char=tmg.getExtendedChar(image.rawdata:sub(pos,pos+len-1))
      pos=pos+len
      local upper,lower=image.rawdata:byte(pos,pos+bytes-1)
      if not upper or (bytes==2 and not lower) then return nil,"Incomplete image data." end
      if bytes==1 then upper,lower=upper//16,upper%16 end
      if char=="▄" then upper,lower=lower,upper
      elseif char=="█" then lower=upper
      elseif char==" " or char=="" then upper=lower
      elseif char~=tmg.char then return nil,"Only extended block and space characters can be edited yet." end
      cells[#cells+1]=string.char(3)..(bytes==1 and string.char(upper*16+lower) or string.char(upper,lower))
      if i%image.size2.sizeX==0 then rows[#rows+1]=table.concat(cells) cells={} end
      pos=pos+bytes
    end
    image.rawdata=table.concat(rows)
  end
  image.autoPreload=false
  return setmetatable({image=image,width=image.size2.sizeX,height=image.size2.sizeY*2,
    savedRaw=image.rawdata,savedDepth=image.depth,savedName=image.name,savedMask=image.mask,
    savedExtended=image.extended,history={},historyBytes=0},self)
end
function document:markSaved()
  self.savedRaw=self.image.rawdata self.savedDepth=self.image.depth self.savedName=self.image.name
  self.savedMask=self.image.mask self.savedExtended=self.image.extended
end
function document:changed()
  return self.image.rawdata~=self.savedRaw or self.image.depth~=self.savedDepth or self.image.name~=self.savedName
    or self.image.mask~=self.savedMask or self.image.extended~=self.savedExtended
end
local function historySize(state) return #state.raw+#(state.mask or "") end
local function restore(doc,state)
  doc.image.rawdata=state.raw doc.image.depth=state.depth doc.image.name=state.name
  doc.image.mask=state.mask doc.image.extended=state.extended
end
function document:commit()
  local previous=self.previous
  self.previous=nil
  if not previous or (previous.raw==self.image.rawdata and previous.depth==self.image.depth
  and previous.name==self.image.name and previous.mask==self.image.mask
  and previous.extended==self.image.extended) then return end
  self.history[#self.history+1]=previous
  self.historyBytes=self.historyBytes+historySize(previous)
  while #self.history>16 or self.historyBytes>128*1024 do
    self.historyBytes=self.historyBytes-historySize(table.remove(self.history,1))
  end
end
function document:begin()
  self:commit()
  self.previous={raw=self.image.rawdata,depth=self.image.depth,name=self.image.name,
    mask=self.image.mask,extended=self.image.extended}
end
function document:cancel()
  if not self.previous then return false end
  restore(self,self.previous) self.previous=nil
  return true
end
function document:undo()
  self:commit()
  local previous=table.remove(self.history)
  if not previous then return false end
  self.historyBytes=self.historyBytes-historySize(previous)
  restore(self,previous)
  return true
end
function document:to8bit()
  if self.image.depth==8 then return end
  local rows={}
  for y=1,self.height//2 do
    local row={}
    for x=1,self.width do
      local byte=self.image.rawdata:byte(((y-1)*self.width+x)*(self.image.extended and 2 or 1))
      row[x]=(self.image.extended and string.char(3) or "")..
        string.char(tmg.rgbToIndex(tmg.palette4bitToColor(byte//16)),
        tmg.rgbToIndex(tmg.palette4bitToColor(byte%16)))
    end
    rows[y]=table.concat(row)
  end
  self.image.rawdata=table.concat(rows) self.image.depth=8
end
function document:enableTransparency()
  if not self.image.mask then self.image.mask=string.rep("\0",(self.width*self.height//2+3)//4) end
end
function document:toExtended()
  if self.image.extended then return end
  local bytes=self.image.depth==4 and 1 or 2
  local rows={}
  for y=1,self.height//2 do
    local cells={}
    for x=1,self.width do
      local pos=((y-1)*self.width+x-1)*bytes+1
      cells[x]=string.char(3)..self.image.rawdata:sub(pos,pos+bytes-1)
    end
    rows[y]=table.concat(cells)
  end
  self.image.rawdata=table.concat(rows) self.image.extended=true
end
function document:clear(color)
  local cells=self.width*self.height//2
  if self.image.mask then
    local rest=cells%4
    self.image.mask=string.rep("\255",cells//4)..(rest>0 and string.char((1 << (rest*2))-1) or "")
  else
    local cell=self.image.depth==4 and string.char(color*17) or string.char(color,color)
    self.image.rawdata=((self.image.extended and string.char(3) or "")..cell):rep(cells)
  end
end
function document:clearBackground()
  local white=self.image.depth==4 and tmg.rgbTo4bit(0xFFFFFF) or tmg.rgbToIndex(0xFFFFFF)
  local rows={}
  for y=1,self.height do
    local row={}
    for x=1,self.width do
      local color=self:get(x,y)
      row[x]=color==-1 and "\2" or color==white and "\1" or "\0"
    end
    rows[y]=table.concat(row)
  end
  local pending={}
  local function matches(x,y)
    local value=rows[y]:byte(x)
    return value==1 or value==2
  end
  local function seed(x,y)
    if matches(x,y) then pending[#pending+1]=(y-1)*self.width+x end
  end
  for x=1,self.width do seed(x,1) seed(x,self.height) end
  for y=2,self.height-1 do seed(1,y) seed(self.width,y) end
  local removed=0
  while #pending>0 do
    local point=table.remove(pending)
    local y=(point-1)//self.width+1
    local x=(point-1)%self.width+1
    if matches(x,y) then
      local left,right=x,x
      while left>1 and matches(left-1,y) do left=left-1 end
      while right<self.width and matches(right+1,y) do right=right+1 end
      for px=left,right do if rows[y]:byte(px)==1 then removed=removed+1 end end
      rows[y]=rows[y]:sub(1,left-1)..string.rep("\3",right-left+1)..rows[y]:sub(right+1)
      for ny=y-1,y+1,2 do
        if ny>=1 and ny<=self.height then
          local inside=false
          for nx=left,right do
            local same=matches(nx,ny)
            if same and not inside then seed(nx,ny) end
            inside=same
          end
        end
      end
    end
  end
  if removed==0 then return 0 end
  local mask={}
  local packed,count=0,0
  for y=1,self.height,2 do
    for x=1,self.width do
      local flags=self.image:getMask(x,(y+1)//2)
      if rows[y]:byte(x)==3 then flags=flags | 1 end
      if rows[y+1]:byte(x)==3 then flags=flags | 2 end
      packed=packed | (flags << (count*2)) count=count+1
      if count==4 then mask[#mask+1]=string.char(packed) packed,count=0,0 end
    end
  end
  if count>0 then mask[#mask+1]=string.char(packed) end
  self.image.mask=table.concat(mask)
  return removed
end
function document:get(x,y,ignoreMask)
  if not ignoreMask and self.image.mask then
    local flags=self.image:getMask(x,(y+1)//2)
    if flags & (y%2==1 and 1 or 2)~=0 then return -1 end
  end
  local cell=(math.floor((y-1)/2)*self.width+x-1)
  local extra=self.image.extended and 1 or 0
  if self.image.depth==4 then
    local byte=self.image.rawdata:byte(cell*(1+extra)+extra+1)
    return y%2==1 and byte//16 or byte%16
  end
  return self.image.rawdata:byte(cell*(2+extra)+extra+(y%2==1 and 1 or 2))
end
function document:set(x,y,color)
  if x<1 or x>self.width or y<1 or y>self.height then return end
  if self.image.mask or color==-1 then
    local flags=self.image:getMask(x,(y+1)//2)
    local bit=y%2==1 and 1 or 2
    local nextFlags=color==-1 and (flags | bit) or (flags & (3 ~ bit))
    if nextFlags~=flags then self.image:setMask(x,(y+1)//2,nextFlags) end
    if color==-1 then return end
  end
  local cell=math.floor((y-1)/2)*self.width+x-1
  local extra=self.image.extended and 1 or 0
  local pos,value
  if self.image.depth==4 then
    pos=cell*(1+extra)+extra+1
    local byte=self.image.rawdata:byte(pos)
    value=y%2==1 and color*16+byte%16 or (byte//16)*16+color
  else pos=cell*(2+extra)+extra+(y%2==1 and 1 or 2) value=color end
  local raw=self.image.rawdata
  if raw:byte(pos)==value then return end
  self.image.rawdata=raw:sub(1,pos-1)..string.char(value)..raw:sub(pos+1)
end
function document:line(x1,y1,x2,y2,color)
  local dx,dy=math.abs(x2-x1),-math.abs(y2-y1)
  local sx,sy=x1<x2 and 1 or -1,y1<y2 and 1 or -1
  local err=dx+dy
  while true do
    self:set(x1,y1,color)
    if x1==x2 and y1==y2 then break end
    local twice=err*2
    if twice>=dy then err=err+dy x1=x1+sx end
    if twice<=dx then err=err+dx y1=y1+sy end
  end
end
function document:rectangle(x1,y1,x2,y2,color)
  self:line(x1,y1,x2,y1,color) self:line(x2,y1,x2,y2,color)
  self:line(x2,y2,x1,y2,color) self:line(x1,y2,x1,y1,color)
end
function document:circle(x1,y1,x2,y2,color)
  if x1==x2 or y1==y2 then self:line(x1,y1,x2,y2,color) return end
  local left,right=math.min(x1,x2),math.max(x1,x2)
  local top,bottom=math.min(y1,y2),math.max(y1,y2)
  local cx,cy=(left+right)/2,(top+bottom)/2
  local rx,ry=(right-left)/2,(bottom-top)/2
  local function round(n) return math.floor(n+.5) end
  for x=left,right do
    local dy=ry*math.sqrt(math.max(0,1-((x-cx)/rx)^2))
    self:set(x,round(cy-dy),color) self:set(x,round(cy+dy),color)
  end
  for y=top,bottom do
    local dx=rx*math.sqrt(math.max(0,1-((y-cy)/ry)^2))
    self:set(round(cx-dx),y,color) self:set(round(cx+dx),y,color)
  end
end
function document:fill(x,y,color)
  local target=self:get(x,y)
  if target==color then return end
  -- Keep rows as byte strings and process horizontal spans, avoiding a table per pixel.
  local rows,clear={},self.image.mask and {} or nil
  for py=1,self.height do
    local row,alpha={},{}
    for px=1,self.width do
      row[px]=string.char(self:get(px,py,true))
      if clear then alpha[px]=self:get(px,py)==-1 and "\1" or "\0" end
    end
    rows[py]=table.concat(row)
    if clear then clear[py]=table.concat(alpha) end
  end
  local function matches(px,py)
    if clear and clear[py]:byte(px)==1 then return target==-1 end
    return target~=-1 and rows[py]:byte(px)==target
  end
  local pending={(y-1)*self.width+x}
  while #pending>0 do
    local seed=table.remove(pending)
    local py=(seed-1)//self.width+1
    local px=(seed-1)%self.width+1
    if matches(px,py) then
      local left,right=px,px
      while left>1 and matches(left-1,py) do left=left-1 end
      while right<self.width and matches(right+1,py) do right=right+1 end
      rows[py]=rows[py]:sub(1,left-1)..string.char(color):rep(right-left+1)..rows[py]:sub(right+1)
      if clear then clear[py]=clear[py]:sub(1,left-1)..string.rep("\0",right-left+1)..clear[py]:sub(right+1) end
      for ny=py-1,py+1,2 do
        if ny>=1 and ny<=self.height then
          local inside=false
          for nx=left,right do
            local same=matches(nx,ny)
            if same and not inside then pending[#pending+1]=(ny-1)*self.width+nx end
            inside=same
          end
        end
      end
    end
  end
  local raw,mask={},{}
  local packed,count=0,0
  for py=1,self.height,2 do
    local row={}
    for px=1,self.width do
      local upper,lower=rows[py]:byte(px),rows[py+1]:byte(px)
      row[px]=(self.image.extended and string.char(3) or "")..
        (self.image.depth==4 and string.char(upper*16+lower) or string.char(upper,lower))
      if clear then
        local flags=clear[py]:byte(px) | (clear[py+1]:byte(px) << 1)
        packed=packed | (flags << (count*2)) count=count+1
        if count==4 then mask[#mask+1]=string.char(packed) packed,count=0,0 end
      end
    end
    raw[#raw+1]=table.concat(row)
  end
  self.image.rawdata=table.concat(raw)
  if clear then
    if count>0 then mask[#mask+1]=string.char(packed) end
    self.image.mask=table.concat(mask)
  end
end
return document
end
