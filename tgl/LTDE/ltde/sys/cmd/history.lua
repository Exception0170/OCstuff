return {
  usage="history",
  run=function(ctx,args)
    for i,line in ipairs(ctx.history or {}) do ctx:print(ctx:column(i,4,true).."  "..line) end
  end
}
