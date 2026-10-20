return {
  usage="ltwm windows | refresh | focus/minimize/restore/close <id>",
  run=function(ctx,args)
    local wm=require("tgl").sys.wm
    if not wm then return 1,"Window manager unavailable." end
    local sub=args[1] or "windows"
    if sub=="refresh" then
      if #args~=1 then return 1,ctx:getUsage("ltwm") end
      local tgl=require("tgl")
      wm:renderRegions({tgl.Size2:new(1,1,tgl.defaults.screenSizeX,tgl.defaults.screenSizeY)})
      return
    end
    if sub=="windows" then
      local idW,pidW=4,4
      for _,m in ipairs(wm.windows) do
        if not m.noTaskbar then
          idW=math.max(idW,#tostring(m.insertIdx))
          pidW=math.max(pidW,#tostring(m.pid or "-"))
        end
      end
      local titleW=math.max(8,(ctx.term.width or 60)-idW-pidW-13)
      local function row(id,pid,state,title)
        return ctx:column(id,idW).." "..ctx:column(pid,pidW).." "..ctx:column(state,10).." "..ctx:column(title,titleW)
      end
      ctx:print(row("ID","PID","STATE","TITLE"))
      for _,m in ipairs(wm.windows) do
        if not m.noTaskbar then
          ctx:print(row(m.insertIdx,m.pid or "-",m.minimized and "minimized" or (m==wm.activeWindow and "active" or "open"),
            m.frame.wmTitle or "Untitled"))
        end
      end
      return
    end
    local actions={focus="bringToFront",minimize="minimizeWindow",restore="restoreWindow",close="closeWindow"}
    if not actions[sub] or not tonumber(args[2]) then return 1,ctx:getUsage("ltwm") end
    for _,m in ipairs(wm.windows) do
      if not m.noTaskbar and m.insertIdx==tonumber(args[2]) then
        if sub=="focus" and m.minimized then wm:restoreWindow(m)
        else wm[actions[sub]](wm,m) end
        return
      end
    end
    return 1,"Window not found: "..args[2]
  end
}
