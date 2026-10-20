local fs=require("filesystem")
local unicode=require("unicode")
local complete={}

---Return complete input candidates and cursor positions. Never runs commands.
function complete.matches(line,cursor,session)
  local before=unicode.sub(line,1,cursor)
  local after=unicode.sub(line,cursor+1)
  -- Keep completion at token boundaries; editing inside a word stays untouched.
  if after~="" and not after:match("^%s") then return {} end
  local words={}
  local start=1
  local quoted=false
  local redirect=false
  for i=1,#before do
    local char=before:sub(i,i)
    if char=='"' then quoted=not quoted
    elseif not quoted and (char:match("%s") or char==">") then
      if i>start then table.insert(words,(before:sub(start,i-1):gsub('"',""))) end
      if char==">" then redirect=true end
      start=i+1
    end
  end
  local token=before:sub(start):gsub('"',"")
  local prefix=before:sub(1,start-1)
  local values={}
  local seen={}
  local function add(value)
    if value:find('["\r\n]') then return end
    if value:sub(1,#token)==token and not seen[value] then
      seen[value]=true table.insert(values,value)
    end
  end
  if #words==0 and not redirect then
    local iter=fs.list("/ltde/sys/cmd")
    if iter then
      for file in iter do
        local name=file:match("^([a-z0-9_-]+)%.lua$")
        if name then add(name) end
      end
    end
    for name in pairs(session.aliases or {}) do add(name) end
  else
    local command=words[1] or ""
    local visited={}
    while session.aliases and session.aliases[command] and not visited[command] do
      visited[command]=true
      command=session.aliases[command]:match("^%s*([^%s]+)") or command
    end
    if command=="run" and #words==1 and not redirect and not token:find("/",1,true) then
      local iter=fs.list("/ltde/apps")
      if iter then
        for file in iter do
          local name=file:gsub("/$","")
          if name:match("%.app$") then add(name) end
        end
      end
    end
    local parent=token:match("^(.*/)") or ""
    local path=parent:sub(1,1)=="/" and parent or fs.concat(session.cwd,parent)
    local iter=fs.list(path)
    if iter then
      for file in iter do
        local name=file:gsub("/$","")
        local dir=fs.isDirectory(fs.concat(path,name))
        if command~="cd" or redirect or dir then add(parent..name..(dir and "/" or "")) end
      end
    end
  end
  table.sort(values)
  local result={}
  for _,value in ipairs(values) do
    if value:find("[%s>]") then value='"'..value..'"' end
    local head=prefix..value
    if unicode.len(head..after)<=4096 then
      table.insert(result,{line=head..after,cursor=unicode.len(head)})
    end
  end
  return result
end

return complete
