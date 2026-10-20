local fs=require("filesystem")
local cfglib={}

---@class CfgFile
---@field _path string|nil
---@field _sections string[]  ordered section names; "" = root
---@field _data table         [section][key] = value
---@field _meta table         [section][key] = {display,desc}
---@field _keyorder table     [section] = {key,...} insertion order
local CfgFile={}
CfgFile.__index=CfgFile

local function trim(s) return s:match("^%s*(.-)%s*$") end

local function parseValue(s)
  if s=="true"  then return true  end
  if s=="false" then return false end
  local hex=s:match("^0[xX](%x+)$")
  if hex then return tonumber(hex,16) end
  local num=tonumber(s)
  if num then return num end
  return s
end

local function serializeValue(v)
  local t=type(v)
  if t=="boolean" then return tostring(v) end
  if t=="number" then
    if math.floor(v)==v then return tostring(math.floor(v)) end
    return tostring(v)
  end
  return tostring(v)
end

---Create an empty CfgFile.
---@return CfgFile
function cfglib.new()
  return setmetatable({
    _path=nil,
    _sections={""},
    _data={[""]={} },
    _meta={},
    _keyorder={[""]={} },
  },CfgFile)
end

---Parse a .cfg file from disk.
---@param path string
---@return CfgFile|nil, string|nil err
function cfglib.load(path)
  local f,err=io.open(path,"r")
  if not f then return nil,tostring(err) end

  local cfg=cfglib.new()
  cfg._path=path
  local cur=""         -- current section ("" = root)
  local pending=nil    -- pending #: metadata for next key

  for line in f:lines() do
    line=trim(line)
    if line=="" then
      pending=nil
    elseif line:sub(1,2)=="#:" then
      local content=trim(line:sub(3))
      local display,desc=content:match("^([^|]+)|(.+)$")
      if display then
        pending={display=trim(display),desc=trim(desc)}
      else
        pending={display=content,desc=""}
      end
    elseif line:sub(1,1)=="#" then
      -- plain comment: leave pending untouched
    else
      local sec=line:match("^%[([%w_%-]+)%]$")
      if sec then
        cur=sec
        pending=nil
        if not cfg._data[sec] then
          cfg._data[sec]={}
          cfg._keyorder[sec]={}
          table.insert(cfg._sections,sec)
        end
      else
        local key,raw=line:match("^([%w_%-]+)%s*=%s*(.*)$")
        if key then
          cfg._data[cur][key]=parseValue(raw)
          table.insert(cfg._keyorder[cur],key)
          if pending then
            if not cfg._meta[cur] then cfg._meta[cur]={} end
            cfg._meta[cur][key]=pending
            pending=nil
          end
        end
        -- malformed lines are silently skipped
      end
    end
  end
  f:close()
  return cfg
end

---Get a value. section="" for root-level keys.
---@param section string
---@param key string
---@param default any
---@return any
function CfgFile:get(section,key,default)
  local s=self._data[section]
  if not s then return default end
  local v=s[key]
  if v==nil then return default end
  return v
end

---Set a value. Creates the section if it does not exist.
---@param section string
---@param key string
---@param value any
function CfgFile:set(section,key,value)
  if not self._data[section] then
    self._data[section]={}
    self._keyorder[section]={}
    table.insert(self._sections,section)
  end
  if self._data[section][key]==nil then
    table.insert(self._keyorder[section],key)
  end
  self._data[section][key]=value
end

---Return metadata for a key, or nil if none.
---@param section string
---@param key string
---@return {display:string,desc:string}|nil
function CfgFile:meta(section,key)
  return self._meta[section] and self._meta[section][key]
end

---List all section names in order (excludes "" root).
---@return string[]
function CfgFile:sections()
  local out={}
  for _,s in ipairs(self._sections) do
    if s~="" then out[#out+1]=s end
  end
  return out
end

---List all keys in a section in insertion order.
---@param section string
---@return string[]
function CfgFile:keys(section)
  return self._keyorder[section] or {}
end

---Save to original path or an explicit path.
---@param path? string
---@return boolean, string|nil err
function CfgFile:save(path)
  path=path or self._path
  if not path then return false,"no path" end
  local f,err=io.open(path,"w")
  if not f then return false,tostring(err) end

  local writeError=nil
  local function write(text)
    if writeError then return end
    local ok,reason=f:write(text)
    if not ok then writeError=tostring(reason or "write failed") end
  end
  local first=true
  for _,sec in ipairs(self._sections) do
    local keys=self._keyorder[sec] or {}
    if #keys==0 then goto continue end  -- skip empty sections

    if not first then write("\n") end
    first=false

    if sec~="" then write("["..sec.."]\n") end

    for _,key in ipairs(keys) do
      local m=self._meta[sec] and self._meta[sec][key]
      if m then
        if m.desc and m.desc~="" then
          write("#: "..m.display.." | "..m.desc.."\n")
        else
          write("#: "..m.display.."\n")
        end
      end
      write(key.."="..serializeValue(self._data[sec][key]).."\n")
    end
    ::continue::
  end
  -- OpenOS close may return nothing and does not propagate buffered flush errors.
  local flushed,flushErr=f:flush()
  local closed,closeErr=f:close()
  if writeError then return false,writeError end
  if not flushed then return false,tostring(flushErr or "flush failed") end
  if closed==false or closeErr~=nil then return false,tostring(closeErr or "close failed") end
  return true
end

---Load all *.cfg files in a directory.
---Returns a table keyed by filename without extension.
---@param dir string
---@return table<string,CfgFile>
function cfglib.loadDir(dir)
  local result={}
  if not fs.isDirectory(dir) then return result end
  local list=fs.list(dir)
  if not list then return result end
  for name in list do
    if name:match("%.conf$") then
      local key=name:match("^(.+)%.conf$")
      local cfg=cfglib.load(fs.concat(dir,name))
      if cfg then result[key]=cfg end
    end
  end
  return result
end

return cfglib
