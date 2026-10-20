local unicode=require("unicode")
local lterm={}
lterm.__index=lterm
-- Windows color attributes: high digit=background, low digit=foreground.
lterm.palette={
  [0]=0x000000,0x000080,0x008000,0x008080,0x800000,0x800080,0x808000,0xAAAAAA,
  0x555555,0x0000FF,0x00FF00,0x00FFFF,0xFF0000,0xFF00FF,0xFFFF00,0xFFFFFF
}

function lterm:new(width,height)
  return setmetatable({width=width or 60,height=height or 16,lines={""},styles={{}},
    limit=200,scroll=0,foreground=self.palette[7],background=self.palette[0]},self)
end

function lterm:write(text)
  text=tostring(text or "")
  if self.onWrite then self.onWrite(text) end
  for i=1,unicode.len(text) do
    local char=unicode.sub(text,i,i)
    if char=="\n" then
      table.insert(self.lines,"") table.insert(self.styles,{})
    elseif char~="\r" then
      if char=="\t" then char="  " end
      if unicode.wlen(self.lines[#self.lines])+unicode.wlen(char)>self.width then
        table.insert(self.lines,"") table.insert(self.styles,{})
      end
      self.lines[#self.lines]=self.lines[#self.lines]..char
      local spans=self.styles[#self.styles]
      local last=spans[#spans]
      if last and last.foreground==self.foreground and last.background==self.background then
        last.text=last.text..char
      else
        table.insert(spans,{text=char,foreground=self.foreground,background=self.background})
      end
    end
    if #self.lines>self.limit then table.remove(self.lines,1) table.remove(self.styles,1) end
  end
  self.scroll=0
end

function lterm:print(text)
  self:write(tostring(text or "").."\n")
end

function lterm:clear()
  self.lines={""} self.styles={{}} self.scroll=0
end

function lterm:setColors(foreground,background)
  local function valid(c) return type(c)=="number" and c>=0 and c<=0xFFFFFF and c%1==0 end
  if not valid(foreground) or not valid(background) then return nil,"Invalid RGB color." end
  self.foreground=foreground self.background=background
  return true
end

function lterm:getColors()
  return self.foreground,self.background
end

function lterm:setColor(attribute,recolor)
  attribute=tostring(attribute or "07")
  if not attribute:match("^%x%x?$") then return nil,"Use one or two hex digits, e.g. 2 or 1f." end
  if #attribute==1 then attribute="0"..attribute end
  local bg=tonumber(attribute:sub(1,1),16)
  local fg=tonumber(attribute:sub(2,2),16)
  if fg==bg then return nil,"Foreground and background must differ." end
  self:setColors(self.palette[fg],self.palette[bg])
  if recolor then
    for _,spans in ipairs(self.styles) do
      for _,span in ipairs(spans) do span.foreground=self.foreground span.background=self.background end
    end
  end
  return true
end

function lterm:scrollBy(n)
  local value=math.max(0,math.min(math.max(0,#self.lines-self.height),self.scroll+n))
  if value==self.scroll then return false end
  self.scroll=value
  return true
end

function lterm:getLines()
  local lines={}
  local first=math.max(1,#self.lines-self.height-self.scroll+1)
  for i=first,math.min(#self.lines,first+self.height-1) do table.insert(lines,self.lines[i]) end
  return lines
end

function lterm:getRows()
  local rows={}
  local first=math.max(1,#self.lines-self.height-self.scroll+1)
  for i=first,math.min(#self.lines,first+self.height-1) do table.insert(rows,self.styles[i]) end
  return rows
end

function lterm:getText()
  return table.concat(self.lines,"\n")
end

return lterm
