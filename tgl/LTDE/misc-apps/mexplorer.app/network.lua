--ME queries, compact inventory snapshots, crafting handles and streamed exports.
local component=require("component")
local fs=require("filesystem")
local network={}
network.__index=network
local types={me_controller=true,me_interface=true,me_importbus=true,me_exportbus=true}
local powerMethods={stored="getStoredPower",maximum="getMaxStoredPower",input="getAvgPowerInjection",
  usage="getAvgPowerUsage",idle="getIdlePowerUsage"}
local function number(value)
  value=tonumber(value)
  return value and value==value and math.abs(value)<math.huge and value or 0
end
local function item(stack)
  if type(stack)~="table" then error("Invalid item data.",0) end
  local metadata=nil
  if stack.lore or stack.enchantments or stack.individual then
    metadata={lore=stack.lore,enchantments=stack.enchantments,individual=stack.individual}
  end
  local row={name=tostring(stack.name or "unknown"),label=tostring(stack.label or stack.name or "Unknown"),
    damage=number(stack.damage),quantity=number(stack.size),craftable=stack.isCraftable==true,nbt=stack.hasTag==true or stack.tag~=nil,
    tag=stack.tag,metadata=metadata}
  row.key=row.name.."\0"..row.damage.."\0"..row.label
  return row
end
function network:new()
  return setmetatable({requests={},cpus={},power={},errors={},times={},nextRequest=0},self)
end
function network.devices()
  local devices={}
  for address,kind in component.list() do
    if types[kind] then devices[#devices+1]={address=address,kind=kind} end
  end
  table.sort(devices,function(a,b)return a.address<b.address end)
  return devices
end
function network:connect(address)
  local ok,proxy=pcall(component.proxy,address)
  if not ok or not proxy then return nil,tostring(proxy or "Component unavailable.") end
  if self.address~=address then
    self.items=nil self.fluids=nil self.craftables=nil self.cpus={} self.power={}
    self.errors={} self.times={}
  end
  self.address=address self.proxy=proxy
  return true
end
function network:call(method,...)
  if not self.proxy then return nil,"No ME component connected." end
  local args={...}
  local ok,result,err=pcall(function() return self.proxy[method](table.unpack(args)) end)
  if not ok then return nil,tostring(result) end
  if result==nil or result==false then return nil,tostring(err or method.." failed.") end
  return result
end
function network:refresh(kind,progress)
  local methods={items="getItemsInNetwork",fluids="getFluidsInNetwork",craftables="getCraftables"}
  local method=methods[kind]
  if not method then return nil,"Unknown inventory type." end
  if progress then progress("Loading "..kind.."...",0,nil) end
  local raw,err=self:call(method)
  if type(raw)~="table" then
    err=err or "Invalid inventory response."
    self.errors[kind]=err return nil,err
  end
  local rows,keys={},{}
  local ok,why=pcall(function()
    for i,source in ipairs(raw) do
      local row
      if kind=="fluids" then
        row={name=tostring(source.name or "unknown"),label=tostring(source.label or source.name or "Unknown"),
          quantity=number(source.amount or source.size)}
        row.key=row.name.."\0"..row.label
      else
        row=item(kind=="craftables" and source.getItemStack() or source)
        if kind=="craftables" then row.recipe=source row.craftable=true end
      end
      local key=row.key
      keys[key]=(keys[key] or 0)+1
      row.key=key.."\0"..keys[key]
      rows[#rows+1]=row
      if i%32==0 or i==#raw then
        if progress then progress("Reading "..kind,i,#raw) end
        os.sleep(0)
      end
    end
  end)
  if not ok then self.errors[kind]=tostring(why) return nil,why end
  self[kind]=rows self.errors[kind]=nil self.times[kind]=os.date("%Y-%m-%d %H:%M:%S")
  return true
end
function network:poll()
  local errors={}
  for key,method in pairs(powerMethods) do
    local value,err=self:call(method)
    if type(value)=="number" then self.power[key]=number(value) self.errors[key]=nil
    else self.errors[key]=err or "Invalid power reading." errors[#errors+1]=method..": "..self.errors[key] end
  end
  local cpus,err=self:call("getCpus")
  if type(cpus)=="table" then
    local rows={}
    local ok,why=pcall(function()
      for i,cpu in ipairs(cpus) do
        local name=tostring(cpu.name or "")
        rows[i]={name=name,label=name~="" and name or "CPU "..i.." (unnamed)",
          storage=number(cpu.storage),coprocessors=number(cpu.coprocessors),busy=cpu.busy==true,key=tostring(i).."\0"..tostring(cpu.name)}
      end
    end)
    if ok then self.cpus=rows self.errors.cpus=nil self.times.cpus=os.date("%Y-%m-%d %H:%M:%S")
    else self.errors.cpus=tostring(why) errors[#errors+1]=self.errors.cpus end
  else self.errors.cpus=err or "Invalid CPU response." errors[#errors+1]=self.errors.cpus end
  self:pollRequests()
  return #errors==0,table.concat(errors,"\n")
end
function network:recipeFor(row)
  if row.recipe then return row end
  if row.nbt then return nil,"Choose this recipe in Crafting; tagged items may have multiple variants." end
  local recipes,err=self:call("getCraftables",{name=row.name,damage=row.damage,label=row.label})
  if type(recipes)~="table" then return nil,err or "Invalid recipe response." end
  if #recipes~=1 then return nil,"Choose a recipe in Crafting ("..#recipes.." matches)." end
  local ok,result=pcall(function() local entry=item(recipes[1].getItemStack()) entry.recipe=recipes[1] entry.craftable=true return entry end)
  if not ok then return nil,tostring(result) end
  return result
end
function network:request(row,amount,cpu)
  if not row or not row.recipe then return nil,"Select a craftable recipe." end
  if not amount or amount%1~=0 or amount<1 or amount>2147483647 then return nil,"Enter a quantity from 1 to 2147483647." end
  local retire=nil
  if #self.requests>=64 then
    for i,job in ipairs(self.requests) do
      if job.state=="Complete" or job.state=="Canceled" or job.state=="Failed" then retire=i break end
    end
    if not retire then return nil,"Already tracking 64 active requests." end
  end
  local ok,handle,err=pcall(row.recipe.request,amount,true,cpu)
  if not ok or not handle then return nil,tostring(ok and err or handle) end
  if retire then table.remove(self.requests,retire) end
  self.nextRequest=self.nextRequest+1
  local job={name=row.name,label=row.label,quantity=amount,cpu=cpu or "Automatic",address=self.address,
    state="Planning",handle=handle,key=tostring(self.nextRequest)}
  self.requests[#self.requests+1]=job
  return job
end
function network:pollRequests()
  for _,job in ipairs(self.requests) do
    if job.state=="Planning" or job.state=="Running" then
      local ok,done,reason=pcall(job.handle.isDone)
      if not ok then job.state="Failed" job.error=tostring(done)
      elseif reason=="computing" then job.state="Planning"
      elseif reason then job.state="Failed" job.error=tostring(reason)
      elseif done then job.state="Complete"
      else
        local success,canceled,why=pcall(job.handle.isCanceled)
        if not success or why then
          if why=="computing" then job.state="Planning"
          else job.state="Failed" job.error=tostring(success and why or canceled) end
        else job.state=canceled and "Canceled" or "Running" end
      end
    end
  end
end
function network:cancel(job)
  if not job or not job.handle then return nil,"Select a request." end
  local ok,result,err=pcall(function()return job.handle.cancel()end)
  if not ok or not result then return nil,tostring(ok and (err or "Cancellation unavailable.") or result) end
  self:pollRequests()
  return true
end

local fields={items={"label","name","damage","quantity","craftable","nbt"},
  fluids={"label","name","quantity"},craftables={"label","name","damage","quantity","nbt"},
  cpus={"name","storage","coprocessors","busy"},
  requests={"label","name","quantity","cpu","address","state","error"}}
local function csv(value)
  return '"'..tostring(value==nil and "" or value):gsub('"','""')..'"'
end
local function literal(value)
  if type(value)=="number" or type(value)=="boolean" then return tostring(value) end
  return string.format("%q",tostring(value or ""))
end
function network:export(path,scope,overwrite,progress)
  if scope~="snapshot" and not fields[scope] then return nil,"Unknown export type." end
  if scope=="snapshot" then
    for _,kind in ipairs({"items","fluids","craftables"}) do
      if not self[kind] then return nil,"Load "..kind.." before exporting a snapshot." end
    end
  elseif not self[scope] then return nil,"Load "..scope.." before exporting." end
  if fs.isDirectory(path) then return nil,"The destination is a directory." end
  if fs.exists(path) and not overwrite then return nil,"The destination already exists." end
  local tmp,backup
  repeat tmp=path..".mexplorer-"..math.random(1,1000000000) backup=tmp..".bak"
  until not fs.exists(tmp) and not fs.exists(backup)
  local file,err=io.open(tmp,"w")
  if not file then return nil,tostring(err) end
  local groups=scope=="snapshot" and {"items","fluids","craftables","cpus","requests"} or {scope}
  local total,done=0,0
  for _,kind in ipairs(groups) do total=total+#self[kind] end
  local function write(text)
    local result,why=file:write(text)
    if result==false or result==nil then error(why or "Write failed.",0) end
  end
  local captured=os.date("%Y-%m-%d %H:%M:%S")
  local ok,why=pcall(function()
    if progress then progress("Exporting "..scope,0,total) end
    if scope=="snapshot" then
      write("return {\nformat=\"mexplorer-1\",\ncaptured="..literal(captured)..",\naddress="..literal(self.address)..",\n")
      write("power={")
      for key in pairs(powerMethods) do write(key.."="..literal(self.power[key])..",") end
      write("},\ncapturedAt={")
      for key,value in pairs(self.times) do write(key.."="..literal(value)..",") end
      write("},\nerrors={")
      for key,value in pairs(self.errors) do write(key.."="..literal(value)..",") end
      write("},\n")
    end
    for _,kind in ipairs(groups) do
      if scope=="snapshot" then write(kind.."={\n")
      else write('"captured","address",'..table.concat(fields[kind],",").."\n") end
      for _,row in ipairs(self[kind]) do
        local values={}
        for i,key in ipairs(fields[kind]) do
          values[i]=scope=="snapshot" and key.."="..literal(row[key]) or csv(row[key])
        end
        if scope=="snapshot" then write("{"..table.concat(values,",").."},\n")
        else write(csv(self.times[kind] or captured)..","..csv(self.address)..","..table.concat(values,",").."\n") end
        done=done+1
        if done%16==0 or done==total then
          if progress then progress("Exporting "..kind,done,total) end
          os.sleep(0)
        end
      end
      if scope=="snapshot" then write("},\n") end
    end
    if scope=="snapshot" then write("}\n") end
    local closed,closeErr=file:close() file=nil
    if closed==false or closeErr then error(closeErr or "Close failed.",0) end
  end)
  if file then pcall(file.close,file) end
  if not ok then fs.remove(tmp) return nil,why end
  local replaced=false
  if fs.exists(path) then
    if not overwrite then fs.remove(tmp) return nil,"The destination already exists." end
    local moved,moveErr=fs.rename(path,backup)
    if not moved then fs.remove(tmp) return nil,tostring(moveErr) end
    replaced=true
  end
  local moved,moveErr=fs.rename(tmp,path)
  if not moved then
    local restored=not replaced or fs.rename(backup,path)
    fs.remove(tmp)
    return nil,tostring(moveErr)..(restored and "" or "; original saved at "..backup)
  end
  if replaced then fs.remove(backup) end
  return true,total
end
return network
