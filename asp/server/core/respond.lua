--respond functions
local asp=require("asp")
local settings=dofile("settings.lua")
local respond={}
function respond.error(request,err)
  asp.sendResponse(request.ip,AspResponse.simple(500,err))
end
function respond.render(request,template,context)
  --readfile
  template="templates/"..template
  local file=io.open(template)
  local body=nil
  if file then
    body=file:read("*a")
    file:close()
  end
  if not body then
    if settings.debug then
      respond.error(request,"Couldn't load template: "..template)
    else
      respond.defaultHandler(request,500)
    end
    return
  end
  --add context
  local headers={
    content_type="tp",
    context=context
  }
  asp.sendResponse(request.ip,AspResponse:new(200,headers,body))
end
function respond.defaultHandler(request,code)
  asp.sendResponse(request.ip,AspResponse.simple(code))
end
function respond.redirect(request,address)

end
return respond