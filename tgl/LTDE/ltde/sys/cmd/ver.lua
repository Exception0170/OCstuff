return {
  usage="ver",
  run=function(ctx,args)
    ctx.services.dialog("About LTDE","LTDE "..tostring(_G._ltde_version or "?").."\nTGL "..require("tgl").version,{"OK"})
  end
}
