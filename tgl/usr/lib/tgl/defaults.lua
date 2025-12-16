return function(tgl)
---Frequently used symbols, colors
tgl.defaults={
  foregroundColor=0xFFFFFF,
  backgroundColor=0,
  ---4bit color palette
  colors16={},
  ---Frequently used characters
  chars={
    full="█",darkshade="▓",mediumshade="▒",
    lightshade="░",sqrt="√",check="✔",
    cross="❌",save="💾",folder="📁",
    fileempty="🗋",file="🗎",email="📧"
  },
  ---For box art
  boxes={
    double="═║╔╗╚╝╠╣╦╩╬",
    signle="─│┌┐└┘├┤┬┴┼",
    round= "─│╭╮╰╯├┤┬┴┼"
  },
  ---Key values for input reading
  keys={
    backspace=8,delete=127,null=0,
    enter=13,space=32,ctrlz=26,
    ctrlc=3,ctrlv=22,esc=27
  }
}
if require("component").gpu.getDepth()==8 then --different bitdepth results in different 16 colors palette
  tgl.defaults.colors16={
    white=0xFFFFFF,gold=0xFFDB40,magenta=0xCC6DBF,lightblue=0X6692FF,
    yellow=0xFFFF00,lime=0x00FF00,pink=0xFF6D80,darkgray=0x2D2D2D,
    lightgray=0xD2D2D2,cyan=0x336D80,purple=0x9924BF,darkblue=0x332480,
    brown=0x662400,darkgreen=0x336D00,red=0xFF0000,black=0x0
  }
else
  tgl.defaults.colors16={
    white=0xFFFFFF,gold=0xFFCC33,magenta=0xCC66CC,lightblue=0x6699FF,
    yellow=0xFFFF33,lime=0x33CC33,pink=0xFF6699,darkgray=0x333333,
    lightgray=0xCCCCCC,cyan=0x336699,purple=0x9933CC,darkblue=0x333399,
    brown=0x663300,darkgreen=0x336600,red=0xFF3333,black=0x0
  }
end
tgl.defaults.screenSizeX,tgl.defaults.screenSizeY=require("component").gpu.getResolution()
---Frequently used Color2 objects
tgl.defaults.colors2={}
tgl.defaults.colors2.error=tgl.Color2:new(tgl.defaults.colors16.red,0)
tgl.defaults.colors2.black=tgl.Color2:new(0xFFFFFF,0)
tgl.defaults.colors2.white=tgl.Color2:new(0,0xFFFFFF)
tgl.defaults.colors2.close=tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.red)
tgl.defaults.colors2.progressbar=tgl.Color2:new(tgl.defaults.colors16.lime,0xFFFFFF)
return tgl end