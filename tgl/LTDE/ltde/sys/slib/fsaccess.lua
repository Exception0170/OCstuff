local fs=require("filesystem")

-- Bound filesystem access for non-system apps; never expose system configs.
return function(appRoot,fullDiskIO)
  local root=fs.canonical(appRoot)
  local function inside(path,base)
    return path==base or path:sub(1,#base+1)==base.."/"
  end
  local function identity(path)
    local best,key=nil,path
    for proxy,mount in fs.mounts() do
      mount=fs.canonical(mount)
      if mount=="/" or inside(path,mount) then
        if not best or #mount>#best then
          best=mount
          local rest=mount=="/" and path or path:sub(#mount+1)
          key=tostring(proxy.address or proxy)..":"..(rest=="" and "/" or rest)
        end
      end
    end
    return key:gsub("/+$","")
  end
  local function resolve(path,write)
    if type(path)~="string" then error("expected a path",3) end
    if path:sub(1,1)~="/" then path=fs.concat(root,path) end
    path=fs.canonical(path)
    if not fullDiskIO and not inside(path,root) then error("access denied: "..path,3) end
    local parent=path
    while parent~="/" and parent~="" do
      if fs.isLink(parent) then error("symbolic-link paths are not supported",3) end
      parent=fs.path(parent):gsub("/+$","")
    end
    local key,protected=identity(path),identity("/ltde/cfg")
    if inside(key,protected) or (write and inside(protected,key)) then
      error("system configuration requires system mode",3)
    end
    return path
  end
  local rfs={concat=fs.concat}
  rfs.open=function(p,m) return fs.open(resolve(p,m and m~="r" and m~="rb"),m) end
  for _,method in ipairs({"exists","isDirectory","list","size","lastModified"}) do
    local name=method
    rfs[name]=function(p) return fs[name](resolve(p)) end
  end
  rfs.makeDirectory=function(p) return fs.makeDirectory(resolve(p,true)) end
  rfs.remove=function(p) return fs.remove(resolve(p,true)) end
  rfs.rename=function(a,b) return fs.rename(resolve(a,true),resolve(b,true)) end
  rfs.canonical=function(p) return resolve(p) end
  return rfs,resolve
end
