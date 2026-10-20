local fs=require("filesystem")
local unicode=require("unicode")
local cfglib=assert(loadfile("/ltde/sys/cfglib.lua"))()
local ltsettings={}

function ltsettings.pages()
  local pages={}
  local names={}
  local iter=fs.list("/ltde/sys/settings")
  if iter then for name in iter do
    if name:match("^[%w_%-]+%.lua$") then names[#names+1]=name end
  end end
  table.sort(names)
  for _,name in ipairs(names) do
    local chunk,err=loadfile("/ltde/sys/settings/"..name,"t",{})
    if not chunk then return nil,err end
    local ok,page=pcall(chunk)
    if not ok then return nil,tostring(page) end
    if type(page)~="table" or type(page.fields)~="table" or type(page.config)~="string"
    or not page.config:match("^[%w_%-]+$") then return nil,"Invalid settings page: "..name end
    pages[#pages+1]=page
  end
  return pages
end

local Session={}
Session.__index=Session

function ltsettings.new()
  local pages,err=ltsettings.pages()
  if not pages then return nil,err end
  local self=setmetatable({pages=pages,values={},original={},configs={}},Session)
  for p,page in ipairs(pages) do
    local cfg=self.configs[page.config]
    if not cfg then
      cfg,err=cfglib.load("/ltde/cfg/"..page.config..".conf")
      if not cfg then return nil,err end
      self.configs[page.config]=cfg
    end
    self.values[p]={}
    self.original[p]={}
    for i,field in ipairs(page.fields) do
      local value=cfg:get(field.section,field.key,field.default)
      self.values[p][i]=value
      self.original[p][i]=value
      local meta=cfg:meta(field.section,field.key)
      field.label=meta and meta.display or field.label or field.key
      field.desc=meta and meta.desc or field.desc or ""
    end
  end
  return self
end

function Session:validate(p,i,value)
  local field=self.pages[p].fields[i]
  if field.kind=="number" then
    value=tonumber(value)
    if not value or value~=value or value<field.min or value>field.max
    or (field.integer and value~=math.floor(value)) then
      return nil,"Enter "..(field.integer and "a whole number" or "a number").." from "..field.min.." to "..field.max.."."
    end
  elseif field.kind=="boolean" then
    if type(value)~="boolean" then return nil,"Expected true or false." end
  else
    if type(value)~="string" or value:find("[%z\r\n]") then return nil,"Enter a single line of text." end
    if field.maxWidth and unicode.wlen(value)>field.maxWidth then return nil,"Use at most "..field.maxWidth.." character cell(s)." end
    if field.kind=="color" then
      local found=false
      for _,choice in ipairs(field.choices) do if value==choice then found=true end end
      if not found then return nil,"Choose a listed color." end
    elseif field.kind=="app" then
      if value:sub(1,1)~="/" or not fs.isDirectory(value) or not fs.exists(fs.concat(value,"manifest.lua"))
      or not fs.exists(fs.concat(value,"main.lua")) then return nil,"Enter an absolute application folder containing manifest.lua and main.lua." end
    end
  end
  return true,value
end

function Session:set(p,i,value)
  local ok,result=self:validate(p,i,value)
  if not ok then return nil,result end
  self.values[p][i]=result
  return true
end

function Session:dirty()
  for p,page in ipairs(self.pages) do for i in ipairs(page.fields) do
    if self.values[p][i]~=self.original[p][i] then return true end
  end end
  return false
end

-- Save through a sibling temporary file; retain the old file until replacement succeeds.
local function save(cfg,path)
  local tmp,backup
  repeat
    tmp=path..".tmp-"..tostring(math.random(1,1000000000))
    backup=tmp..".bak"
  until not fs.exists(tmp) and not fs.exists(backup)
  local ok,err=cfg:save(tmp)
  if not ok then fs.remove(tmp) return nil,err end
  ok,err=fs.rename(path,backup)
  if not ok then fs.remove(tmp) return nil,err end
  ok,err=fs.rename(tmp,path)
  if not ok then
    local restored=fs.rename(backup,path)
    fs.remove(tmp)
    return nil,tostring(err)..(restored and "" or "; original retained at "..backup)
  end
  fs.remove(backup)
  cfg._path=path
  return true
end

-- Returns success,error,applied fields. On partial failure, successful files stay applied.
function Session:apply()
  local pending={}
  for p,page in ipairs(self.pages) do
    for i,field in ipairs(page.fields) do
      if self.values[p][i]~=self.original[p][i] then
        local ok,err=self:validate(p,i,self.values[p][i])
        if not ok then return nil,field.label..": "..err,{} end
        pending[page.config]=true
      end
    end
    if page.config=="core" then
      local warning,critical
      for i,field in ipairs(page.fields) do
        if field.key=="memory_warn_kb" then warning=tonumber(self.values[p][i]) end
        if field.key=="memory_critical_kb" then critical=tonumber(self.values[p][i]) end
      end
      if warning and critical and warning<=critical then
        return nil,"Memory warning must be greater than the critical threshold.",{}
      end
    end
  end
  local configs={}
  -- Re-read before saving, preserve unrelated edits, refuse conflicting field changes.
  for name in pairs(pending) do
    local cfg,err=cfglib.load("/ltde/cfg/"..name..".conf")
    if not cfg then return nil,err,{} end
    configs[name]=cfg
  end
  for p,page in ipairs(self.pages) do for i,field in ipairs(page.fields) do
    if self.values[p][i]~=self.original[p][i] then
      local cfg=configs[page.config]
      local current=cfg:get(field.section,field.key,field.default)
      if current~=self.original[p][i] then return nil,field.label.." was changed elsewhere. Reopen Control Panel.",{} end
      cfg:set(field.section,field.key,self.values[p][i])
    end
  end end
  local core=configs.core
  if core then
    local warning=tonumber(core:get("system","memory_warn_kb",48))
    local critical=tonumber(core:get("system","memory_critical_kb",16))
    if not warning or not critical or warning<=critical then
      return nil,"Memory warning must be greater than the critical threshold.",{}
    end
  end
  local applied={}
  local names={}
  for name in pairs(configs) do names[#names+1]=name end
  table.sort(names)
  for _,name in ipairs(names) do
    local cfg=configs[name]
    local ok,err=save(cfg,"/ltde/cfg/"..name..".conf")
    if not ok then return nil,"Could not save "..name..": "..tostring(err),applied end
    self.configs[name]=cfg
    if _G.ltcfg then _G.ltcfg[name]=cfg end
    for p,page in ipairs(self.pages) do if page.config==name then
      for i,field in ipairs(page.fields) do
        if self.values[p][i]~=self.original[p][i] then
          applied[#applied+1]={field=field,value=self.values[p][i]}
          self.original[p][i]=self.values[p][i]
        end
      end
    end end
  end
  return true,nil,applied
end

return ltsettings
