local fs=require("filesystem")
local ltfiles={}

local function identity(path)
  path=fs.canonical(path)
  local best,key=nil,path
  for proxy,mount in fs.mounts() do
    mount=fs.canonical(mount)
    if mount=="/" or path==mount or path:sub(1,#mount+1)==mount.."/" then
      if not best or #mount>#best then
        best=mount
        local rest=mount=="/" and path or path:sub(#mount+1)
        key=tostring(proxy.address or proxy)..":"..(rest=="" and "/" or rest)
      end
    end
  end
  return key:gsub("/+$","")
end

local function linked(path)
  while path~="/" and path~="" do
    if fs.isLink and fs.isLink(path) then return true end
    path=fs.path(path):gsub("/+$","")
  end
  return false
end

function ltfiles.same(a,b)
  return identity(a)==identity(b)
end

function ltfiles.validName(name)
  return type(name)=="string" and name~="" and name~="." and name~=".."
    and not name:find("[/\\%z\r\n]")
end

-- Sum file contents without following links or other mounted devices.
function ltfiles.info(path)
  path=fs.canonical(path)
  if not fs.exists(path) then return nil,"Item no longer exists." end
  local result={bytes=0,files=0,folders=0,skipped=0}
  local root=fs.get(path)
  local pending={path}
  local seen={}
  local checked=0
  while #pending>0 do
    local current=table.remove(pending)
    local ok,err=pcall(function()
      if fs.isLink and fs.isLink(current) then result.skipped=result.skipped+1 return end
      local proxy=fs.get(current)
      if root and proxy and root.address~=proxy.address then result.skipped=result.skipped+1 return end
      local key=identity(current)
      if seen[key] then result.skipped=result.skipped+1 return end
      seen[key]=true
      if fs.isDirectory(current) then
        if current~=path then result.folders=result.folders+1 end
        local iter,why=fs.list(current)
        if not iter then error(why or "Cannot read folder.",0) end
        for name in iter do pending[#pending+1]=fs.concat(current,name) end
      else
        local size=fs.size(current)
        if type(size)~="number" or size<0 or size==math.huge or size~=size then error("Size unavailable.",0) end
        result.bytes=result.bytes+size
        result.files=result.files+1
      end
    end)
    if not ok then result.skipped=result.skipped+1 result.error=tostring(err) end
    checked=checked+1
    if checked%32==0 then os.sleep(0) end
  end
  return result
end

-- Copy the whole tree successfully before removing any source of a move.
-- Skipping or cancelling leaves the original tree intact, including copied files.
function ltfiles.transfer(src,dst,move,opts)
  opts=opts or {}
  src,dst=fs.canonical(src),fs.canonical(dst)
  local function check(from,to)
    if linked(from) or linked(to) then return nil,"Symbolic-link paths are not supported." end
    local a,b=identity(from),identity(to)
    if a==b then return nil,"Source and destination are the same item." end
    if fs.isDirectory(from) and b:sub(1,#a+1)==a.."/" then
      return nil,"Cannot copy a folder into itself."
    end
    return true
  end
  local valid,reason=check(src,dst)
  if not valid then return nil,reason end
  if not fs.exists(src) then return nil,"Source no longer exists." end
  if not fs.isDirectory(fs.path(dst)) then return nil,"Destination folder does not exist." end

  -- Refuse mounted subtrees and links before a move can remove their contents.
  local seen={}
  local rootProxy=fs.get(src)
  local function inspect(path)
    if linked(path) then return nil,"Symbolic-link paths are not supported." end
    local proxy=fs.get(path)
    if rootProxy and proxy and rootProxy.address~=proxy.address then
      return nil,"Folders containing mounted devices are not supported."
    end
    local key=identity(path)
    if seen[key] then return nil,"Repeated filesystem path in source tree." end
    seen[key]=true
    if fs.isDirectory(path) then
      local iter,err=fs.list(path)
      if not iter then return nil,err or "Cannot read folder." end
      for name in iter do
        local ok,why=inspect(fs.concat(path,name))
        if not ok then return nil,why end
      end
    end
    return true
  end
  valid,reason=inspect(src)
  if not valid then return nil,reason end

  local function copy(from,to)
    local ok,err=check(from,to)
    if not ok then return nil,err end
    local dir=fs.isDirectory(from)
    if fs.exists(to) and not (dir and fs.isDirectory(to)) then
      local action=opts.conflict and opts.conflict(fs.name(to)) or "Cancel"
      if action=="Cancel" or not action then return nil,"Cancelled.",true end
      if action=="Skip" then return nil,"Skipped; source kept." end
      if action=="Rename" then
        local name=opts.rename and opts.rename()
        if not name then return nil,"Cancelled.",true end
        if not ltfiles.validName(name) then return nil,"Invalid destination name." end
        to=fs.concat(fs.path(to),name)
        if fs.exists(to) then return nil,"Renamed destination already exists." end
        ok,err=check(from,to)
        if not ok then return nil,err end
      elseif action~="Replace" then return nil,"Unknown conflict action." end
      if fs.exists(to) and (dir or fs.isDirectory(to)) then
        return nil,"Cannot replace a file with a folder or a folder with a file."
      end
    end
    if opts.update then opts.update(from) end
    if dir then
      if not fs.exists(to) then
        ok,err=fs.makeDirectory(to)
        if not ok then return nil,err end
      end
      local iter,listErr=fs.list(from)
      if not iter then return nil,listErr or "Cannot read folder." end
      for name in iter do
        local stopped
        ok,err,stopped=copy(fs.concat(from,name),fs.concat(to,name))
        if not ok then return nil,err,stopped end
      end
      if opts.completed then opts.completed(from) end
      return true
    end
    local copied,copyErr=fs.copy(from,to)
    if copied and opts.completed then opts.completed(from) end
    return copied,copyErr
  end
  local copied,err,stopped=copy(src,dst)
  if not copied then return nil,err,stopped end
  if move then
    local removed,removeErr=fs.remove(src)
    if not removed then return nil,"Copied, but source could not be removed: "..tostring(removeErr) end
  end
  return true
end

return ltfiles
