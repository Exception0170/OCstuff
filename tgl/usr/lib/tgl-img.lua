---@diagnostic disable: cast-local-type
---@diagnostic disable: return-type-mismatch
local bit32=require("bit32")
local term=require("term")
local tgl=require("tgl")
local tmg={}
tmg.ver="1.3"
tmg.enableCompressing=true --Enable compressing when saving?
tmg.cache={} --TODO: add cache for frequent colors

--UTILS
tmg.char="▀"
tmg.chars={}
tmg.chars[0]=""
tmg.chars[1]=tmg.char
tmg.chars[128]="█"
tmg.chars[129]="▓"
tmg.chars[130]="▒"
tmg.chars[131]="▄"
tmg.chars[132]="▖"
tmg.chars[132]="▗"
tmg.chars[132]="▘"
tmg.chars[132]="▝"

---Gets char in extended mode
---@param byte integer
---@return string
function tmg.getExtendedChar(byte)
  if byte<128 and byte>=32 then return string.char(byte)
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
---@return string
function tmg.collectFlags(depth,compRLE,compDiff,extended)
  if depth==4 then depth=0 else depth=1 end
  if compRLE==true then compRLE=1 else compRLE=0 end
  if compDiff==true then compDiff=1 else compDiff=0 end
  if extended==true then extended=1 else extended=0 end
  return string.char(depth*8+compRLE*4+compDiff*2+extended)
end
---Gets flags from string byte
---@param f string
---@return integer
---@return boolean
---@return boolean
---@return boolean
function tmg.getFlags(f)
  f=string.byte(f)
  return f//8*4+4,f%8//4==1,f%4//2==1,f%2==1
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
tmg.blues = {0x00,0x40,0x80,0xC0,0xFF}
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
---@param col2 Color2
---@return string
function tmg.col2ToChars(col2)
  return string.char(tmg.rgbToIndex(col2[1]))..string.char(tmg.rgbToIndex(col2[2]))
end
---bytes to Color2
---@param b1 integer
---@param b2 integer
---@return Color2
function tmg.bytesToCol2(b1,b2)
  return Color2:new(tmg.indexToRgb(b1),tmg.indexToRgb(b2))
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
---@param col2 Color2
---@return string
function tmg.col2toChar4bit(col2)
  return string.char(16*tmg.rgbTo4bit(col2[1])+tmg.rgbTo4bit(col2[2]))
end
---Byte to color2
---@param b integer
---@return Color2
function tmg.byteToCol2(b)
  return Color2:new(tmg.palette4bitToColor(b//16),tmg.palette4bitToColor(b%16))
end

---Image object
---@class Image:BoxObject
---@field depth integer Bit depth of color, 4 or 8
---@field extended boolean If chars are encoded too
---@field pixelsize integer Number of pixels in image
---@field name string Image name
---@field rawdata string Image rawdata bytes in string form
---@field preloaded boolean If image was parsed into Text objects
---@field data Text[] preloaded image
Image=setmetatable({},{__index=BoxObject})
Image.__index=Image
---@param size2 Size2
---@param depth integer
---@param name? string
---@return Image
function Image:new(size2,depth,name)
  local obj=setmetatable({},self)
  obj.type="Image"
  obj.size2=size2 or Size2:new(1,1,16,16)
  obj.depth=depth or 8
  obj.extended=false
  obj.pixelsize=obj.size2.sizeX*obj.size2.sizeY*2
  obj.rawdata=""
  obj.name=tostring(name) or "untitled"
  obj.preloaded=false
  obj.data={}
  return obj
end

---Parse the rawdata string and generate Text[] objects.
function Image:preload()
  if not self then return false end
  local pos=1
  local maxpos=#self.rawdata
  local x=self.size2.x1
  local y=self.size2.y1
  for iy=1,self.size2.sizeY do
    for ix=1,self.size2.sizeX do
      if pos>maxpos then
        tgl.util.log("Out of bounds! rawdata is too short! saving data for debug","Image/preload")
        self.preloaded=false
        return false
      end
      local c
      local char=tmg.char
      if self.extended==true then
        char=tmg.getExtendedChar(self.rawdata(pos))
        pos=pos+1
      end
      if self.depth==4 then
        c=tmg.byteToCol2(self.rawdata:byte(pos))
        pos=pos+1
      else --8bit
        c=tmg.bytesToCol2(self.rawdata:byte(pos),self.rawdata:byte(pos+1))
        pos=pos+2
      end
      table.insert(self.data,Text:new(char,c,Pos2:new(x+ix-1,y+iy-1)))
    end
  end
  self.preloaded=true
  return true
end

function Image:unload()
  self.data={}
  self.preloaded=false
  return true
end
---Tries to generate rawdata string bytes from data table
---@return boolean
function Image:convert()
  --Generates self.rawdata string from self.data array
  if not self.preloaded then return false end
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
---Saves to .tmg file format
---@param filename string
---@return boolean
function Image:save(filename)
  if not self then return false end
  local file=io.open(filename,"w")
  if not file then return false end
  --compression
  local compRLE=false
  local compDiff=false
  local rawdata=""
  if tmg.enableCompressing then
    rawdata,compRLE,compDiff=tmg.autoCompress(self.rawdata)
  else rawdata=self.rawdata end
  file:write("tmg\n")
  file:write(tmg.collectFlags(self.depth,compRLE,compDiff,self.extended).."\n")
  file:write(self.name.."\n")
  file:write(tostring(self.size2.sizeX).."\n")
  file:write(tostring(self.size2.sizeY).."\n")
  --rawdata
  file:write(rawdata)
  return true
end
---Loads from .tmg file format
---@param filename string
---@param pos2 Pos2? Position of image(defaults to 1,1)
---@return boolean|Image
function Image:load(filename,pos2)
  local file=io.open(filename)
  if not file then return false end
  if file:read("l")~="tmg" then return false end
  local depth,compRLE,compDiff,extended=tmg.getFlags(file:read("l"))
  local name=file:read("l")
  local sizeX=tonumber(file:read("l"))
  local sizeY=tonumber(file:read("l"))
  if not sizeX or not sizeY then return false end
  local size2
  if not pos2 then
    size2=Size2:newFromSize(1,1,sizeX,sizeY)
  else
    size2=Size2:newFromSize(pos2.x,pos2.y,sizeX,sizeY)
  end
  local img=Image:new(size2,depth,name)
  img.rawdata=tmg.decompress(file:read("*a"),compRLE,compDiff)
  return img
end

function Image:render()
  local saved_x,saved_y=term.getCursor()
  local saved_col2=tgl.getCurrentColor2()
  if self.preloaded then
    for i,pixel in ipairs(self.data) do
      pixel:render()
    end
    term.setCursor(saved_x,saved_y)
    tgl.changeToColor2(saved_col2,true)
    return true
  end
  ---rawrender
  ---@param x integer
  ---@param y integer
  ---@param col2 Color2
  ---@param char string
  local function writePixel(x,y,col2,char)
    if not char then char=tmg.char end
    if not tgl.util.pointInSize2(x,y,self.size2) then
      tgl.util.log("Trying to write in bad point: ("..x..","..y..") "..tgl.util.objectInfo(self.size2),"Image/render")
    end
    tgl.changeToColor2(col2)
    term.setCursor(x,y)
    term.write(char)
  end
  if not self.rawdata then return false end
  local pos=1
  local maxpos=#self.rawdata
  local x=self.size2.x1
  local y=self.size2.y1
  for iy=1,self.size2.sizeY do
    for ix=1,self.size2.sizeX do
      if pos>maxpos then
        tgl.util.log("Out of bounds! rawdata is too short!","Image/render")
        break
      end
      local c
      local char=tmg.char
      if self.extended==true then
        char=tmg.getExtendedChar(self.rawdata(pos))
        pos=pos+1
      end
      if self.depth==4 then
        c=tmg.byteToCol2(self.rawdata:byte(pos))
        pos=pos+1
      else --8bit
        c=tmg.bytesToCol2(self.rawdata:byte(pos),self.rawdata:byte(pos+1))
        pos=pos+2
      end
      writePixel(x+ix-1,y+iy-1,c,char)
    end
  end
  term.setCursor(saved_x,saved_y)
  tgl.changeToColor2(saved_col2,true)
  return true
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
<bin> --rawdata
upper=foreground
lower=background

tmg flags
1000 color depth (0=4bit 1=8bit)
0100 compression (RLE)
0010 compression (diff)
0001 extended mode(1byte for char)
]]