return {
  usage="quit-ltde",
  run=function(ctx,args)
    if #args~=0 then return 1,ctx:getUsage("quit-ltde") end
    require("event").push("ltde_shutdown_request")
  end
}
