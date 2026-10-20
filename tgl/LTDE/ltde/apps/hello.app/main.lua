local event=require("event")
local tgl=require("tgl")

local doneName="hello_done_"..string.sub(tostring(math.random(1,1000000)),1,-3)

local frame,cs=ltwapi.addWindow(28,8,"Hello World",{
  onClose=function() event.push(doneName) end
})
if not frame then return end

local col=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)

local msgText=tgl.Text:new("  Hello from LTDEv1!",col,tgl.Pos2:new(cs.x1,cs.y1+1))
local notifyBtn=tgl.Button:new("  Say Hello!  ",function()
  ltnotify.notify("Hello World","Greetings from LTDE!",3)
end,tgl.Pos2:new(cs.x1+1,cs.y1+3),col)

frame:add(msgText,"msg")
frame:add(notifyBtn,"notify")

notifyBtn:enable()
local r=tgl.sys.renderer
r:stop()
frame:render()
r:flush()

-- wait for window to be closed (by user or by system shutdown)
event.pull(doneName)
event.push(doneName.."_actually exited")