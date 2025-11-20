local tmg=require("tgl-img")
local tgl=require("tgl")

local function help()
  local helpmsg=[[TMG Image viewer
  Simply give it a file name and it will print an image.
  Supported image format: .tmg
  Usage: tmgview <filename>
  ]]
  print(helpmsg)
end

local function view(filename)
  local file=io.open(filename)
  if not file then
    local pre=tgl.changeToColor2(Color2:new(0,tgl.defaults.colors16.red),false)
    print("Couldn't open file: "..filename)
    tgl.changeToColor2(pre,true)
  end
  Image:load(filename):render()
end

local args=require("shell").parse(...)
if not args[1] then help() else view(args[1]) end