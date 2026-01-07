local gjson={}

local function esc(s)
  return s:gsub('[%z\1-\31\\"]',function(c)
    local r={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
    return r[c] or string.format("\\u%04x",c:byte())
  end)
end

local function is_array(t)
  local n=0
  for k,_ in pairs(t)do
    if type(k)~="number" or k<1 or k%1~=0 then return false end
    n=n+1
  end
  for i=1,n do if t[i]==nil then return false end end
  return true,n
end

local function encode(v,pretty,indent)
  indent=indent or""
  local t=type(v)
  if t=="nil"then return"null"
  elseif t=="number"then return tostring(v)
  elseif t=="boolean"then return v and"true"or"false"
  elseif t=="string"then return"\""..esc(v).."\""
  elseif t=="table"then
    local arr,n=is_array(v)
    local nextindent=pretty and indent.."  "or""

    if arr then
      local out={}
      for i=1,n do 
        out[i]=encode(v[i],pretty,nextindent) 
      end
      if pretty then
        return"["..(n>0 and"\n"..nextindent..table.concat(out,",\n"..nextindent).."\n"..indent or"").."]"
      else
        return"["..table.concat(out,",").."]"
      end
    else
      local out={}
      for k,val in pairs(v)do
        local key="\""..esc(tostring(k)).."\""
        local kv=key..":"..(pretty and" "or"")..encode(val,pretty,nextindent)
        out[#out+1]=kv
      end
      if pretty then
        return"{"..(#out>0 and"\n"..nextindent..table.concat(out,",\n"..nextindent).."\n"..indent or"").."}"
      else
        return"{"..table.concat(out,",").."}"
      end
    end
  end
  --Return nil for unsupported types instead of error
  return nil
end

---Serialize a Lua table to a JSON string
---@param t any The Lua table to serialize
---@param pretty boolean Whether to pretty-print the JSON (default: false)
---@return string|nil json The JSON string, or nil on error
---@return string|nil err Error message if serialization failed
function gjson.dumps(t,pretty)
  local result = encode(t,pretty)
  if not result then
    return nil, "unsupported data type in object"
  end
  return result
end

---Serialize a Lua table to JSON and write to a file
---@param obj table The Lua table to serialize
---@param filename string The path to the output file
---@param pretty boolean Whether to pretty-print the JSON (default: false)
---@return boolean|nil success True on success, nil on error
---@return string|nil err Error message if operation failed
function gjson.dumptofile(obj, filename, pretty)
  local json_str, err = gjson.dumps(obj, pretty)
  if not json_str then
    return nil, err
  end
    
  local file, err = io.open(filename, "w")
  if not file then
    return nil, "failed to open file for writing: " .. (err or "unknown error")
  end
    
  local success, write_err = file:write(json_str)
  file:close()
    
  if not success then
    return nil, "failed to write to file: " .. (write_err or "unknown error")
  end
    
  return true
end

local pos,str

-- Enhanced skip function to handle whitespace and comments
local function skip()
  while true do
    if pos > #str then return true end
    
    local c = str:sub(pos, pos)
    
    -- Skip whitespace
    if c == " " or c == "\n" or c == "\r" or c == "\t" then
      pos = pos + 1
    
    -- Handle single-line comments: //
    elseif c == "/" and str:sub(pos + 1, pos + 1) == "/" then
      pos = pos + 2  -- Skip "//"
      -- Skip until end of line or end of string
      while pos <= #str and str:sub(pos, pos) ~= "\n" do
        pos = pos + 1
      end
      -- Skip the newline character itself (if present)
      if pos <= #str and str:sub(pos, pos) == "\n" then
        pos = pos + 1
      end
    
    -- Handle multi-line comments: /* ... */
    elseif c == "/" and str:sub(pos + 1, pos + 1) == "*" then
      pos = pos + 2  -- Skip "/*"
      local comment_start = pos
      
      -- Search for closing */
      while pos <= #str - 1 do
        if str:sub(pos, pos + 1) == "*/" then
          pos = pos + 2  -- Skip "*/"
          break
        end
        pos = pos + 1
      end
      
      -- Check if we found the closing */
      if pos > #str and str:sub(#str - 1, #str) ~= "*/" then
        return false, "unterminated multi-line comment starting at position " .. comment_start
      end
    
    -- Not whitespace or comment, stop skipping
    else
      return true
    end
  end
end

local function parse_string()
  pos=pos+1
  local start=pos
  local out={}
  while true do
    if pos > #str then
      return nil, "unterminated string"
    end
    
    local c=str:sub(pos,pos)
    if c=="\""then
      out[#out+1]=str:sub(start,pos-1)
      pos=pos+1
      return table.concat(out)
    elseif c=="\\"then
      out[#out+1]=str:sub(start,pos-1)
      pos=pos+1
      
      if pos > #str then
        return nil, "unterminated escape sequence"
      end
      
      local e=str:sub(pos,pos)
      if e=="\""or e=="\\"or e=="/"then out[#out+1]=e
      elseif e=="b"then out[#out+1]="\b"
      elseif e=="f"then out[#out+1]="\f"
      elseif e=="n"then out[#out+1]="\n"
      elseif e=="r"then out[#out+1]="\r"
      elseif e=="t"then out[#out+1]="\t"
      elseif e=="u"then
        pos=pos+1
        if pos + 3 > #str then
          return nil, "incomplete unicode escape"
        end
        local hex=str:sub(pos,pos+3)
        if #hex~=4 then 
          return nil, "bad unicode escape"
        end
        out[#out+1]=string.char(tonumber(hex,16))
        pos=pos+3
      else 
        return nil, "bad escape character: \\"..e
      end
      pos=pos+1
      start=pos
    else
      pos=pos+1
    end
  end
end

local function parse_number()
  local s,e=str:find("^-?%d+%.?%d*[eE]?[+-]?%d*",pos)
  if not s then
    return nil, "bad number at position "..pos
  end
  local num=str:sub(s,e)
  pos=e+1
  local value = tonumber(num)
  if not value then
    return nil, "invalid number format: "..num
  end
  return value
end

local function parse_value()
  local success, err = skip()
  if not success then
    return nil, err
  end
  
  if pos > #str then
    return nil, "unexpected end of input"
  end

  local c=str:sub(pos,pos)
  if c=="\""then 
    return parse_string()
  elseif c=="{"then
    pos=pos+1
    local obj={}
    
    local success, err = skip()
    if not success then return nil, err end
    
    if str:sub(pos,pos)=="}"then
      pos=pos+1
      return obj
    end
    
    while true do
      local k, err = parse_string()
      if not k then return nil, err end
      
      local success, err = skip()
      if not success then return nil, err end
      
      if str:sub(pos,pos)~=":" then
        return nil, "expected ':' at position " .. pos .. " got '" .. str:sub(pos,pos) .. "'"
      end
      
      pos=pos+1
      local val, err = parse_value()
      if not val then return nil, err end
      
      obj[k]=val
      
      local success, err = skip()
      if not success then return nil, err end
      
      local d=str:sub(pos,pos)
      if d=="}"then
        pos=pos+1
        return obj
      end

      if d~="," then
        return nil, "expected ',' at position " .. pos .. " got '" .. d .. "'"
      end
      pos=pos+1
    end
  elseif c=="["then
    pos=pos+1
    local arr={}
    
    local success, err = skip()
    if not success then return nil, err end
    
    if str:sub(pos,pos)=="]"then
      pos=pos+1
      return arr
    end
    
    local i=1
    while true do
      local val, err = parse_value()
      if not val then return nil, err end
      
      arr[i]=val
      i=i+1
      
      local success, err = skip()
      if not success then return nil, err end
      
      local d=str:sub(pos,pos)
      if d=="]"then
        pos=pos+1
        return arr
      end
      
      if d~="," then
        return nil, "expected ',' at position " .. pos .. " got '" .. d .. "'"
      end
      
      pos=pos+1
    end
  elseif c=="t"and str:sub(pos,pos+3)=="true" then
    pos=pos+4
    return true
  elseif c=="f"and str:sub(pos,pos+4)=="false" then
    pos=pos+5
    return false
  elseif c=="n"and str:sub(pos,pos+3)=="null" then
    pos=pos+4
    return nil
  else
    return parse_number()
  end
end

---Parse a JSON string into a Lua table
---Supports both // single-line and /* */ multi-line comments
---@param s string The JSON string to parse
---@return any|nil data The parsed Lua table, or nil on error
---@return string|nil err Error message if parsing failed
function gjson.loads(s)
  if type(s) ~= "string" then
    return nil, "expected string input"
  end
  
  str=s
  pos=1
  local result, err = parse_value()
  if not result then
    return nil, err
  end
  
  local success, err = skip()
  if not success then
    return nil, err
  end
  
  if pos<=#str then
    return nil, "trailing characters at position " .. pos
  end
  
  return result
end

---Load and parse a JSON file into a Lua table
---Supports both // single-line and /* */ multi-line comments
---@param filename string The path to the JSON file
---@return table|nil data The parsed Lua table, or nil on error
---@return string|nil err Error message if loading failed
function gjson.loadfile(filename)
  local file, err = io.open(filename,"r")
  if not file then 
    return nil, "failed to open file: " .. (err or "unknown error")
  end
  local d, read_err = file:read("*a")
  file:close()
  if not d then
    return nil, "failed to read file: " .. (read_err or "unknown error")
  end
  return gjson.loads(d)
end

return gjson