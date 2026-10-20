-- Public command API. The core supplies private runtime services.
return function(processor,services)
  local lterm=loadfile("/ltde/sys/slib/lterm.lua")()
  local ltcmd={}
  local clipboard=""
  -- Internal LTDE clipboard; host clipboard paste still arrives as a signal.
  function ltcmd.setClipboard(text) clipboard=tostring(text or ""):sub(1,65536) end
  function ltcmd.getClipboard() return clipboard end
  function ltcmd.newSession(term)
    local session={cwd="/home",term=term or lterm:new(),closed=false,history={},aliases={ls="dir",clear="cls",rm="del",cat="type",cp="copy",mv="move"}}
    function session:execute(line)
      if type(line)=="string" and line:match("%S") and self.history[#self.history]~=line then
        table.insert(self.history,line)
        if #self.history>100 then table.remove(self.history,1) end
      end
      return processor.execute(line,self,services)
    end
    return session
  end
  -- One-shot execution captures output; use newSession() to retain cwd.
  function ltcmd.execute(line)
    return ltcmd.newSession():execute(line)
  end
  return ltcmd
end
