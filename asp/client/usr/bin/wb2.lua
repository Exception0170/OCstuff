local tgl=require("tgl")
local asp=require("asp")
local event=require("event")
local unicode=require("unicode")
--setup values
local white=tgl.defaults.colors2.white
local topbar_blue=Color2:new(0xFFFFFF,tgl.defaults.colors16.lightblue)
local urlbar_gray=Color2:new(0,tgl.defaults.colors16.lightgray)
local tab_gray=Color2:new(0,0xD2D2D2)
local browser={}
browser.topbar_current="none"
browser.current_tab=-1
browser.tabsize=10
browser.tabOffset=1
--functions

--setup objects
local main_frame=Frame:new({},Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY),white)

--topbar
local topbar=Bar:new(Pos2:new(1,1),{},topbar_blue,topbar_blue)
topbar:add(Text:new("WebBrowser2 devbuild2"))
topbar:add(Button:new("Tab",function() event.push("browser_topbar_open","tab_frame") end),25,"tab_button")
topbar:add(Button:new("View",function() event.push("browser_topbar_open","view_frame") end),29,"view_button")
topbar:add(Button:new("Settings",function() event.push("browser_topbar_open","settings_frame") end),34,"settings_button")
topbar:add(Button:new("Help",function() event.push("browser_topbar_open","help_frame") end),43,"help_button")
topbar:add(Button:new(" X ",function() event.push("browser_close") end,nil,tgl.defaults.colors2.close),tgl.defaults.screenSizeX-2,"close_button",true)
--[[
Tab: new tab,close tab,save page as,quit
View: reload view,
Settings
Help


]]
--tabbar
local tabbar=Frame:new(Size2:new(1,2,tgl.defaults.screenSizeX,1),{},urlbar_gray)
tabbar:add(EventButton:new("+","browser_newtab",Pos2:new(2,1),urlbar_gray),"new_button")
--" #########X #########X #########X #########X #########X #########X < + > 10 tabs"
Tab={}
Tab.__index=Tab
function Tab:new(title)
  title=title or "Untitled"
  if unicode.len(title)>8 then
    title=unicode.sub(title,1,6)..".."
  end
  local obj=setmetatable({},Tab)
  local xpos=2+(#tabbar.objects*(browser.tabsize+1))
  --if xpos
  obj.button=Frame:new({title=Button:new(title,function() event.push("browser_opentab","") end,Pos2:new(1,1),tab_gray),
  close=Button:new("X",function() event.push("browser_closetab","")end,Pos2:new(10,1),tab_gray)},Size2:new(xpos,1,10,1),tab_gray)
  obj.button.num=#tabbar.objects+1
  tabbar:add(obj.button)
  tabbar:update()
  --tab
  
  --Button:new(title or "New tab",function() event.push("browser_tab_open",obj.num)end,nil,urlbar_gray)
end
--urlbar
local urlbar=Bar:new(Pos2:new(1,3),{},urlbar_gray,urlbar_gray)
urlbar:add(Button:new("<",function() event.push("browser_urlbar_func","tab_back") end),2,"back_button")
urlbar:add(Button:new(">",function() event.push("browser_urlbar_func","tab_forward") end),7,"forward_button")
urlbar:add(Button:new("🔄",function() event.push("browser_urlbar_func","tab_reload") end),4,"reload_button")
urlbar:add(Text:new("URL:",Color2:new(tgl.defaults.colors16.darkgray,tgl.defaults.colors16.lightgray)),10,"text_label",true)
urlbar:add(InputField:new(tgl.util.strgen(" ",60)),15,"url_field")

--main
main_frame:add(topbar,"topbar")
main_frame:add(tabbar,"tabbar")
main_frame:add(urlbar,"urlbar")
main_frame.objects.topbar:enableAll()
main_frame.objects.urlbar:enableAll()
main_frame:render()
while true do
  local id,value=event.pullMultiple("browser_close","browser_topbar_open","browser_urlbar_func","browser_newtab")
  if id=="browser_close" then
    main_frame:disableAll()
    break
  elseif id=="browser_topbar_open" then

  end
end
os.sleep(.1)
require("term").clear()