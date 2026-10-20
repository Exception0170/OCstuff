local init
do
  local invoke=component.invoke
  local function boot_invoke(address, method, ...)
    local result = table.pack(pcall(invoke, address, method, ...))
    if not result[1] then return nil, result[2] end
    return table.unpack(result, 2, result.n)
  end
  local eeprom = component.list("eeprom")()
  computer.getBootAddress = function() return boot_invoke(eeprom, "getData") end
  computer.setBootAddress = function(address) return boot_invoke(eeprom, "setData", address or "") end
  local status = function() end
  local visible = false
  do
    local screen = component.list("screen")()
    local gpu = component.list("gpu")()
    if gpu and screen and boot_invoke(gpu, "bind", screen) then
      local mw, mh = boot_invoke(gpu, "maxResolution")
      local w, h = math.min(mw or 80, 80), math.min(mh or 25, 25)
      --boot_invoke(gpu, "setResolution", w, h)
      boot_invoke(gpu, "setBackground", 0)
      boot_invoke(gpu, "setForeground", 0xCCCCCC)
      boot_invoke(gpu, "fill", 1, 1, w, h, " ")
      local function bgs(x, y, s, v) boot_invoke(gpu, "set", x, y, s, v) end
      local function line(y, s)
        s = tostring(s)
        while unicode.wlen(s)>w-6 do s=unicode.sub(s, 1, unicode.len(s)-1) end
        bgs(4, y, s..string.rep(" ", w-6-unicode.wlen(s)))
      end
      bgs(2, 2, "╔"..string.rep("═", w-4).."╗")
      bgs(2, h-1, "╚"..string.rep("═", w-4).."╝")
      bgs(2, 3, string.rep("║", h-4), true)
      bgs(w-1, 3, string.rep("║", h-4), true)
      boot_invoke(gpu, "setForeground", 0xFFFFFF)
      line(3, "Better Boot Info v1")
      boot_invoke(gpu, "setForeground", 0xCCCCCC)
      line(5, "Architecture : "..(computer.getArchitecture and computer.getArchitecture() or _VERSION))
      line(6, string.format("Memory       : %.0f KB installed / %.0f KB free", computer.totalMemory()/1024, computer.freeMemory()/1024))
      line(7, string.format("Video        : %dx%d text / max %dx%d", w, h, mw or w, mh or h))
      line(8, "System ID    : "..computer.address())
      line(10, "COMPONENT INVENTORY")
      local counts, names, total = {}, {}, 0
      for _, kind in component.list() do
        if not counts[kind] then names[#names+1]=kind counts[kind]=0 end
        counts[kind]=counts[kind]+1
        total=total+1
      end
      table.sort(names)
      local rows = h-14
      for i=1,math.min(#names, rows) do
        line(10+i, string.format("  %-22s %3d detected", names[i], counts[names[i]]))
      end
      line(h-3, total.." components / "..#names.." types"..(#names>rows and " (more types)" or ""))
      status = function(s) line(h-2, s) end
      status("Scanning boot devices...")
      visible = true
    end
  end
  local function tryLoadFrom(address)
    status("Boot device: "..address:sub(1, 12).." /init.lua")
    local handle, reason = boot_invoke(address, "open", "/init.lua")
    if not handle then return nil, reason end
    local buffer = {}
    repeat
      local data
      data, reason = boot_invoke(address, "read", handle, 4096)
      if data then buffer[#buffer+1]=data end
    until not data
    boot_invoke(address, "close", handle)
    if reason then return nil, reason end
    return load(table.concat(buffer), "=init")
  end
  local reason
  local preferred = computer.getBootAddress()
  if preferred and preferred~="" then init, reason=tryLoadFrom(preferred) end
  if not init then
    computer.setBootAddress()
    for address in component.list("filesystem") do
      if address~=preferred then
        init, reason=tryLoadFrom(address)
        if init then computer.setBootAddress(address) break end
      end
    end
  end
  if not init then
    status("BOOT FAILURE: no bootable medium found")
    error("no bootable medium found"..(reason and (": "..tostring(reason)) or ""), 0)
  end
  status("Starting system...")
  if visible then
    local untilTime=computer.uptime()+0.75
    repeat
      if computer.pullSignal(math.max(0,untilTime-computer.uptime()))=="key_down" then break end
    until computer.uptime()>=untilTime
  end
  computer.beep(1000, 0.1)
end
return init()
