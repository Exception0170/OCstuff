---TGLv10 init file
local tgl={}
tgl.version="0.10.0"
tgl=dofile("/usr/lib/tgl/core.lua")(tgl)
tgl=dofile("/usr/lib/tgl/event.lua")(tgl)
tgl=dofile("/usr/lib/tgl/defaults.lua")(tgl)
tgl=dofile("/usr/lib/tgl/theme.lua")(tgl)
tgl=dofile("/usr/lib/tgl/renderer.lua")(tgl)
tgl=dofile("/usr/lib/tgl/util.lua")(tgl)
tgl=dofile("/usr/lib/tgl/gradient.lua")(tgl)
tgl=dofile("/usr/lib/tgl/objects.lua")(tgl)
tgl=dofile("/usr/lib/tgl/widgets.lua")(tgl)
tgl=dofile("/usr/lib/tgl/input.lua")(tgl)

--Image code and codec tables are loaded only when first requested.
setmetatable(tgl,{__index=function(self,key)
  if key=="Image" or key=="img" then
    local img=dofile("/usr/lib/tgl/image.lua")(self)
    self.img=img
    self.Image=img.Image
    return rawget(self,key)
  end
end})

---Release library listeners, timers and GPU buffers before leaving the UI.
function tgl.finish()
  if tgl.sys.input then tgl.sys.input:destroy() end
  local ok=tgl.sys.renderer:finish()
  tgl.sys.events:clear()
  return ok
end

tgl.Renderer:init()
tgl.sys.renderer:start()
tgl.sys.resetActiveArea()
tgl.util.log("TGL version "..tgl.version.." loaded!")
return tgl
