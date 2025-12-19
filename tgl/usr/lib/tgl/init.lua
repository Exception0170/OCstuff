---TGLv8 init file
local tgl={}
tgl.version="0.8.01"
tgl=dofile("/usr/lib/tgl/core.lua")(tgl)
tgl=dofile("/usr/lib/tgl/defaults.lua")(tgl)
tgl=dofile("/usr/lib/tgl/renderer.lua")(tgl)
tgl=dofile("/usr/lib/tgl/util.lua")(tgl)
tgl=dofile("/usr/lib/tgl/objects.lua")(tgl)

tgl.Renderer:init()
tgl.sys.renderer:start()
tgl.util.log("TGL version "..tgl.version.." loaded!")
return tgl