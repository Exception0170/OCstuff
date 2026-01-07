local glog={}
glog.systemlogname=""
glog.timeFormat="%H:%M-%d-%b-%Y"
glog.format="[%s][%s][%s]: %s"
glog.DEBUG=-1
glog.INFO=0
glog.WARN=1
glog.ERROR=2
glog.FATAL=3
function glog.getCritStr(crit)
  if not tonumber(crit) then crit=0 end
  if crit==1 then return "WARN"
  elseif crit==2 then return "ERROR"
  elseif crit==3 then return "FATAL"
  elseif crit==-1 then return "DEBUG"
  else return "INFO" end
end
function glog.getLogMsg(msg,mod,crit)
  if not mod then mod="unk" end
  return string.format(glog.format,os.date(glog.timeFormat),glog.getCritStr(crit),mod,msg)
end
function glog.newSysLog()
  glog.systemlogname="/gde/etc/log/system"..os.date("%H:%M-%d-%b-%Y")..".log"
  local file=io.open(glog.systemlogname,"a")
  if not file then return false end
  file:write("GDE System log\n"..os.date().."\n----\n")
  file:close()
  return true
end
---File logging
---@param filename string File name
---@param msg string Message
---@param mod? string Module name, default = unk
---@param crit? integer 0/nil=info, -1=debug, 1=warn, 2=error, 3=fatal
function glog.filelog(filename,msg,mod,crit)
  local file=io.open(filename,"a")
  if not file then return end
  file:write(glog.getLogMsg(msg,mod,crit),"\n")
  file:close()
end
---System logging to `glog.systemlogname`
---@param msg string Message
---@param mod? string Module name, default = unk
---@param crit? integer 0/nil=info, -1=debug, 1=warn, 2=error, 3=fatal
function glog.syslog(msg,mod,crit)
  if not mod then mod="sys" end
  glog.filelog(glog.systemlogname,msg,mod,crit)
end

---BaseLogger class
---@class glog.BaseLogger
---@field filename string
---@field timeformat string
---@field format string
---@field name string
---@field log function
glog.BaseLogger={}
glog.BaseLogger.__index=glog.BaseLogger
function glog.newBaseLogger()
  local obj=setmetatable({},glog.BaseLogger)
  obj.filename="/glog.txt"
  obj.timeformat=glog.timeFormat
  obj.format=glog.format
  obj.name="BaseLogger"
  return obj
end
---Log a message
---@param msg string Message
---@param crit integer 0/nil=info, -1=debug, 1=warn, 2=error, 3=fatal
---@return boolean
function glog.BaseLogger:log(msg,crit)
  local file=io.open(self.filename,"a")
  if not file then return false end
  file:write(string.format(self.format,os.date(self.timeformat),glog.getCritStr(crit),self.name,msg),"\n")
  file:close()
  return true
end
return glog