return {
  usage='notify [-t info|warn|error|dialog] [-T title] [-d seconds]\n       [-b "OK,Cancel"] [--] <message>',
  run=function(ctx,args)
    local kind,title,duration="info","Command Prompt",nil
    local buttons=nil
    local words={}
    local stop=false
    local i=1
    while i<=#args do
      local arg=args[i]
      if not stop and arg=="--" then stop=true
      elseif not stop and (arg=="-t" or arg=="--type" or arg=="-T" or arg=="--title"
      or arg=="-d" or arg=="--duration" or arg=="-b" or arg=="--buttons") then
        i=i+1
        local value=args[i]
        if not value then return 1,"Missing value for "..arg end
        if arg=="-t" or arg=="--type" then kind=value
        elseif arg=="-T" or arg=="--title" then title=value
        elseif arg=="-d" or arg=="--duration" then
          duration=tonumber(value)
          if not duration or duration<=0 or duration>=math.huge then return 1,"Duration must be a positive number." end
        else
          buttons={}
          for label in (value..","):gmatch("(.-),") do
            label=label:match("^%s*(.-)%s*$")
            if label=="" then return 1,"Button labels cannot be empty." end
            table.insert(buttons,label)
          end
        end
      elseif not stop and arg:sub(1,1)=="-" then return 1,"Unknown option: "..arg
      else table.insert(words,arg) end
      i=i+1
    end
    if kind~="info" and kind~="warn" and kind~="error" and kind~="dialog" then return 1,"Unknown notification type: "..kind end
    if #words==0 then return 1,ctx:getUsage("notify") end
    if buttons and kind~="dialog" then return 1,"Buttons require --type dialog." end
    if duration and (kind=="dialog" or kind=="error") then return 1,"Dialogs wait for a response; duration applies to info/warn." end
    local text=table.concat(words," ")
    if kind=="info" then ctx.services.notify(title,text,duration)
    elseif kind=="warn" then ctx.services.warn(title,text,duration)
    elseif kind=="error" then ctx.services.error(title,text)
    else
      local selected=ctx.services.dialog(title,text,buttons or {"OK"})
      if selected then ctx:print(selected) end
    end
  end
}
