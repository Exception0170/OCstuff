return {
  usage='calc [--] <expression>\n    Example: calc "(2+3)*4"; calc "sqrt(81)+2^3"\n    Trig uses radians. Use run calc.app for the window.',
  run=function(ctx,args)
    local calc=assert(loadfile("/ltde/sys/slib/ltcalc.lua"))()
    local first=1
    if args[first]=="--" then first=first+1 end
    if first>#args then return 1,"Usage: calc <expression>" end
    local value,err=calc.evaluate(table.concat(args," ",first),true)
    if value==nil then return 1,err end
    ctx:print(calc.format(value))
  end
}
