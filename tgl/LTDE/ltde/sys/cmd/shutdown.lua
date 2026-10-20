return {
  usage="shutdown",
  run=function(ctx,args)
    if #args~=0 then return 1,ctx:getUsage("shutdown") end
    require("event").push("ltde_computer_poweroff")
  end
}
