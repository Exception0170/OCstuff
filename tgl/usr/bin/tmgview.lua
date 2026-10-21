local term=require("term")
local event=require("event")
local function help()
  print([[TMG Image viewer
  Simply give it a file name and it will print an image.
  Press any key to close it afterwards.
  Supported image format: .tmg
  Usage: tmgview [--inline|-i] <filename>
  --inline, -i: print at the cursor without clearing or waiting.
  ]])
end

local args,opts=require("shell").parse(...)
if not args[1] then help() return end
local tgl=require("tgl")
local tmg=require("tgl-img")

local function view(filename)
  local r=tgl.sys.renderer
  local ownsRenderer=not tgl.sys.wm
  local inline=opts.inline or opts.i
  local color=tgl.getCurrentColor2()
  local nextRow=nil
  local img=nil
  if ownsRenderer then r:start() end
  local success,msg=xpcall(function()
    local err
    img,err=tmg.Image:load(filename)
    if not img then error(err or "Couldn't open image",0) end
    if not inline then term.clear() end
    r:stop()
    local drawn,why
    if inline then
      local x,y=term.getCursor()
      local height=math.min(img.size2.sizeY,tgl.defaults.screenSizeY-1)
      local scroll=math.max(0,y+height-tgl.defaults.screenSizeY)
      if scroll>0 then term.scroll(scroll) y=y-scroll end
      img.autoPreload=false
      drawn,why=img:renderRegion({x1=1,y1=1,x2=img.size2.sizeX,y2=height},tgl.Pos2:new(x,y))
      nextRow=y+height
    else drawn,why=img:render() end
    if not drawn then error(why or "Couldn't render image",0) end
    r:flush(true)
    if not inline then event.pull("key_down") end
  end,debug.traceback)
  if img then img:unload() end
  r:flush()
  if ownsRenderer then r:finish() end
  if inline then
    tgl.changeToColor2(color)
    if nextRow then term.setCursor(1,nextRow) end
  else term.clear() end
  if not success then
    tgl.cprint("Couldn't display image:")
    tgl.cprint(msg)
    return
  end
  if inline then return end
  tgl.cprint("Image stats",tgl.Color2:new(tgl.defaults.colors16.yellow))
  print("Name: "..img.name)
  if img.extended then
    print("Shape: "..img.size2.sizeX.."x"..img.size2.sizeY)
  else
    print("Shape: "..img.size2.sizeX.."x"..img.size2.sizeY.."("..img.size2.sizeX.."x"..(img.size2.sizeY*2)..")")
  end
  print("Color depth: "..img.depth.."bit")
  print("Extended: "..tostring(img.extended))
  print("")
end

view(args[1])
