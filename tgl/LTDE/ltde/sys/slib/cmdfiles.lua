local fs=require("filesystem")
local cmdfiles={}

-- Compare mounted filesystem identities as well as paths (a disk can have aliases).
local function identity(path)
  local best=nil
  local key=path
  for proxy,mount in fs.mounts() do
    mount=fs.canonical(mount)
    if mount=="/" or path==mount or path:sub(1,#mount+1)==mount.."/" then
      if not best or #mount>#best then
        best=mount
        key=tostring(proxy.address or proxy)..":"..(mount=="/" and path or path:sub(#mount+1))
      end
    end
  end
  return key
end

cmdfiles.identity=identity

function cmdfiles.transfer(ctx,args,move)
  local overwrite=false
  local paths={}
  local stop=false
  for _,arg in ipairs(args) do
    if not stop and arg=="--" then stop=true
    elseif not stop and (arg=="-f" or arg=="--force") then overwrite=true
    elseif not stop and arg:sub(1,1)=="-" then return 1,"Unknown option: "..arg
    else table.insert(paths,arg) end
  end
  if #paths~=2 then return 1,(move and "move" or "copy").." [-f] <source-file> <destination>" end
  local src,dst=ctx:resolve(paths[1]),ctx:resolve(paths[2])
  if not fs.exists(src) then return 1,"File not found: "..src end
  if fs.isDirectory(src) then return 1,"This command currently supports files only." end
  if fs.isDirectory(dst) then dst=fs.concat(dst,fs.name(src)) end
  -- Do not follow symbolic links when overwriting or removing file data.
  local function linked(path)
    while path~="/" and path~="" do
      if fs.isLink and fs.isLink(path) then return true end
      path=fs.path(path):gsub("/$","")
    end
    return false
  end
  if linked(src) or linked(dst) then return 1,"Symbolic-link paths are not supported." end
  if src==dst or identity(src)==identity(dst) then return 1,"Source and destination are the same file." end
  if fs.isDirectory(dst) then return 1,"Destination is a directory: "..dst end
  if fs.exists(dst) and not overwrite then return 1,"Destination exists; use -f to overwrite." end
  local ok,err=fs.copy(src,dst)
  if not ok then return 1,err or "Copy failed." end
  if move then
    local removed,removeErr=fs.remove(src)
    if not removed then return 1,"Copied, but source could not be removed: "..tostring(removeErr) end
  end
  ctx:print((move and "Moved " or "Copied ")..src.." -> "..dst)
end

return cmdfiles
