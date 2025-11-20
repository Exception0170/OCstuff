local tmg=require("tgl-img")
local tgl=require("tgl")
local term=require("term")
local function help()
  local helpmsg=[[TMG Image viewer
  Simply give it a file name and it will print an image.
  Press any key to close it afterwards.
  Supported image format: .tmg
  Usage: tmgview <filename>
  ]]
  print(helpmsg)
end

local function view(filename)
  local file=io.open(filename)
  if not file then
    tgl.cprint("Couldn't open file: "..filename)
    return
  end
  local img=Image:load(filename)
  if not img then
    tgl.cprint("Couldn't open image")
    return
  end
  term.clear()
  img:render()
  require("event").pull("key_down")
  term.clear()
  tgl.cprint("Image stats",Color2:new(tgl.defaults.colors16.yellow))
  print("Name: "..img.name)
  print("Shape: "..img.size2.sizeX.."x"..img.size2.sizeY.."("..img.size2.sizeX.."x"..(img.size2.sizeY*2)..")")
  print("Color depth: "..img.depth.."bit")
  print("Extended: "..tostring(img.extended))
  print("")
end

local args=require("shell").parse(...)
if not args[1] then help() else view(args[1]) end