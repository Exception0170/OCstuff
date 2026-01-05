local unicode=require("unicode")
return function(tgl)

---Gets line of desired length starting at pos2
---@param pos2 tgl.Pos2
---@param len integer
---@return string
function tgl.util.getLine(pos2,len)
  local s=""
  for i=1,len do
    local char=tgl.sys.renderer:getPoint(pos2.x+i-1,pos2.y)
    s=s..char
  end
  return s
end

---Checks if line at pos2 is matches text[and same color as col2, if given]
---@param pos2 tgl.Pos2
---@param text string
---@param col2? tgl.Color2
function tgl.util.getLineMatched(pos2,text,col2)
  local r=tgl.sys.renderer
  if type(pos2)~="table" then return end
  if not text then return end
  if text=="" then return 0 end
  local matched=0
  local dolog=true
  for i=1,unicode.wlen(text) do
    local char,col=r:getPoint(pos2.x+i-1,pos2.y)
    if char==unicode.sub(text,i,i) then
      if col2 then
        if col2==col then
          matched=matched+1
        else
          --tgl.util.log("Color mismatch: "..tostring(bgcol).." "..tostring(col2[2]),"Util/getLineMatched")
          if r.gpu.getDepth()==4 and dolog then tgl.util.log("4bit color problem, refer to tgl.defaults.colors16","Util/getLineMatched") end
          dolog=false
        end
      else matched=matched+1
      end
    else
      --tgl.util.log(char.."!="..unicode.sub(text,i,i),"Util/getLineMatched")
    end
  end
  return matched
end

---Gets current cursor color2
---@return tgl.Color2
function tgl.getCurrentColor2()
  local r=tgl.sys.renderer
  local fg_col,fg_ispalette=r.gpu.getForeground()
  local bg_col,bg_ispalette=r.gpu.getBackground()
  if fg_ispalette and bg_ispalette then
    return tgl.Color2:new(fg_col,bg_col,true)
  elseif not fg_ispalette and not bg_ispalette then
    return tgl.Color2:new(fg_col,bg_col)
  else --fallback to regular colors
    if fg_ispalette then
      fg_col=r.gpu.getPaletteColor(fg_col)
    else
      bg_col=r.gpu.getPaletteColor(bg_col)
    end
    return tgl.Color2:new(fg_col,bg_col)
  end
end

---Changes cursor color to given Color2
---@param col2 tgl.Color2
---@param ignore? boolean if function should ignore previous color
---@return tgl.Color2|false|nil
function tgl.changeToColor2(col2,ignore)
  if not col2 then return false end
  local r=tgl.sys.renderer
  local old=nil
  if not ignore then
    old=tgl.getCurrentColor2()
  end
  if col2.is_palette then
    local success=pcall(function()
      r.gpu.setForeground(col2[1],true)
      r.gpu.setBackground(col2[2],true)
    end)
    if not success then
      tgl.util.log("Couldn't change to palette color2! indexes: "..tostring(col2[1]).." "..tostring(col2[2]),"Util")
      return false
    end
    return old
  end
  r.gpu.setForeground(col2[1])
  r.gpu.setBackground(col2[2])
  return old
end

return tgl end