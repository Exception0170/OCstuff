local respond=dofile("core/respond.lua")
local views={}

function views.main(request)
  if request.method=="GET" then
    local context={}
    context['text1']="YAY!"
    return respond.render(request,"main.tp",context)
  end
end
function views.defaultHandler(request,code)
  return respond.defaultHandler(request,code)
end
return views