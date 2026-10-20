local unicode=require("unicode")
local splash={}

local _tgl=nil
local _frameSize=nil
local _frameBgCol=nil
local _frameTextCol=nil
local _statusRelY=nil
local _frameZ=nil
local _statusDelay=0.25
local _progress=nil
local _progressValue=0

function splash.showStartup(wallCol,delay)
  _statusDelay=math.max(0,tonumber(delay) or 0.25)
  _tgl=require("tgl")
  local r=_tgl.sys.renderer
  local sw=_tgl.defaults.screenSizeX
  local sh=_tgl.defaults.screenSizeY

  _frameZ=5
  _frameBgCol=_tgl.Color2:new(0,_tgl.defaults.colors16.lightgray)
  _frameTextCol=_frameBgCol

  -- ┌────────────────────────────────────────┐
  -- │  EDIT STARTUP SCREEN CONTENT BELOW     │
  -- └────────────────────────────────────────┘
  local FW=43   -- must be >= logo width + 2 border cols
  local FH=13
  local logo=[[
██      ████████ ██████  ███████      ██
██         ██    ██   ██ ██          ███
██         ██    ██   ██ █████        ██
██         ██    ██   ██ ██           ██
███████    ██    ██████  ███████      ██]]
  local sub="Lightweight TGL Desktop Environment"
  local ver=tostring(_G._ltde_version or "")
  -- ─────────────────────────────────────────

  local function c(text)  -- center relX within frame
    return math.floor((FW-unicode.wlen(text))/2)+1
  end

  local cx=math.floor(sw/2)
  local cy=math.floor(sh/2)
  local fx=cx-math.floor(FW/2)
  local fy=cy-math.floor(FH/2)
  _frameSize=_tgl.Size2:newFromSize(fx,fy,FW,FH)
  _statusRelY=10

  local dimCol=_tgl.Color2:new(_tgl.defaults.colors16.darkgray,_tgl.defaults.colors16.lightgray)
  local logoCol=_tgl.Color2:new(_tgl.defaults.colors16.darkblue,_tgl.defaults.colors16.lightgray)

  local logoBox=_tgl.TextBox:new(logo,_tgl.Size2:newFromSize(2,2,FW-2,5),logoCol)
  logoBox.showScroll=false
  local subT=_tgl.Text:new(sub,dimCol,_tgl.Pos2:new(c(sub),7))
  local verT=_tgl.Text:new(ver,dimCol,_tgl.Pos2:new(c(ver),8))
  local statusT=_tgl.Text:new("Loading...",_frameBgCol,_tgl.Pos2:new(c("Loading..."),_statusRelY))

  _progressValue=0
  _progress=require("tgl-ui").Progressbar:new(_tgl.Pos2:new(3,11),FW-4,
    _tgl.Color2:new(_tgl.defaults.colors16.darkblue,0xFFFFFF))
  local frame=_tgl.Frame:new({logo=logoBox,sub=subT,ver=verT,status=statusT,progress=_progress},_frameSize,_frameBgCol)
  frame.z_index=_frameZ
  frame.borders="─│┌┐└┘"

  r:stop()
  r:fill(_tgl.Size2:newFromSize(1,1,sw,sh)," ",wallCol,0)
  frame:render()
  r:flush()
end

-- Update the status line while booting.
function splash.setStatus(msg,progress)
  if not _tgl or not _frameSize or not _statusRelY then return end
  local r=_tgl.sys.renderer
  local fx=_frameSize.x1
  local fy=_frameSize.y1
  local FW=_frameSize.sizeX
  local statusY=fy+_statusRelY-1
  msg=tostring(msg or "")
  while unicode.wlen(msg)>FW-2 do msg=unicode.sub(msg,1,unicode.len(msg)-1) end
  local lw=unicode.wlen(msg)
  local textX=fx+math.floor((FW-lw)/2)
  r:stop()
  r:fill(_tgl.Size2:newFromSize(fx+1,statusY,FW-2,1)," ",_frameBgCol,_frameZ)
  r:set(_tgl.Pos2:new(textX,statusY),msg,_frameTextCol,_frameZ)
  if _progress and type(progress)=="number" and progress==progress then
    _progressValue=math.max(_progressValue,math.min(1,math.max(0,progress)))
    _progress:setValue(_progressValue)
    _progress:render()
  end
  r:flush(true)
end

-- Release startup state before the desktop replaces it.
function splash.finishStartup()
  if _tgl and _statusDelay>0 then os.sleep(_statusDelay) end
  _progress=nil
  _frameSize=nil
  _tgl=nil
end

-- Full-screen shutdown overlay. Call before tgl.sys.renderer:finish().
function splash.showShutdown()
  local tgl=require("tgl")
  local r=tgl.sys.renderer
  local sw=tgl.defaults.screenSizeX
  local sh=tgl.defaults.screenSizeY
  local cx=math.floor(sw/2)
  local cy=math.floor(sh/2)
  local wallCol=tgl.sys.wm and tgl.sys.wm.bgCol2
    or tgl.Color2:new(0xFFFFFF,tgl.defaults.colors16.cyan)
  local bgCol=tgl.Color2:new(0,tgl.defaults.colors16.lightgray)
  local Z=10000

  local FW=30
  local FH=4
  local fx=cx-math.floor(FW/2)
  local fy=cy-math.floor(FH/2)
  local frameSize=tgl.Size2:newFromSize(fx,fy,FW,FH)

  local function c(text)
    return math.floor((FW-unicode.wlen(text))/2)+1
  end

  local frame=tgl.Frame:new({
    title=tgl.Text:new("Shutting down",bgCol,tgl.Pos2:new(c("Shutting down"),2)),
    body=tgl.Text:new("Please wait...",bgCol,tgl.Pos2:new(c("Please wait..."),3)),
  },frameSize,bgCol)
  frame.z_index=Z
  frame.borders="─│┌┐└┘"

  r:stop()
  r:fill(tgl.Size2:newFromSize(1,1,sw,sh)," ",wallCol,Z-1)
  frame:render()
  r:flush()
end

return splash
