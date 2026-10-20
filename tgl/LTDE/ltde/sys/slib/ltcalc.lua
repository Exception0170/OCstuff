local calc={}

function calc.format(value)
  return string.format("%.12g",value==0 and 0 or value)
end

---Evaluate arithmetic only; expressions never execute Lua code.
function calc.evaluate(text,extended,ans)
  if type(text)~="string" or #text>512 then return nil,"Expression is too long (maximum 512 characters)." end
  local ok,result=pcall(function()
    local pos,depth=1,0
    local expression,unary
    local function skip() pos=text:find("%S",pos) or #text+1 end
    local function take(char)
      skip()
      if text:sub(pos,pos)==char then pos=pos+1 return true end
      return false
    end
    local function finite(value)
      if value~=value or value==math.huge or value==-math.huge then error("Result is outside the real number range.",0) end
      return value
    end
    local functions={sqrt=math.sqrt,abs=math.abs,sin=math.sin,cos=math.cos,tan=math.tan,
      asin=math.asin,acos=math.acos,atan=math.atan,ln=math.log,
      log=function(x)return math.log(x)/math.log(10)end,exp=math.exp,floor=math.floor,ceil=math.ceil}
    local function primary()
      skip()
      if take("(") then
        local value=expression()
        if not take(")") then error("Expected closing parenthesis.",0) end
        return value
      end
      local rest=text:sub(pos)
      local number=rest:match("^%d+%.?%d*[eE][+-]?%d+") or rest:match("^%.%d+[eE][+-]?%d+")
        or rest:match("^%d+%.?%d*") or rest:match("^%.%d+")
      if number then pos=pos+#number return finite(tonumber(number)) end
      local name=rest:match("^[%a_]+")
      if name then
        pos=pos+#name name=name:lower()
        if name=="ans" then return finite(ans or 0) end
        if not extended then error("Enable extended mode for functions and constants.",0) end
        if name=="pi" then return math.pi end
        if name=="e" then return math.exp(1) end
        if not functions[name] then error("Unknown function: "..name,0) end
        if not take("(") then error("Expected '(' after "..name..".",0) end
        local value=expression()
        if not take(")") then error("Expected closing parenthesis.",0) end
        return finite(functions[name](value))
      end
      error("Expected a number at character "..pos..".",0)
    end
    local function power()
      local value=primary()
      if take("^") then
        if not extended then error("Enable extended mode for powers.",0) end
        value=finite(value^unary())
      end
      return value
    end
    unary=function()
      depth=depth+1
      if depth>64 then error("Expression is nested too deeply.",0) end
      local value
      if take("+") then value=unary()
      elseif take("-") then value=-unary()
      else value=power() end
      depth=depth-1
      return value
    end
    local function product()
      local value=unary()
      while true do
        if take("*") then value=finite(value*unary())
        elseif take("/") then
          local divisor=unary()
          if divisor==0 then error("Cannot divide by zero.",0) end
          value=finite(value/divisor)
        else break end
      end
      return value
    end
    expression=function()
      local value=product()
      while true do
        if take("+") then value=finite(value+product())
        elseif take("-") then value=finite(value-product())
        else break end
      end
      return value
    end
    local value=expression()
    skip()
    if pos<=#text then error("Unexpected input at character "..pos..".",0) end
    return finite(value)
  end)
  if not ok then return nil,tostring(result) end
  return result
end

return calc
