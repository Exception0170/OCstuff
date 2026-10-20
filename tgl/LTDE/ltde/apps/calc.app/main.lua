--LTDE Calculator
local tgl=require("tgl")
local calc=assert(loadfile("/ltde/sys/slib/ltcalc.lua"))()
local uid=tostring(math.random(1,1000000))
local close="calc_close_"..uid
local press="calc_press_"..uid
local gray=tgl.Color2:new(0,0xD2D2D2)
local white=tgl.Color2:new(0,0xFFFFFF)
local frame=ltwapi.addWindow(36,20,"Calculator",{
  onClose=function() ltevent.push(close) end
})
if not frame then return 1 end
local wm=tgl.sys.wm
local input,answer="",0
local extended=false
local evaluated=false
local display=tgl.Text:new("0",white,tgl.Pos2:new(2,3)) display.maxLength=32
local status=tgl.Text:new("Basic | Keyboard ready",gray,tgl.Pos2:new(2,4)) status.maxLength=32
frame:add(display,"display") frame:add(status,"status")
local function button(text,value,x,y,key)
  local b=tgl.EventButton(text,press,value,tgl.Pos2:new(x,y),gray)
  b.onClick=nil
  frame:add(b,key)
  return b
end
local mode=button("[Extended]","mode",2,6,"mode")
button("[C]","clear",16,6,"clear")
button("[Back]","back",24,6,"back")
local rows={{"7","8","9","/","("},{"4","5","6","*",")"},{"1","2","3","-","ans"},{"0",".","=","+","neg"}}
for row,values in ipairs(rows) do
  for col,value in ipairs(values) do button("["..value.."]",value,2+(col-1)*7,8+(row-1)*2,"key"..row..col) end
end
local scientific={}
for i,value in ipairs({"sqrt","sin","cos","tan","^","ln","log","abs","pi","e"}) do
  scientific[i]=button("["..value.."]",value,2+(i-1)%5*7,16+math.floor((i-1)/5)*2,"science"..i)
  scientific[i].hidden=true
end
local function redraw()
  display.text=(input=="" and "0" or input):sub(-32)
  local managed=wm and wm:getManagedWindow(frame)
  if managed and not frame.hidden then wm:renderRegions({wm:getWindowBounds(managed)}) end
end
local function insert(text)
  if evaluated and not text:match("^[+*/^%-]") then input="" end
  evaluated=false
  if #input+#text>512 then status.text="Maximum 512 characters." return end
  input=input..text
end
local function action(value)
  status.text=extended and "Extended | Angles in radians" or "Basic | Keyboard ready"
  if value=="mode" then
    extended=not extended
    mode.text=extended and "[Basic]" or "[Extended]"
    for _,b in ipairs(scientific) do
      b.hidden=not extended
      if extended and not frame.hidden then b:enable() else b:disable() end
    end
    status.text=extended and "Extended | Angles in radians" or "Basic | Keyboard ready"
  elseif value=="clear" then input="" evaluated=false
  elseif value=="back" then input=input:sub(1,-2) evaluated=false
  elseif value=="neg" then
    if #input>509 then status.text="Maximum 512 characters."
    else input="-("..(input=="" and "0" or input)..")" evaluated=false end
  elseif value=="=" then
    local result,err=calc.evaluate(input,extended,answer)
    if result==nil then
      status.text="Invalid expression"
      ltnotify.warn("Calculator",err)
    else answer=result input=calc.format(result) evaluated=true end
  elseif value:match("^[a-z]+$") and value~="ans" and value~="pi" and value~="e" then insert(value.."(")
  else insert(value) end
  redraw()
end
local ok,err=pcall(function()
  frame:enableAll()
  redraw()
  while true do
    local ev,a,b,c=ltevent.pull()
    if ev==close or ev=="ltde_shutdown" then break end
    if ev==press then action(a)
    elseif ev=="key_down" then
      if c==28 or c==156 or b==61 then action("=")
      elseif c==14 then action("back")
      elseif c==211 or c==1 then action("clear")
      elseif c==60 then action("mode")
      elseif b and b>=32 and b<=126 then insert(string.char(b)) redraw() end
    elseif ev=="clipboard" and type(b)=="string" then
      insert((b:gsub("[^%w%s%.+*/%^()_-]",""):gsub("%s"," "))) redraw()
    end
  end
end)
frame:disableAll()
ltwapi.removeWindow(frame)
if not ok then error(err,0) end
return 0
