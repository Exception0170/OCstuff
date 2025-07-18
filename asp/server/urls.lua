local views=dofile("views.lua")
local urls={}
function urls.resolve(request)
  if not request.headers.url then
    --400
    return views.defaultHandler(request,400)
  end
  if not urls[request.headers.url] then
    return views.defaultHandler(request,404)
  end
  return urls[request.headers.url](request)
end
urls[""]=views.main
urls["/"]=views.main

return urls