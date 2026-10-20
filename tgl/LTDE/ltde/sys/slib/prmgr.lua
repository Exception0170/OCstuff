local prmgr={}

---Permission bit constants
prmgr.FULL_DISK_IO=0x1
prmgr.RUN_PROGRAMS=0x10
prmgr.COMPONENT_ACCESS=0x100
prmgr.NO_SANDBOX=0x1000
prmgr.ROOT_ACCESS=0x10000
prmgr.ALL_KNOWN=0x11111

---Validate bitmask has no unknown bits
---@param n integer
---@return boolean
function prmgr.check(n)
  if type(n)~="number" then return false end
  return (n&~prmgr.ALL_KNOWN)==0
end

---Query a named permission
---@param n integer
---@param name string
---@return boolean|nil
function prmgr.get(n,name)
  if name=="fullDiskIO" then return (n&prmgr.FULL_DISK_IO)~=0 end
  if name=="runPrograms" then return (n&prmgr.RUN_PROGRAMS)~=0 end
  if name=="componentAccess" then return (n&prmgr.COMPONENT_ACCESS)~=0 end
  if name=="noSandbox" then return (n&prmgr.NO_SANDBOX)~=0 end
  if name=="rootAccess" then return (n&prmgr.ROOT_ACCESS)~=0 end
  return nil
end

---Return bitmask with permission added
---@param n integer
---@param name string
---@return integer
function prmgr.grant(n,name)
  if name=="fullDiskIO" then return n|prmgr.FULL_DISK_IO end
  if name=="runPrograms" then return n|prmgr.RUN_PROGRAMS end
  if name=="componentAccess" then return n|prmgr.COMPONENT_ACCESS end
  if name=="noSandbox" then return n|prmgr.NO_SANDBOX end
  if name=="rootAccess" then return n|prmgr.ROOT_ACCESS end
  return n
end

---Return bitmask with permission removed
---@param n integer
---@param name string
---@return integer
function prmgr.revoke(n,name)
  if name=="fullDiskIO" then return n&~prmgr.FULL_DISK_IO end
  if name=="runPrograms" then return n&~prmgr.RUN_PROGRAMS end
  if name=="componentAccess" then return n&~prmgr.COMPONENT_ACCESS end
  if name=="noSandbox" then return n&~prmgr.NO_SANDBOX end
  if name=="rootAccess" then return n&~prmgr.ROOT_ACCESS end
  return n
end

return prmgr
