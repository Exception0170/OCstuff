local fs=require("filesystem")
local ltassoc={}

function ltassoc.scan(cfg)
  local result={}
  local apps={}
  local iter=fs.list("/ltde/apps")
  if iter then
    for name in iter do
      name=name:gsub("/+$","")
      if name:match("%.app$") then apps[#apps+1]=name end
    end
  end
  table.sort(apps)
  for _,name in ipairs(apps) do
    local path=fs.concat("/ltde/apps",name)
    local chunk=loadfile(fs.concat(path,"manifest.lua"),"t",{})
    if chunk then
      local ok,manifest=pcall(chunk)
      if ok and type(manifest)=="table" and type(manifest.opens)=="table" then
        for _,ext in ipairs(manifest.opens) do
          if type(ext)=="string" then
            ext=ext:lower():gsub("^%.","")
            if ext~="" and not result[ext] then result[ext]=path end
          end
        end
      end
    end
  end
  if cfg then
    for _,ext in ipairs(cfg:keys("extensions")) do
      result[ext:lower()]=cfg:get("extensions",ext)
    end
    result["*"]=cfg:get("","default",result["*"])
  end
  return result
end

return ltassoc
