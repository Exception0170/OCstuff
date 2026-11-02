--Core-owned display power and idle tracking. Apps and services keep running.
local event=require("event")
local computer=require("computer")
local component=require("component")
local tgl=require("tgl")
return function(wm,getConfig)
  local display={}
  local screen=nil
  local wakePending=false
  local lastActivity=computer.uptime()
  local inputs={"key_down","key_up","touch","drag","drop","scroll","clipboard"}
  local function activity()
    lastActivity=computer.uptime()
    if screen and not wakePending then
      wakePending=true
      event.push("ltde_screen_wake")
    end
  end

  function display.off()
    if screen then return true end
    local r=tgl.sys.renderer
    if not r:setSuspended(true) then return false,"The renderer is busy. Try again." end
    local ok,result=pcall(function()
      local address=r.gpu.getScreen()
      if not address then error("No screen is connected.",0) end
      local target=component.proxy(address)
      target.turnOff()
      return target
    end)
    if not ok then r:setSuspended(false) return false,tostring(result) end
    screen=result
    return true
  end

  function display.wake()
    wakePending=false
    lastActivity=computer.uptime()
    if not screen then return true end
    local r=tgl.sys.renderer
    r:setSuspended(false)
    --Rebuild current app state before lighting the screen, including overlays.
    wm:renderRegions({tgl.Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY)})
    local ok,err=pcall(screen.turnOn)
    if not ok then r:setSuspended(true) return false,tostring(err) end
    screen=nil
    return true
  end

  function display.update()
    if screen then return end
    local cfg=getConfig()
    local timeout=tonumber(cfg and cfg:get("","screen_off_timeout",300)) or 300
    local now=computer.uptime()
    if timeout>0 and timeout<math.huge and now-lastActivity>=timeout then
      local ok,err=display.off()
      if not ok then
        lastActivity=now
        return false,err
      end
    end
    return true
  end

  function display.cleanup()
    for _,name in ipairs(inputs) do event.ignore(name,activity) end
    tgl.sys.renderer:setSuspended(false)
    if screen then pcall(screen.turnOn) screen=nil end
    wakePending=false
  end

  for _,name in ipairs(inputs) do event.listen(name,activity) end
  return display
end
