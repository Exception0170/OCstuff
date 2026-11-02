--Read-only, bounded NBT inspection. OC returns item tags as gzip-compressed NBT.
local nbt={}
local limit=32768
local function gunzip(data)
  if data:sub(1,3)~="\31\139\8" or #data<18 then error("Invalid gzip tag.",0) end
  local expected=string.unpack("<I4",data,#data-3)
  if expected>limit then error("NBT exceeds the 32 KiB viewer limit.",0) end
  local flags=data:byte(4)
  if flags&224~=0 then error("Invalid gzip flags.",0) end
  local pos=11
  if flags&4~=0 then
    local size=string.unpack("<I2",data,pos) pos=pos+2+size
  end
  for _,flag in ipairs({8,16}) do
    if flags&flag~=0 then
      local finish=data:find("\0",pos,true)
      if not finish then error("Invalid gzip header.",0) end
      pos=finish+1
    end
  end
  if flags&2~=0 then pos=pos+2 end
  local buffer,bits=0,0
  local function read(count)
    while bits<count do
      if pos>#data-8 then error("Truncated gzip tag.",0) end
      buffer=buffer|(data:byte(pos)<<bits) bits=bits+8 pos=pos+1
    end
    local value=buffer&((1<<count)-1)
    buffer=buffer>>count bits=bits-count return value
  end
  local function tree(lengths)
    local counts,nextCode,codes={},{},{}
    for _,length in pairs(lengths) do
      if length>0 then counts[length]=(counts[length] or 0)+1 end
    end
    local code=0
    for length=1,15 do
      code=(code+(counts[length-1] or 0))<<1
      if code+(counts[length] or 0)>1<<length then error("Invalid Huffman tree.",0) end
      nextCode[length]=code codes[length]={}
    end
    local maximum=-1 for symbol in pairs(lengths) do maximum=math.max(maximum,symbol) end
    for symbol=0,maximum do
      local length=lengths[symbol] or 0
      if length>0 then
        local value,reverse=nextCode[length],0
        for _=1,length do reverse=(reverse<<1)|(value&1) value=value>>1 end
        codes[length][reverse]=symbol nextCode[length]=nextCode[length]+1
      end
    end
    return codes
  end
  local function symbol(codes)
    local code=0
    for length=1,15 do
      code=code|(read(1)<<(length-1))
      if codes[length][code]~=nil then return codes[length][code] end
    end
    error("Invalid Huffman symbol.",0)
  end
  local lengthBase={3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
  local lengthBits={0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
  local distanceBase={1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
  local distanceBits={0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
  local out={}
  local function append(char)
    if #out>=limit then error("NBT exceeds the 32 KiB viewer limit.",0) end
    out[#out+1]=char
    if #out%1024==0 then os.sleep(0) end
  end
  local final=0
  repeat
    final=read(1)
    local kind=read(2)
    if kind==0 then
      buffer=0 bits=0
      local count=read(16)
      if read(16)~=(count~65535) then error("Invalid stored block.",0) end
      for _=1,count do append(string.char(read(8))) end
    elseif kind==1 or kind==2 then
      local lengths,distances={},{}
      if kind==1 then
        for i=0,287 do lengths[i]=i<144 and 8 or i<256 and 9 or i<280 and 7 or 8 end
        for i=0,31 do distances[i]=5 end
      else
        local literalCount,distanceCount,codeCount=read(5)+257,read(5)+1,read(4)+4
        local order={16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
        local codeLengths={}
        for i=1,codeCount do codeLengths[order[i]]=read(3) end
        local codeTree=tree(codeLengths)
        local all,index={},0
        while index<literalCount+distanceCount do
          local value=symbol(codeTree)
          local count=1
          if value==16 then
            if index==0 then error("Missing repeated code length.",0) end
            value=all[index-1] count=read(2)+3
          elseif value==17 then value=0 count=read(3)+3
          elseif value==18 then value=0 count=read(7)+11 end
          if index+count>literalCount+distanceCount then error("Invalid code lengths.",0) end
          for _=1,count do all[index]=value index=index+1 end
        end
        for i=0,literalCount-1 do lengths[i]=all[i] end
        for i=0,distanceCount-1 do distances[i]=all[literalCount+i] end
      end
      if not lengths[256] or lengths[256]==0 then error("Missing end-of-block code.",0) end
      local literals,distancesTree=tree(lengths),tree(distances)
      while true do
        local value=symbol(literals)
        if value<256 then append(string.char(value))
        elseif value==256 then break
        else
          local index=value-256
          if not lengthBase[index] then error("Invalid match length.",0) end
          local count=lengthBase[index]+read(lengthBits[index])
          local distance=symbol(distancesTree)+1
          if not distanceBase[distance] then error("Invalid match distance.",0) end
          distance=distanceBase[distance]+read(distanceBits[distance])
          if distance>#out then error("Match before tag start.",0) end
          for _=1,count do append(out[#out-distance+1]) end
        end
      end
    else error("Invalid gzip block.",0) end
  until final==1
  if #out~=expected then error("Invalid gzip size.",0) end
  return table.concat(out)
end
function nbt.decode(data)
  if data:sub(1,2)=="\31\139" then data=gunzip(data) end
  if #data>limit then error("NBT exceeds the 32 KiB viewer limit.",0) end
  local pos,nodes=1,0
  local function read(format)
    local value,nextPos=string.unpack(">"..format,data,pos) pos=nextPos return value
  end
  local function text()
    local size=read("I2")
    if pos+size-1>#data then error("Truncated NBT string.",0) end
    local value=data:sub(pos,pos+size-1):gsub("\192\128","\0") pos=pos+size return value
  end
  local value
  value=function(kind,depth)
    nodes=nodes+1
    if depth>32 or nodes>4096 then error("NBT is too complex to display.",0) end
    local formats={[1]="i1",[2]="i2",[3]="i4",[4]="i8",[5]="f",[6]="d"}
    if formats[kind] then return read(formats[kind]) end
    if kind==8 then return text() end
    if kind==10 then
      local result={}
      while true do
        local child=read("I1")
        if child==0 then return result end
        local name=text() result[name]=value(child,depth+1)
      end
    end
    if kind==7 or kind==9 or kind==11 or kind==12 then
      local child=kind==9 and read("I1") or kind==7 and 1 or kind==11 and 3 or 4
      local count=read("i4")
      if count<0 or count>4096-nodes then error("NBT array is too large to display.",0) end
      local result={}
      for i=1,count do result[i]=value(child,depth+1) end
      return result
    end
    error("Unknown NBT tag type: "..kind,0)
  end
  local kind=read("I1") text()
  return value(kind,0)
end
local function quoted(value)
  local text=tostring(value)
  if #text>limit then text=text:sub(1,limit).."<truncated>" end
  return string.format("%q",text):gsub("\n","\\n"):gsub("[\128-\255]",function(char)return string.format("\\x%02X",char:byte())end)
end
local function scalar(value)
  if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
  return quoted(value)
end
function nbt.describe(row)
  local lines={"Item: "..quoted(row.label),"Has NBT: "..(row.nbt and "yes" or "no"),""}
  local seen={}
  local function show(value,indent)
    if #lines>=256 then return end
    if #indent>64 then lines[#lines+1]=indent.."<depth limit>" return end
    if type(value)~="table" then lines[#lines+1]=indent..scalar(value) return end
    if not next(value) then lines[#lines+1]=indent.."{}" return end
    if seen[value] then lines[#lines+1]=indent.."<recursive>" return end
    seen[value]=true
    local keys={} for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    for _,key in ipairs(keys) do
      if #lines>=256 then break end
      if type(value[key])=="table" then
        lines[#lines+1]=indent..quoted(key)..":" show(value[key],indent.."  ")
      else lines[#lines+1]=indent..quoted(key).." = "..scalar(value[key]) end
    end
    seen[value]=nil
  end
  if row.tag then
    local tag=row.tag
    if type(tag)=="string" and (tag:byte(1)==10 or tag:sub(1,2)=="\31\139") then
      local ok,result=pcall(nbt.decode,tag)
      if ok then tag=result else lines[#lines+1]="Cannot decode NBT: "..tostring(result) tag=nil end
    end
    if tag then show(tag,"") end
  elseif row.nbt then
    lines[#lines+1]="Full NBT was not exposed by OpenComputers."
    lines[#lines+1]="Enable allowItemStackNBTTags in OC's config, then refresh."
  else lines[#lines+1]="This item has no NBT tag." end
  if row.metadata and next(row.metadata) then
    lines[#lines+1]="" lines[#lines+1]="Other exposed item metadata:"
    show(row.metadata,"")
  end
  if #lines>=256 then lines[#lines+1]="<display limited to 256 lines>" end
  return lines
end
return nbt
