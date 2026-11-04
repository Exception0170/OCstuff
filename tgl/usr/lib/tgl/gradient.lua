local unicode=require("unicode")
return function(tgl)
---@class tgl.Gradient
---@field from integer RGB start color
---@field to integer RGB end color
---@field vertical boolean
---@field steps integer|nil Optional number of color bands
tgl.Gradient={}
tgl.Gradient.__index=tgl.Gradient
local function rgb(color)
  return type(color)=="number" and color==color and color%1==0 and color>=0 and color<=0xFFFFFF
end
local function valid(gradient)
  return type(gradient)=="table" and rgb(gradient.from) and rgb(gradient.to)
    and type(gradient.vertical)=="boolean" and (gradient.steps==nil or
      type(gradient.steps)=="number" and gradient.steps>=2 and gradient.steps<math.huge and gradient.steps%1==0)
end
function tgl.Gradient:new(from,to,vertical,steps)
  checkArg(1,from,"number")
  checkArg(2,to,"number")
  checkArg(3,vertical,"boolean","nil")
  checkArg(4,steps,"number","nil")
  local obj=setmetatable({type="Gradient",from=from,to=to,vertical=vertical or false,steps=steps},self)
  if not valid(obj) then return nil end
  return obj
end
local function areaValid(area)
  if type(area)~="table" then return false end
  for _,key in ipairs({"x1","y1","x2","y2"}) do
    local value=area[key]
    if type(value)~="number" or value~=value or value%1~=0 or math.abs(value)==math.huge then return false end
  end
  return area.x2>=area.x1 and area.y2>=area.y1
end
local function colorAt(gradient,offset,length)
  local t=length<=1 and 0 or math.max(0,math.min(1,offset/(length-1)))
  if gradient.steps then t=math.floor(t*(gradient.steps-1)+0.5)/(gradient.steps-1) end
  local color=0
  for shift=16,0,-8 do
    local a=(gradient.from >> shift)&255
    local b=(gradient.to >> shift)&255
    color=color | (math.floor(a+(b-a)*t+0.5) << shift)
  end
  return color
end
local function colorValue(r,col2,index)
  if col2.is_palette then return r.gpu.getPaletteColor(col2[index]) end
  return col2[index]
end
local function visible(r,cmd,area)
  local x1,y1,x2,y2=area.x1,area.y1,area.x2,area.y2
  if cmd.buffer==0 then
    x1,y1=math.max(1,x1),math.max(1,y1)
    x2,y2=math.min(r._sw,x2),math.min(tgl.defaults.screenSizeY,y2)
  end
  local clip=cmd.clipRegion
  if clip then
    x1,y1=math.max(x1,clip.x1),math.max(y1,clip.y1)
    x2,y2=math.min(x2,clip.x2),math.min(y2,clip.y2)
  end
  if x1>x2 or y1>y2 then return nil end
  return {x1=x1,y1=y1,x2=x2,y2=y2}
end
local function textBounds(pos2,text,vertical)
  local width,height=unicode.wlen(text),1
  if vertical then
    width=1 height=math.max(1,unicode.len(text))
    for i=1,unicode.len(text) do width=math.max(width,unicode.wlen(unicode.sub(text,i,i))) end
  end
  return {x1=pos2.x,y1=pos2.y,x2=pos2.x+math.max(1,width)-1,y2=pos2.y+height-1}
end
tgl.Renderer.cmd.gradient=function(r,cmd)
  local area=cmd.size2
  local clip=visible(r,cmd,area)
  if not clip then return true end
  local g=cmd.gradient
  local first,last=g.vertical and clip.y1 or clip.x1,g.vertical and clip.y2 or clip.x2
  local origin=g.vertical and area.y1 or area.x1
  local length=g.vertical and (area.y2-area.y1+1) or (area.x2-area.x1+1)
  local cell={cmd="fill",char=" ",size2={},col2={colorValue(r,cmd.col2,1),0},
    z_index=cmd.z_index,buffer=cmd.buffer,clipRegion=cmd.clipRegion}
  local start,color=first,colorAt(g,first-origin,length)
  for i=first+1,last+1 do
    local nextColor=i<=last and colorAt(g,i-origin,length) or nil
    if nextColor~=color then
      local s=cell.size2
      s.x1=g.vertical and clip.x1 or start s.x2=g.vertical and clip.x2 or i-1
      s.y1=g.vertical and start or clip.y1 s.y2=g.vertical and i-1 or clip.y2
      s.sizeX=s.x2-s.x1+1 s.sizeY=s.y2-s.y1+1
      cell.col2[2]=color
      if not r:execCmd(cell) then return false end
      start,color=i,nextColor
    end
  end
  return true
end
tgl.Renderer.cmd.gradienttext=function(r,cmd)
  local x,y=cmd.pos2.x,cmd.pos2.y
  local bounds=textBounds(cmd.pos2,cmd.value,cmd.vertical)
  if not visible(r,cmd,bounds) then return true end
  local area,g=cmd.area,cmd.gradient
  local origin=g.vertical and area.y1 or area.x1
  local length=g.vertical and (area.y2-area.y1+1) or (area.x2-area.x1+1)
  local fixed=colorValue(r,cmd.col2,cmd.foreground and 2 or 1)
  local cell={cmd="set",pos2={},col2={fixed,fixed},vertical=cmd.vertical,
    z_index=cmd.z_index,buffer=cmd.buffer,clipRegion=cmd.clipRegion}
  local run,color,startX,startY={},nil,x,y
  local function draw()
    if #run==0 then return true end
    cell.pos2.x=startX cell.pos2.y=startY
    cell.value=table.concat(run) cell.col2[cmd.foreground and 1 or 2]=color
    return r:execCmd(cell)
  end
  for i=1,unicode.len(cmd.value) do
    local char=unicode.sub(cmd.value,i,i)
    local nextColor=colorAt(g,(g.vertical and y or x)-origin,length)
    if nextColor~=color then
      if not draw() then return false end
      run={} startX,startY=x,y color=nextColor
    end
    run[#run+1]=char
    if cmd.vertical then y=y+1 else x=x+unicode.wlen(char) end
  end
  return draw()
end

---Queue a background gradient; clipping keeps the original gradient coordinates.
function tgl.Renderer:gradient(size2,gradient,col2,z_index,buf)
  checkArg(1,size2,"table")
  checkArg(2,gradient,"table")
  checkArg(3,col2,"table","nil")
  checkArg(4,z_index,"number","nil")
  checkArg(5,buf,"number","nil")
  if not areaValid(size2) or not valid(gradient) then return false end
  return self:addCmd({cmd="gradient",size2=size2,gradient=gradient,
    col2=col2 or tgl.defaults.colors2.black,z_index=z_index,buffer=buf})
end
---Write text with background colors sampled from the same gradient area.
function tgl.Renderer:gradientText(pos2,text,gradient,area,col2,z_index,vertical,buf)
  checkArg(1,pos2,"table")
  checkArg(2,text,"string")
  checkArg(3,gradient,"table")
  checkArg(4,area,"table","nil")
  checkArg(5,col2,"table","nil")
  checkArg(6,z_index,"number","nil")
  checkArg(7,vertical,"boolean","nil")
  checkArg(8,buf,"number","nil")
  if not valid(gradient) then return false end
  if type(pos2.x)~="number" or type(pos2.y)~="number" then return false end
  area=area or textBounds(pos2,text,vertical)
  if not areaValid(area) or not areaValid({x1=pos2.x,y1=pos2.y,x2=pos2.x,y2=pos2.y}) then return false end
  if text=="" then return true end
  return self:addCmd({cmd="gradienttext",pos2=pos2,value=text,gradient=gradient,area=area,
    col2=col2 or tgl.defaults.colors2.black,z_index=z_index,vertical=vertical,buffer=buf})
end
return tgl end
