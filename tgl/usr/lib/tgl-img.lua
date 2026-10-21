---@diagnostic disable: cast-local-type
---@diagnostic disable: return-type-mismatch
local bit32=require("bit32")
local tgl=require("tgl")
local tmg={}
tmg.ver="1.7"
tmg.enableCompressing=true --Enable compressing when saving?
tmg.autoPreload=true --Automatically preload
tmg.cache={} --TODO: add cache for frequent colors

--UTILS
tmg.char="▀"
tmg.chars={}
tmg.chars[0]=""
tmg.chars[3]=tmg.char
tmg.chars[128]="█"
tmg.chars[129]="▓"
tmg.chars[130]="▒"
tmg.chars[131]="▄"
tmg.chars[132]="▖"
tmg.chars[133]="▗"
tmg.chars[134]="▘"
tmg.chars[135]="▝"

---Gets char in extended mode
---@param char string
---@return string
function tmg.getExtendedChar(char)
  local byte=0
  if string.len(char)<2 then
    byte=string.byte(char)
  else
    return char
  end
  if byte<128 and byte>=32 then return char
  else
    if tmg.chars[byte] then return tmg.chars[byte]
    else return "" end
  end
end

---Collect flags to byte
---@param depth integer
---@param compRLE boolean
---@param compDiff boolean
---@param extended boolean
---@param transparency? boolean
---@return string
function tmg.collectFlags(depth,compRLE,compDiff,extended,transparency)
  if depth==4 then depth=0 else depth=1 end
  if compRLE==true then compRLE=1 else compRLE=0 end
  if compDiff==true then compDiff=1 else compDiff=0 end
  if extended==true then extended=1 else extended=0 end
  return string.char((transparency and 16 or 0)+depth*8+compRLE*4+compDiff*2+extended)
end
---Gets flags from string byte
---@param f string
---@return integer
---@return boolean
---@return boolean
---@return boolean
---@return boolean
function tmg.getFlags(f)
  f=string.byte(f)
  return f%16//8*4+4,f%8//4==1,f%4//2==1,f%2==1,f&16~=0
end
--compression
---Run-Length Encoding
---@param data string
function tmg.compressRLE(data)
  if #data==0 then return data,0 end
  local result={}
  local count=1
  local current=data:byte(1)
  local original_size=#data
  
  for i=2,#data do
    local byte=data:byte(i)
    if byte==current and count<255 then
      count=count+1
    else
      table.insert(result,string.char(count))
      table.insert(result,string.char(current))
      current=byte
      count=1
    end
  end
  table.insert(result,string.char(count))
  table.insert(result,string.char(current))
  
  local compressed=table.concat(result)
  return compressed,original_size
end
---@param data string
---@return string
function tmg.decompressRLE(data)
  local result={}
  for i=1,#data,2 do
    local count=data:byte(i)
    local byte=data:byte(i+1)
    table.insert(result,string.char(byte):rep(count))
  end
  return table.concat(result)
end
---Difference encoding
---@param data string
function tmg.compressDiff(data)
  if #data==0 then return data,0 end
  local result={string.char(data:byte(1))}
  local last=data:byte(1)
  local original_size=#data
  
  for i=2,#data do
    local byte=data:byte(i)
    local diff=(byte-last+256)%256
    table.insert(result, string.char(diff))
    last=byte
  end
  
  local compressed=table.concat(result)
  return compressed, original_size
end
---@param data string
---@return string
function tmg.decompressDiff(data)
  local result={string.char(data:byte(1))}
  local last=data:byte(1)
  for i=2,#data do
    local diff=data:byte(i)
    last=(last+diff)%256
    table.insert(result, string.char(last))
  end
  return table.concat(result)
end

---@param data string
function tmg.compressRLEDiff(data)
  local diff_data,_=tmg.compressDiff(data)
  local rle_data,original_size=tmg.compressRLE(diff_data)
  return rle_data,original_size
end
---@param data string
---@return string
function tmg.decompressRLEDiff(data)
  local rle_decompressed=tmg.decompressRLE(data)
  local diff_decompressed=tmg.decompressDiff(rle_decompressed)
  return diff_decompressed
end

---Main compression decision function
---@param data string
---@return string
---@return boolean
---@return boolean
---@return integer
function tmg.autoCompress(data)
  if #data < 100 then  -- Too small to benefit
    return data,false,false,#data
  end
  
  -- Try different methods
  local rle_data, orig_size_rle = tmg.compressRLE(data)
  local diff_data, orig_size_diff = tmg.compressDiff(data)
  local rlediff_data, orig_size_rlediff = tmg.compressRLEDiff(data)
  
  -- Find best compression
  local options = {
    {compRLE = false, compDIFF = false, data = data, size = #data},
    {compRLE = true, compDIFF = false, data = rle_data, size = #rle_data},
    {compRLE = false, compDIFF = true, data = diff_data, size = #diff_data},
    {compRLE = true, compDIFF = true, data = rlediff_data, size = #rlediff_data}
  }
  table.sort(options, function(a, b) return a.size < b.size end)

  local best = options[1]
  if best.size<#data*0.9 then --at least 10% savings
    return best.data,best.compRLE,best.compDIFF,#data
  else
    return data,false,false,#data
  end
end

---Main decompression function
---@param data string
---@param compRLE boolean
---@param compDIFF boolean
---@return string
function tmg.decompress(data, compRLE, compDIFF)
  if not compRLE and not compDIFF then return data
  elseif compRLE and not compDIFF then return tmg.decompressRLE(data)
  elseif not compRLE and compDIFF then return tmg.decompressDiff(data)
  elseif compRLE and compDIFF then return tmg.decompressRLEDiff(data) end
  return ""
end

---Analyze data for best method
function tmg.analyzeCompression(data)
  local analysis={
    original_size=#data,
    methods={
      none=#data,
      rle=#tmg.compressRLE(data),
      diff=#tmg.compressDiff(data),
      rle_diff=#tmg.compressRLEDiff(data)
    }
  }
  return analysis
end

--8bit color

tmg.reds = {0x00,0x33,0x66,0x99,0xCC,0xFF}
tmg.greens = {0x00,0x24,0x49,0x6D,0x92,0xB6,0xDB,0xFF}
tmg.blues = {0x00,0x40,0x80,0xBF,0xFF}
tmg.greys = {0x0F,0x1E,0x2D,0x3C,0x4B,0x5A,0x69,0x78,
0x87,0x96,0xA5,0xB4,0xC3,0xD2,0xE1,0xF0}

---Get nearest value from color list
---@param value integer
---@param list table
---@return integer
function tmg.nearest(value, list)
  local best_i,best_d = 1, math.huge
  for i=1,#list do
    local d=math.abs(value-list[i])
    if d<best_d then
      best_d=d
      best_i=i
    end
  end
  return best_i-1  -- return 0-based index
end

---RGB color to 8bit index 0-255
---@param color integer
---@return integer
function tmg.rgbToIndex(color)
  local r=bit32.rshift(color, 16)
  local g=bit32.band(bit32.rshift(color, 8), 0xFF)
  local b=bit32.band(color, 0xFF)

  -- find nearest palette component
  local ri = tmg.nearest(r, tmg.reds)
  local gi = tmg.nearest(g, tmg.greens)
  local bi = tmg.nearest(b, tmg.blues)

  -- If color is greyscale, place in greys.
  if r==g and g==b then
    if r==0 then return 0 end
    if r==255 then return 239 end
    -- find nearest grey
    local giGrey = tmg.nearest(r, tmg.greys)
    return 240+giGrey
  end
  -- return the 6×8×5 index (0–239)
  return ri*40 + gi*5 + bi
end
---8bit index to rgb color integer
---@param idx integer
---@return integer
function tmg.indexToRgb(idx)
  if idx<240 then
    local ri = math.floor(idx/40)
    local gi = math.floor((idx%40)/5)
    local bi = idx%5

    local r = tmg.reds[ri+1]
    local g = tmg.greens[gi+1]
    local b = tmg.blues[bi+1]

    return (r<<16) | (g<<8) | b
  end
  local gi = idx-240+1
  local gray = tmg.greys[gi]
  return (gray<<16) | (gray<<8) | gray
end

---Color2 to 2 string bytes
---@param col2 tgl.Color2
---@return string
function tmg.col2ToChars(col2)
  return string.char(tmg.rgbToIndex(col2[1]))..string.char(tmg.rgbToIndex(col2[2]))
end
---bytes to Color2
---@param b1 integer
---@param b2 integer
---@return tgl.Color2
function tmg.bytesToCol2(b1,b2)
  return tgl.Color2:new(tmg.indexToRgb(b1),tmg.indexToRgb(b2))
end

--4bit color
tmg.palette4bit = {}
local colorNames = {
    "black", "red", "darkgreen", "brown",
    "darkblue", "purple", "cyan", "darkgray",
    "lightgray", "pink", "lime", "yellow", 
    "lightblue", "magenta", "gold", "white"
}
for i, colorName in ipairs(colorNames) do
  tmg.palette4bit[i - 1] = tgl.defaults.colors16[colorName]
end

---RGB integer to 4bit index
---@param col integer
---@return integer
function tmg.rgbTo4bit(col)
  for i = 0, 15 do
    if tmg.palette4bit[i]==col then return i end
  end
  return 0
end
---4bit palette index to RGB integer
---@param index integer
---@return integer
function tmg.palette4bitToColor(index)
  if index==nil or index<0 or index>15 then
    return tmg.palette4bit[0]
  end
  return tmg.palette4bit[index]
end
---Color2 to string byte
---@param col2 tgl.Color2
---@return string
function tmg.col2toChar4bit(col2)
  return string.char(16*tmg.rgbTo4bit(col2[1])+tmg.rgbTo4bit(col2[2]))
end
---Byte to color2
---@param b integer
---@return tgl.Color2
function tmg.byteToCol2(b)
  return tgl.Color2:new(tmg.palette4bitToColor(b//16),tmg.palette4bitToColor(b%16))
end

---Convert Screen pixels to rawdata
---@param size2 tgl.Size2
---@param depth integer
---@param extended boolean default: true
---@return string
function tmg.dumpScreenToRaw(size2,depth,extended)
  if not size2 or not depth then return "" end
  if not extended then extended=true end
  local res=""
  local r=tgl.sys.renderer
  for y=size2.y1,size2.y2 do
    for x=size2.x1,size2.x2 do
      local char,col2=r:getPoint(x,y)
      if extended then res=res..char end
      if depth==4 then res=res..tmg.col2toChar4bit(col2)
      else res=res..tmg.col2ToChars(col2) end
    end
  end
  return res
end

---Image object
---@class tmg.Image:tgl.BoxObject
---@field depth integer Bit depth of color, 4 or 8
---@field extended boolean If chars are encoded too
---@field pixelsize integer Number of pixels in image
---@field name string Image name
---@field rawdata string Image rawdata bytes in string form
---@field mask string|nil Packed two-bit transparency mask, four cells per byte
---@field autoPreload boolean|nil Set false to disable automatic preloading for this image
---@field preloaded boolean If image was preloaded into buffer
---@field preload_buf integer
---@field data tgl.Text[] Array of text objects
tmg.Image=setmetatable({},{__index=tgl.BoxObject})
tmg.Image.__index=tmg.Image
---@param size2 tgl.Size2
---@param depth integer
---@param name? string
---@return tmg.Image
function tmg.Image:new(size2,depth,name)
  local obj=setmetatable({},self)
  obj.type="Image"
  obj.z_index=0
  obj.size2=size2 or tgl.Size2:new(1,1,16,16)
  obj.depth=depth or 8
  obj.extended=false
  obj.pixelsize=obj.size2.sizeX*obj.size2.sizeY*2
  obj.rawdata=""
  obj.mask=nil
  obj.name=tostring(name) or "untitled"
  obj.preloaded=false
  obj.data={}
  return obj
end

local function maskAt(img,x,y)
  if not img.mask then return 0 end
  local i=(y-1)*img.size2.sizeX+x-1
  return (img.mask:byte(i//4+1) >> ((i%4)*2)) & 3
end

local function maskPosition(img,x,y)
  return type(x)=="number" and type(y)=="number" and x==math.floor(x) and y==math.floor(y)
    and x>=1 and x<=img.size2.sizeX and y>=1 and y<=img.size2.sizeY
end

---Get cell transparency: 0 opaque, 1 upper clear, 2 lower clear, 3 both clear.
function tmg.Image:getMask(x,y)
  if not maskPosition(self,x,y) then return nil,"Invalid mask position." end
  return maskAt(self,x,y)
end

---Set cell transparency, creating an opaque mask on the first transparent cell.
function tmg.Image:setMask(x,y,value)
  if not maskPosition(self,x,y) or type(value)~="number" or value~=math.floor(value)
  or value<0 or value>3 then return false,"Invalid mask position or value." end
  if not self.mask and value==0 then return true end
  local count=self.size2.sizeX*self.size2.sizeY
  local mask=self.mask or string.rep("\0",(count+3)//4)
  local i=(y-1)*self.size2.sizeX+x-1
  local pos,shift=i//4+1,(i%4)*2
  local byte=(mask:byte(pos) & (255 ~ (3 << shift))) | (value << shift)
  if self.preloaded then self:unload() end
  self.mask=mask:sub(1,pos-1)..string.char(byte)..mask:sub(pos+1)
  return true
end

local function halfColors(char,col)
  if char=="▀" then return col[1],col[2]
  elseif char=="▄" then return col[2],col[1]
  elseif char=="█" then return col[1],col[1]
  elseif char==" " then return col[2],col[2] end
end

-- Extended images mix a character with binary color bytes in each cell.
-- Decode characters by byte offset; Unicode indexing cannot skip color bytes.
local function readCell(img,pos)
  local raw=img.rawdata
  local char=tmg.char
  if img.extended then
    local first=raw:byte(pos)
    if not first then return nil,"Incomplete image data." end
    local len=1
    if first>=0xC2 and first<=0xDF then len=2
    elseif first>=0xE0 and first<=0xEF then len=3
    elseif first>=0xF0 and first<=0xF4 then len=4 end
    for i=1,len-1 do
      local byte=raw:byte(pos+i)
      if not byte or byte<0x80 or byte>0xBF then return nil,"Invalid image character." end
    end
    char=tmg.getExtendedChar(raw:sub(pos,pos+len-1))
    if char=="" then char=" " end
    pos=pos+len
  end
  local bytes=img.depth==4 and 1 or 2
  if pos+bytes-1>#raw then return nil,"Incomplete image data." end
  local col=img.depth==4 and tmg.byteToCol2(raw:byte(pos))
    or tmg.bytesToCol2(raw:byte(pos),raw:byte(pos+1))
  return char,col,pos+bytes
end

local function imageRows(img)
  local w,h=img.size2.sizeX,img.size2.sizeY
  if (img.depth~=4 and img.depth~=8) or type(img.rawdata)~="string"
  or w<1 or h<1 or w~=math.floor(w) or h~=math.floor(h) then return nil,"Invalid image dimensions or depth." end
  if img.mask~=nil then
    if type(img.mask)~="string" or #img.mask~=(w*h+3)//4 then return nil,"Invalid transparency mask length." end
    local used=w*h%4
    if used~=0 and img.mask:byte(-1) >> (used*2)~=0 then return nil,"Invalid transparency mask padding." end
  end
  local bytes=img.depth==4 and 1 or 2
  if #img.rawdata<w*h*(bytes+(img.extended and 1 or 0)) then return nil,"Incomplete image data." end
  if not img.extended then return true end
  local cached=img._rows
  if cached and cached.raw==img.rawdata and cached.mask==img.mask and cached.width==w and cached.height==h and cached.depth==img.depth then
    return cached
  end
  local rows={raw=img.rawdata,mask=img.mask,width=w,height=h,depth=img.depth}
  local pos=1
  for y=1,h do
    rows[y]=pos
    for x=1,w do
      local char,col,nextPos=readCell(img,pos)
      if not char then return nil,col end
      local mask=maskAt(img,x,y)
      if (mask==1 or mask==2) and not halfColors(char,col) then
        return nil,"Half-cell transparency requires block or space characters."
      end
      pos=nextPos
    end
    if y%20==0 then os.sleep(0) end
  end
  img._rows=rows
  return rows
end

local function rowStart(img,rows,y)
  if img.extended then return rows[y] end
  return ((y-1)*img.size2.sizeX)*(img.depth==4 and 1 or 2)+1
end

-- Keep image pixels out of the command queue. Decode them only while the
-- renderer executes this one command, reusing its position/command tables.
local function drawImage(r,cmd)
  local img=cmd.image
  local point={x=0,y=0}
  local cell={cmd="set",pos2=point,buffer=cmd.buffer,z_index=cmd.z_index,clipRegion=cmd.clipRegion}
  for y=cmd.source.y1,cmd.source.y2 do
    local pos=rowStart(img,cmd.rows,y)
    if not img.extended then pos=pos+(cmd.source.x1-1)*(img.depth==4 and 1 or 2) end
    local first=img.extended and 1 or cmd.source.x1
    for x=first,cmd.source.x2 do
      local char,col,nextPos=readCell(img,pos)
      if not char then error(col,0) end
      pos=nextPos
      if x>=cmd.source.x1 then
        point.x=cmd.destination.x+x-cmd.source.x1
        point.y=cmd.destination.y+y-cmd.source.y1
        local mask=maskAt(img,x,y)
        if mask~=3 then
          if mask~=0 then
            local upper,lower=halfColors(char,col)
            local oldChar,fg,bg=r.gpu.get(point.x,point.y)
            local oldUpper,oldLower=halfColors(oldChar,{fg,bg})
            if mask==1 then upper=oldUpper or bg else lower=oldLower or bg end
            char,col=tmg.char,tgl.Color2:new(upper,lower)
          end
          cell.value,cell.col2=char,col
          if not r:execCmd(cell) then return false end
        end
      end
    end
  end
  return true
end

tgl.Renderer.cmd.tmg=drawImage

local function queueImage(img,rows,source,destination,buffer)
  local r=tgl.sys.renderer
  local snapshot={rawdata=img.rawdata,mask=img.mask,depth=img.depth,extended=img.extended,
    size2={sizeX=img.size2.sizeX,sizeY=img.size2.sizeY}}
  local cmd={cmd="tmg",image=snapshot,rows=rows,source=source,destination=destination,
    buffer=buffer or 0,z_index=img.z_index}
  if r.customCommands then return r:addCmd(cmd) end
  if img.mask then return false,"Transparency requires a renderer with custom command support." end
  -- Compatibility with earlier v9 renderers; use the original queued path.
  for y=source.y1,source.y2 do
    local pos=rowStart(snapshot,rows,y)
    if not snapshot.extended then pos=pos+(source.x1-1)*(snapshot.depth==4 and 1 or 2) end
    for x=snapshot.extended and 1 or source.x1,source.x2 do
      local char,col,nextPos=readCell(snapshot,pos)
      if not char then return false,col end
      pos=nextPos
      if x>=source.x1 then
        r:setPoint(destination.x+x-source.x1,destination.y+y-source.y1,char,col,img.z_index,false,buffer)
      end
    end
  end
  return true
end

---Decode the image into a reusable GPU buffer.
---@return boolean, string|nil
function tmg.Image:preload()
  if self.mask then return false,"Transparent images must be drawn over their destination." end
  local r=tgl.sys.renderer
  if self.preloaded and r:hasBuffer(self.preload_buf) then return true end
  local rows,err=imageRows(self)
  if not rows then return false,err end
  -- TGL positions are screen-width bounded; wider images use regional drawing.
  if self.size2.sizeX>tgl.defaults.screenSizeX then return false,"Image is wider than the buffer drawing limit." end
  local ok,success,buf=pcall(r.allocateBuffer,r,self.size2.sizeX,self.size2.sizeY)
  if not ok or not success then return false,"Not enough GPU memory to preload image." end
  local clip=r:getClipRegion()
  r:setClipRegion(tgl.Size2:new(1,1,self.size2.sizeX,self.size2.sizeY))
  local drawn,result,why=pcall(queueImage,self,rows,
    {x1=1,y1=1,x2=self.size2.sizeX,y2=self.size2.sizeY},tgl.Pos2:new(1,1),buf)
  r:setClipRegion(clip)
  r:addCmd({cmd="reset",col2=tgl.defaults.colors2.black,z_index=self.z_index})
  if not drawn or not result then
    r:addCmd({cmd="freebuffer",id=buf,z_index=self.z_index})
    return false,tostring(drawn and why or result)
  end
  self.preloaded=true
  self.preload_buf=buf
  return true
end

function tmg.Image:unload()
  self.preloaded=false
  if type(self.preload_buf)=="number" and self.preload_buf>0 then
    local r=tgl.sys.renderer
    if r:hasBuffer(self.preload_buf) then
      r:addCmd({cmd="freebuffer",id=self.preload_buf,z_index=self.z_index})
    end
  end
  self.preload_buf=0
  return true
end
---Tries to generate rawdata string bytes from data table
---@return boolean
function tmg.Image:convert()
  --Generates self.rawdata string from self.data array
  if type(self.data)~="table" then return false end
  table.sort(self.data,function(a,b)
    if a.pos2.y<b.pos2.y then return true
    elseif a.pos2.y<b.pos2.y then return false
    else
      if a.pos2.x<b.pos2.x then return true
      else return false end
    end
  end)
  local res=""
  for i,p in pairs(self.data) do
    if self.extended then
      res=res..p.text
    end
    if self.depth==4 then
      res=res..tmg.col2toChar4bit(p.col2)
    else
      res=res..tmg.col2ToChars(p.col2)
    end
  end
  self.rawdata=res
  return true
end
-- Close handles on success, parse errors and failed writes. OpenOS close may
-- return nil without an error on success.
local function withFile(filename,mode,callback)
  local file,err=io.open(filename,mode)
  if not file then return false,err end
  local ok,result,reason=pcall(callback,file)
  local closed,value,closeErr=pcall(function() return file:close() end)
  if not ok then return false,tostring(result) end
  if not closed or value==false or closeErr then return false,tostring(closeErr or value or "Close failed.") end
  return result,reason
end

---Save a .tmg file. Returns false,error on failure.
function tmg.Image:save(filename)
  local rows,err=imageRows(self)
  if not rows then return false,err end
  if self.name:find("[\r\n]") then return false,"Image name must fit on one line." end
  filename=filename or self.name..".tmg"
  return withFile(filename,"wb",function(file)
    local raw,compRLE,compDiff=self.rawdata,false,false
    if tmg.enableCompressing then raw,compRLE,compDiff=tmg.autoCompress(raw) end
    local data="tmg\n"..tmg.collectFlags(self.depth,compRLE,compDiff,self.extended,self.mask~=nil).."\n"..
      self.name.."\n"..self.size2.sizeX.."\n"..self.size2.sizeY.."\n"..(self.mask or "")..raw
    local written,why=file:write(data)
    if not written then return false,why or "Write failed." end
    if file.flush then
      local flushed,flushErr=file:flush()
      if flushed==false or flushErr then return false,flushErr or "Flush failed." end
    end
    return true
  end)
end

---Load a new Image; returns false,error on failure.
function tmg.Image:load(filename,pos2)
  return withFile(filename,"rb",function(file)
    if file:read("l")~="tmg" then return false,"Not a TMG image." end
    -- Flags are a raw byte, which can itself be a newline.
    local flags=file:read(1)
    if not flags or flags:byte()>31 or file:read(1)~="\n" then return false,"Invalid TMG flags." end
    local depth,compRLE,compDiff,extended,transparency=tmg.getFlags(flags)
    local name=file:read("l")
    local w,h=tonumber(file:read("l")),tonumber(file:read("l"))
    if not name or not w or not h or w<1 or h<1 or w~=math.floor(w) or h~=math.floor(h)
    or w==math.huge or h==math.huge then return false,"Invalid image dimensions." end
    pos2=pos2 or tgl.Pos2:new(1,1)
    local img=tmg.Image:new(tgl.Size2:new(pos2.x,pos2.y,w,h),depth,name)
    img.extended=extended
    if transparency then
      local count=(w*h+3)//4
      img.mask=file:read(count)
      if not img.mask or #img.mask~=count then return false,"Incomplete transparency mask." end
    end
    img.rawdata=tmg.decompress(file:read("*a"),compRLE,compDiff)
    local rows,why=imageRows(img)
    if not rows then return false,why end
    return img
  end)
end

---Draw an image-cell source rectangle at a screen position, without resizing.
---Source bounds are 1-based. The destination defaults to the image's position.
---@param source tgl.Size2|nil nil means the full image
---@param pos2 tgl.Pos2|nil destination of the requested source's top-left
---@return boolean, string|nil
function tmg.Image:renderRegion(source,pos2)
  if self.hidden then return true end
  local r=tgl.sys.renderer
  source=source or {x1=1,y1=1,x2=self.size2.sizeX,y2=self.size2.sizeY}
  pos2=pos2 or self.size2.pos1
  local function coordinate(value)
    return type(value)=="number" and value==math.floor(value) and math.abs(value)~=math.huge
  end
  if type(source)~="table" or type(pos2)~="table"
  or not coordinate(source.x1) or not coordinate(source.y1) or not coordinate(source.x2)
  or not coordinate(source.y2) or not coordinate(pos2.x) or not coordinate(pos2.y) then
    return false,"Region coordinates must be finite integers."
  end
  if source.x2<source.x1 or source.y2<source.y1 then return false,"Invalid image region." end
  local sx,sy=math.max(1,source.x1),math.max(1,source.y1)
  local ex,ey=math.min(self.size2.sizeX,source.x2),math.min(self.size2.sizeY,source.y2)
  local dx,dy=pos2.x+sx-source.x1,pos2.y+sy-source.y1
  local clip=r:getClipRegion()
  local left,top=math.max(1,dx),math.max(1,dy)
  local right,bottom=math.min(tgl.defaults.screenSizeX,dx+ex-sx),math.min(tgl.defaults.screenSizeY,dy+ey-sy)
  if clip then
    left,top=math.max(left,clip.x1),math.max(top,clip.y1)
    right,bottom=math.min(right,clip.x2),math.min(bottom,clip.y2)
  end
  if left>right or top>bottom or sx>ex or sy>ey then return true end
  sx,sy=sx+left-dx,sy+top-dy
  ex,ey=sx+right-left,sy+bottom-top
  local destination=tgl.Size2:newFromPoint(left,top,right,bottom)
  local rows,err=imageRows(self)
  if not rows then return false,err end
  if self.mask and self.preloaded then self:unload() end
  if self.preloaded and not r:hasBuffer(self.preload_buf) then self.preloaded=false self.preload_buf=0 end
  local temporary=false
  if not self.mask and not self.preloaded and self.autoPreload~=false and tmg.autoPreload then temporary=self:preload() end
  if self.preloaded then
    local copied=r:bufcopy(self.preload_buf,0,destination,self.z_index,tgl.Pos2:new(sx,sy))
    if temporary then self:unload() end
    return copied
  end
  r:setClipRegion(destination)
  local ok,result,why=pcall(queueImage,self,rows,{x1=sx,y1=sy,x2=ex,y2=ey},tgl.Pos2:new(left,top))
  r:setClipRegion(clip)
  if not ok then return false,tostring(result) end
  return result,why
end

---Draw the complete image at its stored position, respecting the renderer clip.
function tmg.Image:render()
  return self:renderRegion()
end

---Saves screen area to .tmg Image
---@param size2 tgl.Size2
---@param depth? integer default: 8bit
---@param name? string defaults: Untitled
---@param extended? boolean defaults: true
---@return tmg.Image
function tmg.saveScreenToTmg(size2,name,depth,extended)
  if not size2 then return nil end
  if not depth then depth=8 end
  if not extended then extended=true end
  local img=tmg.Image:new(size2,depth,name)
  img.extended=extended
  img.rawdata=tmg.dumpScreenToRaw(size2,depth,extended)
  return img
end
return tmg
--[[
Image
sizeX*sizeY chars
each char is 2 pixels
rawdata={chars}
rawdata len:
4bit: sizeX*sizeY
8bit: sizeX*sizeY
8bit char is stored in chunk of two bytes

.tmg file format
tmg --file format
1010 --flags
<str> --name
16 --sizeX(in chars)
16 --sizeY(in chars)
<bin> --optional uncompressed mask, ceil(sizeX*sizeY/4) bytes, no separator
<bin> --rawdata
upper=foreground
lower=background

tmg flags
10000 transparency mask present
1000 color depth (0=4bit 1=8bit)
0100 compression (RLE)
0010 compression (diff)
0001 extended mode(1byte for char)
]]
