local mnp=require("cmnp")
local ser=require("serialization")
local ftp=require("ftp")
local ip=require("ipv2")
local asp={}
asp.defaultPage="index"
asp.maxContentLength=7168 --7KB
asp.defaultHeaders={}
asp.version="0.2"
asp.util={}
asp.methods={
  GET=true,
  HEAD=true,
  POST=true
}

function asp.util.parse_query(url)
  local params = {}
  local query_string = url:match("?([^#]*)")
  if query_string then
    -- Split by '&' to get individual key-value pairs
    for param_pair in query_string:gmatch("([^&]*)") do
      -- Split each pair by '='
      local key, value = param_pair:match("([^=]*)=(.*)")
      if key then
        params[string.gsub(key,"+"," ")] = string.gsub(value or "","+"," ") -- Unescape key and value
      end
    end
  end
  return params
end

function asp.util.splitURL(path)
  if not string.find(path,"/") then
    path=path.."/"..asp.defaultPage
  elseif string.find(path,"/")==string.len(path) then
    path=path..asp.defaultPage
  end
  local hostname=string.sub(path,1,string.find(path,"/")-1)
  local pagepath=string.sub(path,string.find(path,"/")+1,string.len(path))
  local options={}
  if string.find(pagepath,"?") then
    pagepath=string.sub(pagepath,1,string.find(pagepath,'?'))
    options=asp.util.parse_query(pagepath)
  end
  return hostname,pagepath,options
end

--[[headers
content_length - size of body
content_type - none or text/tdf/tp file
location - for 301
options - ?query
]]
AspRequest={}
AspRequest.__index=AspRequest
function AspRequest:new(method,headers,body)
  if not asp.methods[method] then return nil,"Invalid method" end
  if type(headers)~="table" then return nil,"no header" end
  if type(body)~="string" then body="" end
  local obj=setmetatable({},AspRequest)
  obj.method=method
  obj.headers=headers
  obj.body=body
  return obj
end

function AspRequest:addHeaders(headers)
  for key,value in pairs(headers) do
    self.headers[key]=value
  end
end
--AspRequest:new("GET",{url="/home/index.tp"})

AspResponse={}
AspResponse.__index=AspResponse
function AspResponse:new(code,headers,body)
  if not tonumber(code) then return nil,"Invalid code" end
  if type(headers)~="table" then return nil,"no header" end
  if type(body)~="string" then body="" end
  local obj=setmetatable({},AspRequest)
  obj.code=code
  obj.headers=headers
  obj.body=body
  if not headers["content_length"] then obj.headers.content_length=string.len(body) end
  if not headers["content_type"] then obj.headers.content_type="text" end
  return obj
end

AspResponse.statusCodes={
  [100]="Continue", --for large files
  [101]="EndOfFile", --for large files(FTP)
  [200]="OK", --supports ftp
  [201]="OK,Large content", --OK but init big transfer
  [204]="No content",
  [301]="Moved Permanently",
  [400]="Bad request",
  [403]="Forbidden",
  [404]="Not found",
  [405]="Method not allowed",
  [408]="Request timeout",
  [500]="Internal server error"
}

function AspResponse:addHeader(key, value)
  self.headers[key:lower()] = value
end


--helper functions for quick responses
function AspResponse.ok(body, headers)
  return AspResponse:new(200, headers, body)
end

function AspResponse.simple(code,body,headers)
  if not body and not headers then
    body=code.." "..AspResponse.statusCodes[code]
    headers={}
  end
  if not headers then headers={} end
  return AspResponse:new(code, headers, body)
end

function AspResponse.redirect(url, status)
  local headers = {location=url}
  return AspResponse:new(status or 301,headers,"")
end

--connection
--large content
asp.large={}
function asp.large.split(body)
  local chunks={}
  local str_len=#body
  local pos=1
  while pos<=str_len do
    local end_pos=math.min(pos+asp.maxContentLength-1,str_len)
    table.insert(chunks,string.sub(body,pos,end_pos))
    pos=pos+asp.maxContentLength
  end
  return chunks
end
function asp.large.sendContent(address,response)
  local chunks=asp.large.split(response.body)
  asp.sendResponse(address,AspResponse:new(201,response.headers,chunks[1]))
  os.sleep(.05)
  for n,chunk in pairs(chunks) do
    if n==1 then --skip
    else
      local code=100
      if n==#chunks then code=101 end
      asp.sendResponse(address,AspResponse:new(code,{},chunk))
      os.sleep(.05)
    end
  end
  return true
end
function asp.large.getContent(to_ip,first)
  local res=first
  local last_code=201
  while last_code~=101 do
    local r=mnp.receive(to_ip,"asp",20)
    if not r then return res end
    res=res..r.body
    last_code=r.code
  end
  return res
end

function asp.sendResponse(address,response)
  if response.headers.content_length<=asp.maxContentLength then
    mnp.send(address,"asp",response)
    return true
  else
    return asp.large.sendContent(address,response)
  end
end

function asp.sendRequest(to_ip,request)
  mnp.send(to_ip,"asp",request)
  return true
end

function asp.getResponse(to_ip)
  local response=mnp.receive(to_ip,"asp")
  if not response then return nil end
  if response.code==201 then
    local body=asp.large.getContent(to_ip,response.body)
    response.body=body
  end
  return response
end

function asp.sendRequestResponse(to_ip,request)
  if asp.sendRequest(to_ip,request) then
    return asp.getResponse(to_ip)
  end
end


function asp.get(path,headers)
  --parse options
  local hostname,url,options= asp.util.splitURL(path)
  if not mnp.checkHostname(hostname) and not ip.isIPv2(path) then
    return false,"invalid hostname"
  end
  local state,to_ip=mnp.checkAvailability(hostname)
  if not state then return false,"unavailable" end
  local req=AspRequest:new("GET",{url=url})
  if not req then return nil end
  req:addHeaders({options=options})
  req:addHeaders(headers)
  req:addHeaders(asp.defaultHeaders)
  local response=asp.sendRequestResponse(to_ip,req)
  if not response then return false,"timeout" end
  if response.code==301 then
    return asp.get(response.headers.location,headers)
  else return response
  end
end
return asp