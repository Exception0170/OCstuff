local tgl=require("tgl")
local tui=require("tgl-ui")
local term=require("term")
local gpu=require("component").gpu
local event=require("event")
local mnp=require("cmnp")
local ip=require("ipv2")
local filename="/etc/.cm_last_netuuid"
--setup values
local version="1.4"
local blue=Color2:new(0xFFFFFF,tgl.defaults.colors16.darkblue)
local gray=Color2:new(0,tgl.defaults.colors16.lightgray)
local red=Color2:new(tgl.defaults.colors16.red,0xFFFFFF)
local gold=Color2:new(tgl.defaults.colors16.gold,0xFFFFFF)
local green=Color2:new(tgl.defaults.colors16.darkgreen,0xFFFFFF)
local checkboxcol=Color2:new(tgl.defaults.colors16.darkgreen,tgl.defaults.colors16.lightgray)
local progressbarcol=Color2:new(tgl.defaults.colors16.lime,tgl.defaults.colors16.darkgray)
local white=tgl.defaults.colors2.white
local app_offset_x=5
local app_offset_y=3
local app_size_x=29
local app_size_y=10
local app_current_frame="menu_frame"

local app_size=Size2:new(app_offset_x,app_offset_y,app_size_x,app_size_y)
local notify_size=Size2:new(7,8,25,5)
--functions
local function savePrevAddress(name)
  local file=io.open(filename,"w")
  if not file then return end
  file:write(name)
  file:close()
end
local function loadPrevAddress()
  local file=io.open(filename,"r")
  if not file then return nil end
  local name=file:read("*a")
  file:close()
  return name
end
function notify(msg)
  local notify_frame=tui.notificationWindow(notify_size,"CMTUI",msg,blue,gray)
  notify_frame.objects.text.col2=gray
  notify_frame.objects.close_button.eventName="cmtui_close_notif"
  tgl.sys.setActiveArea(notify_size)
  notify_frame:open()
  event.pull("cmtui_close_notif")
  os.sleep(.1)
  notify_frame:close()
  notify_frame=nil
  tgl.sys.resetActiveArea()
end
function getpassword()
  local window=tui.notificationWindow(notify_size,"CMTUI","Enter password",blue,gray)
  if not window then return end
  window.objects.icon.relpos2.y=2
  window.objects.text.relpos2.y=2
  window:add(InputField:new("[___________________]",Pos2:new(3,3),gray),"input")
  window.objects.input.secret=true
  window.objects.close_button.eventName="cmtui_enter_pass"
  window:open()
  event.pull("cmtui_enter_pass")
  os.sleep(.1)
  window:close()
  local pass=window.objects.input.text
  window=nil
  tgl.sys.resetActiveArea()
  return pass
end
function getdomain(allow_ipv2)
  local window=tui.notificationWindow(notify_size,"CMTUI","Enter domain",blue,gray)
  if not window then return end
  window.objects.icon.relpos2.y=2
  window.objects.text.relpos2.y=2
  window:add(InputField:new("[___________________]",Pos2:new(3,3),white),"input")
  window.objects.close_button.eventName="cmtui_enter_domain"
  window:open()
  os.sleep(.1)
  local name
  while true do
    event.pull("cmtui_enter_domain")
    name=window.objects.input.text
    if mnp.checkHostname(name) then break
    elseif name=="" then name="" break
    elseif allow_ipv2 then
      if ip.isIPv2(name) then break
      else
        window.objects.text:updateText("Please try again.")
      end
    else
      window.objects.text:updateText("Please try again.")
    end
  end
  os.sleep(.1)
  window:close()
  window=nil
  tgl.sys.resetActiveArea()
  return name
end

--setup objects
local back_frame=Frame:new({},Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY),blue)

local status_frame=Frame:new({},Size2:new(2,2,app_size_x-1,app_size_y-1),white)
status_frame:add(Button:new("Close",function() event.push("cmtui_open","menu_frame") end,Pos2:new(2,2),tgl.defaults.colors2.close),"close_button")
status_frame:add(Text:new("Not connected",red,Pos2:new(3,3)),"status")
status_frame:add(Text:new("IPv2: ????:????",white,Pos2:new(3,4)),"ip")
status_frame:add(Text:new("Dynamic IPv2: ",white,Pos2:new(3,5)))
status_frame:add(Text:new("disabled",red,Pos2:new(17,5)),"dynamic")
status_frame:add(Text:new("Network name: unknown",white,Pos2:new(3,6)),"netname")
function status_frame:main()
  local this_ip=os.getenv("this_ip")
  if not this_ip or not mnp.isConnected() then
    status_frame.objects.status.text="Not connected"
    status_frame.objects.status.col2=red
    status_frame.objects.ip.text="-"
    status_frame.objects.dynamic.text="-"
    status_frame.objects.dynamic.col2=white
    status_frame.objects.netname.text="-"
    return
  end
  status_frame.objects.ip.text="IPv2: "..this_ip
  status_frame.objects.status.text="Connected!"
  status_frame.objects.status.col2=green
  status_frame.objects.netname.text="Network: "..mnp.getSavedNodeName(loadPrevAddress())
  local n,c=ip.getParts(this_ip)
  if c~=string.sub(require("component").modem.address,1,4) then
    status_frame.objects.dynamic.text="enabled"
    status_frame.objects.dynamic.col2=green
  else
    status_frame.objects.dynamic.text="disabled"
    status_frame.objects.dynamic.col2=red
  end
  os.sleep(.1)
  status_frame:render()
end
status_frame:close()

local connect_frame=Frame:new({},Size2:new(2,2,app_size_x-1,app_size_y-1),white)
connect_frame:add(Text:new("Select network",white,Pos2:new(5,1)))
connect_frame:add(InputField:new("[__________________]",Pos2:new(2,2),gray),"input")
connect_frame:add(Text:new("",white,Pos2:new(2,3)),"found")
connect_frame:add(CheckBox:new(Pos2:new(19,5),checkboxcol,1,"*"),"static_checkbox")
connect_frame:add(Text:new("Use static IPv2",white,Pos2:new(3,5)))
connect_frame:add(Text:new("Selected:",white,Pos2:new(2,4)))
connect_frame:add(Text:new("loading..",white,Pos2:new(12,4)),"netname")
connect_frame:add(tgl.EventButton("Connect","cmtui_connect",nil,Pos2:new(4,6),gray),"connect_button")
connect_frame:add(tgl.EventButton("Cancel","cmtui_connect_cancel",nil,Pos2:new(13,6),tgl.defaults.colors2.close),"cancel_button")
connect_frame.objects.input.eventName="cmtui_connect_name"
local connecting_frame=Frame:new({},Size2:new(2,8,25,2),gray)
connecting_frame:add(Text:new("Connecting:",gray,Pos2:new(1,1)))
connecting_frame:add(Text:new("awaiting..",gray,Pos2:new(12,1)),"connect_status")
connecting_frame:add(Progressbar:new(Pos2:new(5,2),10,progressbarcol),"progressbar")
connecting_frame:add(Text:new("?%",gray,Pos2:new(1,2)),"percent")
connecting_frame.ignoreOpen=true
connect_frame:add(connecting_frame,"connecting_frame")
function connect_frame:main()
  mnp.openPorts()
  local name,address,password,node_ip
  address=loadPrevAddress()
  name,password,node_ip=mnp.getSavedNodeName(address)
  if name then
    connect_frame.objects.netname:updateText(name)
    connect_frame.objects.found.col2=green
    connect_frame.objects.found:updateText("Loaded previous")
  end
  while true do
    local id,newname=event.pullMultiple("closeCMTUI","cmtui_connect","cmtui_connect_cancel","cmtui_connect_name")
    if id=="cmtui_connect_cancel" then
      event.push("cmtui_open","menu_frame")
      break
    elseif id=="closeCMTUI" then
      os.sleep(.1)
      tgl.changeToColor2(tgl.defaults.colors2.black)
      term.clear()
      os.exit()
    elseif id=="cmtui_connect_name" then
      name=newname
      connect_frame.objects.netname:updateText(name)
      address,password,node_ip=mnp.getSavedNode(name)
      if not address then
        connect_frame.objects.found.col2=red
        connect_frame.objects.found:updateText("Couldn't find network")
      else
        connect_frame.objects.found.col2=green
        connect_frame.objects.found:updateText("Network found")
      end
    else --connect
      if not address then
        notify("Can't connect!")
      else
        os.sleep(.1)
        local static=connect_frame.objects.static_checkbox.value
        connect_frame.objects.connecting_frame:open(true)
        local function state(msg,val)
          connect_frame.objects.connecting_frame.objects.connect_status:updateText(msg)
          connect_frame.objects.connecting_frame.objects.progressbar:setValue(val,true)
          connect_frame.objects.connecting_frame.objects.percent:updateText(tostring(100*val).."%")
        end
        state("Starting",0)
        if mnp.isConnected() then mnp.disconnect() state("Disconnecting",0) end
        state("Saving address..",0.1)
        savePrevAddress(address)
        state("Requesting..",0.3)
        require("thread").create(function() event.pull(5,"modem") state("Received",0.6) end):detach()
        local check,password_required=mnp.networkConnectByName(address,name,password,not static)
        if check then
          state("Done",1)
          os.sleep(.1)
          notify("Connected!")
          event.push("cmtui_open","menu_frame")
          connect_frame.objects.connecting_frame:close()
          break
        elseif password_required then
          local new_password=getpassword()
          if mnp.networkConnectByName(address,name,new_password,not static) then
            mnp.addNodePassword(node_ip,new_password)
            notify("Connected!")
          else
            notify("Incorrect password!")
          end
        else
          notify("Couldn't connect")
        end
      end
    end
  end
  connect_frame:disableAll()
end
connect_frame:close()

local function disconnect()
  os.sleep(.1)
  if os.getenv("node_uuid") then mnp.disconnect() end
  notify("Disconnected!")
end
local function reconnect()
  os.sleep(.1)
  local address,password,node_ip,name,force_static
  local n,c=ip.getParts(os.getenv("this_ip"))
  if c~=string.sub(require("component").modem.address,1,4) then force_static=false
  else force_static=true end
  if os.getenv("node_uuid") then mnp.disconnect() end
  address=loadPrevAddress()
  name,password,node_ip=mnp.getSavedNodeName(address)
  local check,password_required=mnp.networkConnectByName(address,name,password,not force_static)
  if check then
    notify("Reconnected!")
  elseif password_required then
    local new_password=getpassword()
    if mnp.networkConnectByName(address,name,new_password,not force_static) then
      mnp.addNodePassword(node_ip,new_password)
      notify("Connected!")
    else
      notify("Incorrect password!")
    end
  else
    notify("Couldn't connect")
  end
end
local function setdomain()
  os.sleep(.1)
  if not mnp.isConnected(true) then
    notify("Not connected!")
  else
    local name=getdomain()
    if name=="" then return end
    if mnp.setDomain(name) then
      notify("Success")
    else
      notify("Couldn't set domain")
    end
  end
end
local function calculateStats(array)
  local max = array[1]
  local min = array[1]
  local sum = 0
  for _, value in ipairs(array) do
      if value>max then max=value end
      if value < min then min = value end
      sum=sum+value
  end
  local average = sum / #array
  return max, min, average
end
local function roundTime(value)
  return math.floor(value*100+0.5)/100
end
local function nping()
  os.sleep(.1)
  if not mnp.isConnected() then
    notify("Not connected!")
    return
  end
  tgl.sys.setActiveArea(Size2:new(5,4,35,8))
  local window=tgl.defaults.window(Size2:new(5,4,35,8),"Node Ping",blue,gray)
  if not window then return end
  window:add(Text:new("Pinging node "..string.sub(os.getenv("node_uuid"),1,4)..":0000",gray,Pos2:new(2,2)))
  window:open()
  local n=4
  local times={}
  for i=1,n do
    local str=""
    local time=mnp.mncp.nodePing()
    if not time then str=i..")Ping timeout." times[i]=0
    else time=roundTime(time) str=i..")Ping: "..time.."s" times[i]=time end
    window:add(Text:new(str,gray,Pos2:new(2,2+i)),"ping"..i)
    window.objects["ping"..i]:render()
  end
  local max,min,avg=calculateStats(times)
  window:add(Text:new("Ping statistics:",gray,Pos2:new(2,7)))
  window:add(Text:new("max: "..max.."s min: "..min.."s avg: "..avg.."s",gray,Pos2:new(2,8)))
  window:render()
  window:enableAll()
  event.pull("closeNode Ping")
  os.sleep(.1)
  window:close()
  tgl.sys.resetActiveArea()
  window=nil
end
local function cping()
  os.sleep(.1)
  if not mnp.isConnected() then
    notify("Not connected!")
    return
  end
  local dest=getdomain(true)
  if dest=="" then return end
  local check,to_ip=mnp.checkAvailability(dest)
  if not check then
    notify("Couldn't find host!")
    return false
  end
  local window=tgl.defaults.window(Size2:new(5,4,35,8),"Client Ping",blue,gray)
  if not window then return end
  tgl.sys.setActiveArea(Size2:new(5,4,35,8))
  window:add(Text:new("Pinging client "..to_ip,gray,Pos2:new(2,2)))
  window:open()
  local n=4
  local times={}
  for i=1,n do
    local str=""
    local time=mnp.mncp.c2cPing(to_ip)
    if not time then str=i..")Ping timeout." times[i]=0
    else time=roundTime(time) str=i..")Ping: "..time.."s" times[i]=time end
    window:add(Text:new(str,gray,Pos2:new(2,2+i)),"ping"..i)
    window.objects["ping"..i]:render()
  end
  local max,min,avg=calculateStats(times)
  window:add(Text:new("Ping statistics:",gray,Pos2:new(2,7)))
  window:add(Text:new("max: "..max.."s min: "..min.."s avg: "..avg.."s",gray,Pos2:new(2,8)))
  window:render()
  window:enableAll()
  event.pull("closeClient Ping")
  os.sleep(.1)
  window:close()
  tgl.sys.resetActiveArea()
  window=nil
end

local menu_frame=Frame:new({},Size2:new(2,2,app_size_x-1,app_size_y-1),white)
menu_frame:add(Text:new("Connection  Manager",white,Pos2:new(5,2)))
menu_frame:add(Text:new("Text User Interface",white,Pos2:new(5,3)))
menu_frame:add(Text:new("Version: "..version,white,Pos2:new(5,4)))
menu_frame:add(tgl.EventButton("Status","cmtui_open","status_frame",Pos2:new(3,6),white),"status_button")
menu_frame:add(tgl.EventButton("Connect","cmtui_open","connect_frame",Pos2:new(3,7),white),"connect_button")
menu_frame:add(Button:new("Disconnect",disconnect,Pos2:new(15,7),white),"disconnect_button")
menu_frame:add(Button:new("Reconnect",reconnect,Pos2:new(3,8),white),"reconnect_button")
menu_frame:add(Button:new("Set Domain",setdomain,Pos2:new(15,8),white),"setdomain_button")
menu_frame:add(Button:new("Ping Node",nping,Pos2:new(3,9),white),"nping_button")
menu_frame:add(Button:new("Ping Client",cping,Pos2:new(15,9),white),"cping_button")
function menu_frame:main() end
local window=tui.window_outlined(app_size,"CMTUI",tgl.defaults.boxes.double)
window:add(menu_frame,"menu_frame")
window:add(status_frame,"status_frame")
window:add(connect_frame,"connect_frame")
--main
back_frame:add(window,"window")
back_frame.objects.window.objects.topbar:enableAll()
back_frame.objects.window.objects.menu_frame:enableAll()
back_frame:render()
while true do
  local id,name=event.pullMultiple("closeCMTUI","cmtui_open")
  if id=="closeCMTUI" then break
  elseif id=="cmtui_open" then
    --close current
    os.sleep(.1)
    back_frame.objects.window.objects[app_current_frame]:close()
    --open needed
    back_frame.objects.window.objects[name]:open(true)
    back_frame.objects.window.objects[name].main()
  end
end
back_frame:disableAll()
os.sleep(.1)
tgl.changeToColor2(tgl.defaults.colors2.black,true)
term.clear()
--[[
window -> frame1
          frame2
          
    Connection  manager
    Text User Interface
      Version: 1.0 dev

  Status      Search
  Connect     Disconnect
  Reconnect   Set Domain
  Ping Node   Ping Client

  Reset
]]