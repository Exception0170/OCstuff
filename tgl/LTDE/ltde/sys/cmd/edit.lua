return {
  usage="edit <file>",
  run=function(ctx,args)
    if #args~=1 then return 1,ctx:getUsage("edit") end
    local fs=require("filesystem")
    local path=ctx:resolve(args[1])
    if fs.isDirectory(path) then return 1,"Cannot edit a directory." end
    local editor="/ltde/apps/notepad.app"
    local cfg=_G.ltcfg and _G.ltcfg.core
    if cfg then editor=cfg:get("system","text_editor",editor) end
    if not fs.isDirectory(editor) then return 1,"Editor not found: "..tostring(editor) end
    if not fs.exists(path) then
      -- Append mode creates a new file without truncating one created meanwhile.
      local file,createErr=io.open(path,"a")
      if not file then return 1,"Cannot create file: "..tostring(createErr or path) end
      local ok,closeErr=file:close()
      if not ok and closeErr then return 1,"Cannot close file: "..tostring(closeErr) end
    end
    local prog,err=ctx.services.launch(editor,{path})
    if not prog then return 1,err or "Cannot launch editor." end
  end
}
