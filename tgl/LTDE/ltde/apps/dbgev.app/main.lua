local event=require("event")
local tgl=require("tgl")
local computer=require("computer")
local r=tgl.sys.renderer

local doneName="dbgev_done_"..string.sub(tostring(math.random(1,1000000)),1,-3)

local frame,cs=ltwapi.addWindow(50,12,"dbgev.app",{
  onClose=function() event.push(doneName) end
})
if not frame then return end

local col=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
local whitelist={
  drag=true,touch=true,drop=true,key_up=true,key_down=true,
  renderDone=true,scroll=true,thread_exit=true
}

frame:add(tgl.Text:new("Events debug (common whitelisted)",col,tgl.Pos2:new(1,2)))
frame:add(tgl.Frame:new({},tgl.Size2:new(1,3,50,10),col),"list")

local lines={}
local function addStr(str)
  lines[#lines+1]=str
  if #lines>10 then table.remove(lines,1) end
  frame.objects.list.objects={}
  for i,line in ipairs(lines) do
    local txt=tgl.Text:new(line,col,tgl.Pos2:new(1,i))
    txt.maxLength=50
    frame.objects.list.objects[i]=txt
  end
  frame.objects.list:translate()
end

r:stop()
frame:render()
r:flush()

while true do
  local res={event.pull()}
  local ev=res[1]
  if ev==doneName then break end
  if not whitelist[ev] then
    local t=string.format("%.1f",computer.uptime())
    local parts={"["..t.."]",ev}
    for i=2,#res do parts[#parts+1]=tostring(res[i]) end
    addStr(table.concat(parts," "))
    r:stop()
    frame:render()
    r:flush()
  end
end
