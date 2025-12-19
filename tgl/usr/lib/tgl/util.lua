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
  return tgl.Color2:new(r.gpu.getForeground(),r.gpu.getBackground())
end

return tgl end