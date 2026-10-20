local fs=require("filesystem")
local tgl=require("tgl")
local ltfiletypes={}

---Return an optional foreground; callers own the fallback and selection colors.
function ltfiletypes.color(path,isDir)
  local cfg=ltcfg and ltcfg.filetypes
  if not cfg then return nil end
  local name=path:gsub("/+$",""):match("[^/]+$") or ""
  name=name:lower()
  if isDir==nil then isDir=fs.isDirectory(path) end
  local value
  if name:match("%.app$") then value=cfg:get("types","app")
  elseif isDir then value=cfg:get("types","directory")
  else value=cfg:get("extensions",name:match("%.([^%.]+)$") or "") end
  if type(value)=="string" then value=tgl.defaults.colors16[value:lower()] end
  if type(value)=="number" and value>=0 and value<=0xFFFFFF and value==math.floor(value) then return value end
end

function ltfiletypes.reload()
  local cfg,err=cfglib.load("/ltde/cfg/filetypes.conf")
  if not cfg then return nil,err end
  ltcfg.filetypes=cfg
  return true
end

return ltfiletypes
