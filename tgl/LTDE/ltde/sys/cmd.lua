local fs=require("filesystem")
local processor={}

-- Discover names without executing modules. Only lowercase filenames are commands.
local function discover()
  local commands={}
  local iter=fs.list("/ltde/sys/cmd")
  if iter then
    for file in iter do
      local name=file:match("^([a-z0-9_-]+)%.lua$")
      if name then commands[name]=true end
    end
  end
  return commands
end

local function loadCommand(name)
  local path="/ltde/sys/cmd/"..name..".lua"
  if fs.isLink and fs.isLink(path) then error("Command modules cannot be symbolic links.",0) end
  local chunk,err=loadfile(path)
  if not chunk then error(err,0) end
  local command=chunk()
  if type(command)=="function" then return {usage=name,run=command} end
  if type(command)~="table" or type(command.run)~="function" then error("Invalid command module: "..name,0) end
  return command
end

function processor.parse(line)
  local tokens={}
  local word={}
  local quoted=false
  local started=false
  local function finish()
    if started then table.insert(tokens,{text=table.concat(word)}) word={} started=false end
  end
  local i=1
  while i<=#line do
    local char=line:sub(i,i)
    if char=='"' then quoted=not quoted started=true
    elseif char:match("%s") and not quoted then finish()
    elseif char==">" and not quoted then
      finish()
      local op=">"
      if line:sub(i+1,i+1)==">" then op=">>" i=i+1 end
      table.insert(tokens,{text=op,operator=true})
    else table.insert(word,char) started=true end
    i=i+1
  end
  if quoted then return nil,"Unclosed double quote." end
  finish()
  local args={}
  local redirect=nil
  for n,token in ipairs(tokens) do
    if token.operator then
      if n~=#tokens-1 or #args==0 or tokens[n+1].operator or tokens[n+1].text=="" then
        return nil,"Use command > file or command >> file."
      end
      redirect={path=tokens[n+1].text,append=token.text==">>"}
      break
    end
    table.insert(args,token.text)
  end
  return args,nil,redirect
end

function processor.execute(line,session,services)
  -- Identity is resolved by LTDE, never accepted from the command or session.
  local caller=services.caller()
  if not caller or caller.mode~="system" or not services.permissions.get(caller.perms,"rootAccess") then
    return 1,"Command access requires a trusted system application."
  end
  if type(line)~="string" then return 1,"Command must be a string." end
  local args,err,redirect=processor.parse(line)
  if not args then return 1,err end
  if #args==0 then return 0,"" end
  local aliases=session.aliases or {}
  local seen={}
  while aliases[args[1]:lower()] do
    local name=args[1]:lower()
    if seen[name] then return 1,"Alias cycle: "..name end
    seen[name]=true
    local expanded,aliasErr,aliasRedirect=processor.parse(aliases[name])
    if not expanded or #expanded==0 or aliasRedirect then return 1,aliasErr or "Invalid alias: "..name end
    table.remove(args,1)
    for i=#expanded,1,-1 do table.insert(args,1,expanded[i]) end
  end
  local name=table.remove(args,1):lower()
  local commands=discover()
  if not commands[name] then return 1,"Unknown command: "..name end
  local output={}
  local ctx={cwd=session.cwd,commands=commands,aliases=aliases,history=session.history,services=services}
  function ctx:write(text)
    text=tostring(text or "")
    ctx.term:write(text)
  end
  function ctx:print(text) self:write(tostring(text or "").."\n") end
  function ctx:resolve(path)
    if path:sub(1,1)=="/" then return fs.canonical(path) end
    return fs.concat(self.cwd,path)
  end
  function ctx:column(text,width,right)
    local unicode=require("unicode")
    text=tostring(text or "")
    width=math.max(1,width)
    if unicode.wlen(text)>width then
      while unicode.wlen(text)>width-1 do text=unicode.sub(text,1,unicode.len(text)-1) end
      text=text.."~"
    end
    local padding=string.rep(" ",width-unicode.wlen(text))
    return right and padding..text or text..padding
  end
  ctx.term=session.term
  function ctx:getUsage(commandName)
    if not commands[commandName] then return nil end
    local ok,command=pcall(loadCommand,commandName)
    if not ok then return commandName.." (invalid module)" end
    return command.usage or commandName
  end
  local file=nil
  local prevWrite=session.term.onWrite
  session.term.onWrite=function(text)
    table.insert(output,text)
    if prevWrite then prevWrite(text) end
  end
  local ok,code,message=pcall(function()
    local command=loadCommand(name)
    for _,permission in ipairs(command.permissions or {}) do
      if not services.permissions.get(caller.perms,permission) then return 1,"Permission denied: "..permission end
    end
    ctx.redirectPath=redirect and ctx:resolve(redirect.path) or nil
    if command.validate then
      local valid,validationErr=command.validate(ctx,args)
      if valid==false then return 1,validationErr or "Invalid command arguments." end
    end
    if redirect then
      local openErr
      file,openErr=io.open(ctx.redirectPath,redirect.append and "a" or "w")
      if not file then return 1,openErr or "Cannot open output file." end
      local function write(text)
        local result,writeErr=file:write(tostring(text or ""))
        if not result then error(writeErr or "Output write failed.",0) end
      end
      ctx.term=setmetatable({write=function(_,text) write(text) end,
        print=function(_,text) write(tostring(text or "").."\n") end},
        {__index=function(_,key)
          local value=session.term[key]
          if type(value)=="function" then return function(_,...) return value(session.term,...) end end
          return value
        end})
    end
    return command.run(ctx,args)
  end)
  session.term.onWrite=prevWrite
  if file then
    local closed,result,closeErr=pcall(function() return file:close() end)
    if not closed or (not result and closeErr) then return 1,tostring(closeErr or result) end
  end
  if not ok then return 1,tostring(code) end
  session.cwd=ctx.cwd
  session.closed=ctx.closed or false
  if message then return code or 1,tostring(message) end
  return code or 0,table.concat(output)
end

return processor
