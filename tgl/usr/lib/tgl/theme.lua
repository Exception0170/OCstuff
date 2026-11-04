local unicode=require("unicode")
return function(tgl)
--Literal colors in defaults.colors2 remain available; themes describe UI roles.
local defaults={
  colors={
    text=tgl.defaults.colors2.black,
    button=tgl.defaults.colors2.black,
    frame=tgl.defaults.colors2.black,
    input=tgl.defaults.colors2.white,
    scrollbar=tgl.Color2:new(tgl.defaults.colors16.lightgray,tgl.defaults.colors16.darkgray),
    progressbar=tgl.defaults.colors2.progressbar,
    focus=tgl.defaults.colors2.focus
  },
  chars={scrollbarTrack="▒",scrollbarThumb="█",checkboxChecked="🗹",checkboxUnchecked="🗷",
    radioSelected="●",radioUnselected="○"}
}
local function colorCopy(color)
  return tgl.Color2:new(color[1],color[2],color.is_palette)
end
local function newTheme()
  local theme={colors={},chars={}}
  for role,color in pairs(defaults.colors) do theme.colors[role]=colorCopy(color) end
  for role,char in pairs(defaults.chars) do theme.chars[role]=char end
  return theme
end
tgl.theme=newTheme()

--Constructors copy their defaults, so later theme edits leave existing UI alone.
function tgl.sys.themeColor(role)
  local colors=tgl.theme.colors or {}
  return colorCopy(colors[role] or defaults.colors[role])
end
function tgl.sys.themeChar(role)
  return (tgl.theme.chars or {})[role] or defaults.chars[role]
end

---Read a serialized theme without changing tgl.theme. Returns theme or nil,error.
---@param path? string defaults to /etc/tgl/theme.st
function tgl.sys.loadTheme(path)
  checkArg(1,path,"string","nil")
  local file,err=io.open(path or "/etc/tgl/theme.st","r")
  if not file then return nil,err end
  local ok,data,readErr=pcall(function()return file:read(16385)end)
  local closed,value,closeErr=pcall(function()return file:close()end)
  if not ok then return nil,tostring(data) end
  if not closed or value==false or closeErr then return nil,tostring(closeErr or value or "Close failed.") end
  if not data then return nil,readErr or "Empty theme file." end
  if #data>16384 then return nil,"Theme file exceeds 16 KiB." end
  local parsed,raw,reason=pcall(function()return require("serialization").unserialize(data)end)
  if not parsed then return nil,tostring(raw) end
  if type(raw)~="table" then return nil,reason or "Theme must be a table." end
  local theme=newTheme()
  for group,entries in pairs(raw) do
    if group~="colors" and group~="chars" then return nil,"Unknown theme section: "..tostring(group) end
    if type(entries)~="table" then return nil,"Theme "..group.." must be a table." end
    for role,entry in pairs(entries) do
      if defaults[group][role]==nil then return nil,"Unknown theme role: "..tostring(role) end
      if group=="colors" then
        if type(entry)~="table" then return nil,"Invalid theme color: "..role end
        for key in pairs(entry) do
          if key~=1 and key~=2 and key~="is_palette" and not (key=="type" and entry.type=="Color2") then
            return nil,"Invalid theme color field: "..role
          end
        end
        if entry.is_palette~=nil and type(entry.is_palette)~="boolean" then return nil,"Invalid palette flag: "..role end
        local limit=entry.is_palette and 16 or 0x1000000
        for i=1,2 do
          local color=entry[i]
          if type(color)~="number" or color~=color or color%1~=0 or color<0 or color>=limit then
            return nil,"Invalid theme color: "..role
          end
        end
        theme.colors[role]=colorCopy(entry)
      else
        local valid,length,width=pcall(function()return unicode.len(entry),unicode.wlen(entry)end)
        local limit=(role=="scrollbarTrack" or role=="scrollbarThumb") and 1 or 2
        if type(entry)~="string" or not valid or length~=1 or width<1 or width>limit then
          return nil,"Invalid theme character width: "..role
        end
        theme.chars[role]=entry
      end
    end
  end
  return theme
end
return tgl end
