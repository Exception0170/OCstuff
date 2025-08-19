local Token = {}
Token.__index = Token

function Token.new(type, value)
  local self = setmetatable({}, Token)
  self.type = type
  self.value = value
  return self
end

function Token:__tostring()
  return string.format("Token(%s, %s)", self.type, tostring(self.value))
end

function lex(source)
  local tokens = {}
  local i = 1

  while i <= #source do
    local char = string.sub(source, i, i)

    if string.match(char, "%s") then -- Whitespace
      i = i + 1
    elseif string.sub(source, i, i + 1) == "//" then --comments
      -- Skip the rest of the line
      while i <= #source and string.sub(source, i, i) ~= "\n" do
          i = i + 1
      end
    elseif string.sub(source, i, i + 1) == "if" then
      table.insert(tokens, Token.new("T_IF", "if"))
      i = i + 2
    elseif string.sub(source, i, i + 2) == "for" then
      table.insert(tokens, Token.new("T_FOR", "for"))
      i = i + 3
    elseif string.sub(source, i, i + 5) == "elseif" then
      table.insert(tokens, Token.new("T_ELSEIF", "elseif"))
      i = i + 6
    elseif string.sub(source, i, i + 3) == "else" then
      table.insert(tokens, Token.new("T_ELSE", "else"))
      i = i + 4
    elseif string.sub(source, i, i + 3) == "true" then
      table.insert(tokens, Token.new("T_BOOLEAN", "true"))
      i = i + 4
    elseif string.sub(source, i, i + 4) == "false" then
      table.insert(tokens, Token.new("T_BOOLEAN", "false"))
      i = i + 5
    elseif string.sub(source, i, i + 3) == "null" then
      table.insert(tokens, Token.new("T_NULL", "null"))
      i = i + 4
    elseif string.sub(source, i, i + 7) == "function" then
      table.insert(tokens, Token.new("T_FUNCTION", "function"))
      i = i + 8
    elseif string.sub(source, i, i + 5) == "return" then
      table.insert(tokens, Token.new("T_RETURN", "return"))
      i = i + 6
    elseif string.sub(source,i,i+4)=="while" then
      table.insert(tokens, Token.new("T_WHILE", "while"))
      i=i+5
    elseif string.sub(source,i,i+4)=="break" then
      table.insert(tokens, Token.new("T_BREAK", "break"))
      i=i+5
    elseif char == "{" then
      table.insert(tokens, Token.new("T_LBRACE", "{"))
      i = i + 1
    elseif char == "}" then
      table.insert(tokens, Token.new("T_RBRACE", "}"))
      i = i + 1
    elseif char == "(" then
      table.insert(tokens, Token.new("T_LPAREN", "("))
      i = i + 1
    elseif char == ")" then
      table.insert(tokens, Token.new("T_RPAREN", ")"))
      i = i + 1
     elseif char == "[" then
      table.insert(tokens, Token.new("T_LSQUARE", "["))
      i = i + 1
    elseif char == "]" then
      table.insert(tokens, Token.new("T_RSQUARE", "]"))
      i = i + 1
    elseif char == "=" then
      if string.sub(source, i + 1, i + 1) == "=" then
        table.insert(tokens, Token.new("T_OPERATOR", "=="))
        i = i + 2
      else
        table.insert(tokens, Token.new("T_OPERATOR", "="))
        i = i + 1
      end
    elseif char == ">" then
      table.insert(tokens, Token.new("T_OPERATOR", ">"))
      i = i + 1
    elseif char == "<" then
      table.insert(tokens, Token.new("T_OPERATOR", "<"))
      i = i + 1
    elseif string.sub(source, i, i + 1) == ">=" then
      table.insert(tokens, Token.new("T_OPERATOR", ">="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "<=" then
      table.insert(tokens, Token.new("T_OPERATOR", "<="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "!=" then
      table.insert(tokens, Token.new("T_OPERATOR", "!="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "//" then
      table.insert(tokens, Token.new("T_OPERATOR", "//"))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "+=" then
      table.insert(tokens, Token.new("T_OPERATOR", "+="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "-=" then
      table.insert(tokens, Token.new("T_OPERATOR", "-="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "/=" then
      table.insert(tokens, Token.new("T_OPERATOR", "/="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "*=" then
      table.insert(tokens, Token.new("T_OPERATOR", "*="))
      i = i + 2
    elseif string.sub(source, i, i + 1) == "%=" then
      table.insert(tokens, Token.new("T_OPERATOR", "%="))
      i = i + 2
    elseif char == "%" then
      table.insert(tokens, Token.new("T_OPERATOR", "%"))
      i = i + 1
    elseif char == "+" then
      table.insert(tokens, Token.new("T_OPERATOR", "+"))
      i = i + 1
    elseif char == "-" then
      table.insert(tokens, Token.new("T_OPERATOR", "-"))
      i = i + 1
    elseif char == "*" then
      table.insert(tokens, Token.new("T_OPERATOR", "*"))
      i = i + 1
    elseif char == "/" then
      table.insert(tokens, Token.new("T_OPERATOR", "/"))
      i = i + 1
    elseif char == ";" then
      table.insert(tokens, Token.new("T_SEMICOLON", ";"))
      i = i + 1
    elseif char == "," then
      table.insert(tokens, Token.new("T_COMMA", ","))
      i = i + 1
    elseif char == "." then
      table.insert(tokens, Token.new("T_DOT", "."))
      i = i + 1
    elseif string.match(char, "%a") then -- Identifiers
      local identifier = char
      local j = i + 1
      while j <= #source and string.match(string.sub(source, j, j), "%w") do
        identifier = identifier .. string.sub(source, j, j)
        j = j + 1
      end
      table.insert(tokens, Token.new("T_IDENTIFIER", identifier))
      i = j
    elseif string.match(char, "%d") then -- Numbers
      local number = char
      local j = i + 1
      while j <= #source and string.match(string.sub(source, j, j), "%d") do
        number = number .. string.sub(source, j, j)
        j = j + 1
      end
      table.insert(tokens, Token.new("T_NUMBER", number))
      i = j
    elseif char == '"' or char == "'" then -- Strings
      local string_value = ""
      local j = i + 1
      local quote_char = char
      while j <= #source and string.sub(source, j, j) ~= quote_char do
        string_value = string_value .. string.sub(source, j, j)
        j = j + 1
      end
      if j <= #source and string.sub(source, j, j) == quote_char then
        table.insert(tokens, Token.new("T_STRING", string_value))
        i = j + 1
      else
        error("Unterminated string")
      end
    else
      error("Unexpected character: " .. char)
    end
  end

  table.insert(tokens, Token.new("T_EOF", nil))
  return tokens
end

-- AST Node Definitions (same as before)
local AST = {}

AST.Program = function(statements)
    return { type = "Program", statements = statements }
end

AST.IfStatement = function(condition, thenBlock, elseifBlocks, elseBlock)
    return { type = "IfStatement", condition = condition, thenBlock = thenBlock, elseifBlocks = elseifBlocks, elseBlock = elseBlock }
end

AST.Block = function(statements)
    return { type = "Block", statements = statements }
end

AST.Assignment = function(target, value)
    return { type = "Assignment", target = target, value = value }
end

AST.BinaryExpression = function(operator, left, right)
    return { type = "BinaryExpression", operator = operator, left = left, right = right }
end

AST.Identifier = function(name)
    return { type = "Identifier", name = name }
end

AST.NumberLiteral = function(value)
    return { type = "NumberLiteral", value = value }
end

AST.StringLiteral = function(value)
    return { type = "StringLiteral", value = value }
end

AST.BooleanLiteral = function(value)
    return { type = "BooleanLiteral", value = value }
end

AST.TableLiteral = function(fields)
    return { type = "TableLiteral", fields = fields }
end

AST.TableAccess = function(base, index)
    return {type = "TableAccess", base = base, index = index}
end

AST.NullLiteral = function()
  return { type = "NullLiteral"}
end

AST.FunctionDefinition = function(name, parameters, body)
  return { type = "FunctionDefinition", name = name, parameters = parameters, body = body }
end

AST.FunctionCall = function(name, arguments)
  return { type = "FunctionCall", name = name, arguments = arguments }
end

AST.ReturnStatement = function(expression)
  return {type="ReturnStatement", expression = expression}
end

AST.WhileLoop = function(condition, body)
  return { type = "WhileLoop", condition = condition, body = body }
end

AST.Break = function()
  return {type="Break"}
end

AST.ForLoop = function (variable,start,endValue,step,body)
  return {
    type = "ForLoop",
    variable = variable,
    start = start,
    endValue = endValue,
    step = step,
    body = body
}
end
-- Parser
function parse(tokens)
  local i = 1
  function peek()
    return tokens[i]
  end

  function next_token()
      local token = tokens[i]
      i = i + 1
      return token
  end

  function match(expectedType)
      local token = peek()
      if not token then
          return false
      end

      return token.type == expectedType
  end

  function consume(expectedType, errorMessage)
      if not match(expectedType) then
        error("Expected " .. expectedType .. ", got " .. (peek() and peek().type or "EOF") .. (errorMessage and (": " .. errorMessage) or ""))
      end
      return next_token()
  end
  function parse_table()

      local fields = {}
      local implicitKey = 1

      while not match("T_RBRACE") do
          if match("T_IDENTIFIER") and  tokens[i+1] and tokens[i+1].type=="T_OPERATOR" and tokens[i+1].value == "=" then
              -- Key-value pair
              local key = consume("T_IDENTIFIER", "Expected key identifier").value
              consume("T_OPERATOR", "Expected '=' after key")
              local value = parse_expression()
              fields[key] = value --CHANGED LINE
          else
              -- Array-like value
              local value = parse_expression()
              fields[implicitKey] = value --CHANGED LINE
              implicitKey = implicitKey + 1
          end

          if match("T_COMMA") then
              consume("T_COMMA", "Expected comma between table entries")
          elseif not match("T_RBRACE") then
              error("Expected comma or '}' after table entry")
          end
      end

      consume("T_RBRACE", "Expected '}' to end table")
      return AST.TableLiteral(fields)
  end

function parse_primary()
    local token = next_token()
    if token.type == "T_NUMBER" then
        return AST.NumberLiteral(tonumber(token.value))
    elseif token.type == "T_STRING" then
        return AST.StringLiteral(token.value)
    elseif token.type == "T_IDENTIFIER" then
        local identifier = AST.Identifier(token.value)
        if match("T_LSQUARE") then
            next_token() -- Consume the '['
            local index = parse_expression()
            consume("T_RSQUARE", "Expected ']' to close table index")
            return AST.TableAccess(identifier, index)
        -- elseif match("T_LPAREN") then
        --   return parse_function_call(identifier)
        else
            return identifier
        end
    elseif token.type == "T_BOOLEAN" then
        return AST.BooleanLiteral(token.value == "true")
    elseif token.type == "T_LPAREN" then
        local expr = parse_expression()
        consume("T_RPAREN", "Expected ')'")
        return expr
    elseif token.type == "T_LBRACE" then
        return parse_table()
    elseif token.type == "T_NULL" then
      return AST.NullLiteral()
    elseif token.type == "T_FUNCTION" then
      return parse_function_definition()
    else
        error("Unexpected token in expression: " .. (token and token.type or "EOF"))
    end
  end

  function parse_block()
      consume("T_LBRACE", "Expected '{' at start of block")
      local statements = {}

      while not match("T_RBRACE") and not match("T_EOF") do
          local stmt = parse_statement()
          if stmt then
              table.insert(statements, stmt)
          end
      end

      consume("T_RBRACE", "Expected '}' at end of block")
      return AST.Block(statements)
  end

  function parse_if_statement()
      consume("T_IF", "Expected 'if'")
      consume("T_LPAREN", "Expected '(' after 'if'")
      local condition = parse_expression()
      consume("T_RPAREN", "Expected ')' after if condition")
      local thenBlock = parse_block()

      local elseifBlocks = {}
      while match("T_ELSEIF") do
          consume("T_ELSEIF", "Expected 'elseif'")
          consume("T_LPAREN", "Expected '(' after 'elseif'")
          local elseifCondition = parse_expression()
          consume("T_RPAREN", "Expected ')' after elseif condition")
          local elseifBlock = parse_block()
          table.insert(elseifBlocks, {condition = elseifCondition, block = elseifBlock})
      end

      local elseBlock = nil
      if match("T_ELSE") then
          consume("T_ELSE", "Expected 'else'")
          elseBlock = parse_block()
      end

      return AST.IfStatement(condition, thenBlock, elseifBlocks, elseBlock)
  end

  function parse_expression()
    local left = parse_primary()
    while (match("T_OPERATOR") and peek().value~="=" and peek().value~="+=" and
    peek().value~='-=' and peek().value~='/=' and peek().value~='*=' and peek().value~='%=')
    or match("T_DOT") or match("T_LSQUARE") or match("T_LPAREN") do
        if match("T_OPERATOR") then
          local operator = next_token().value
          local right = parse_primary()
          left = AST.BinaryExpression(operator, left, right)
        elseif match("T_LSQUARE") then
          next_token() -- Consume the '['
          local index = parse_expression()
          consume("T_RSQUARE", "Expected ']' to close table index")
          left =  AST.TableAccess(left, index)
        elseif match("T_DOT") then
          print("dot!")
          consume("T_DOT", "Expected '.'")
          local property = consume("T_IDENTIFIER", "Expected identifier after '.'").value
          left = AST.TableAccess(left, AST.StringLiteral(property)) --Creates inline object
        elseif match("T_LPAREN") then
          print("parsing function?",left.type)
          left=parse_function_call(left)
        end
    end
    return left
  end

  function parse_assignment_statement()
    local target = parse_expression()
    print(target.type)
    local op=consume("T_OPERATOR","Expected '=' in assignment!")
    local value = parse_expression()
    if op.value=="=" then
      return AST.Assignment(target, value)
    elseif op.value=="+=" or op.value=="-=" or op.value=="/=" or op.value=="*=" or op.value=="%=" then
      return AST.Assignment(target,AST.BinaryExpression(string.sub(op.value,1,1),target,value))
    else
      --error("Invalid operator for assignment: "..op.value)
      --do nothing!
    end
  end
  -- function parse_function_definition()
  --   consume("T_FUNCTION", "Expected 'function' keyword")
  --   local name = consume("T_IDENTIFIER", "Expected function name").value
  --   consume("T_LPAREN", "Expected '(' after function name")
  --   local parameters = {}
  --   if not match("T_RPAREN") then
  --       repeat
  --           local paramName = consume("T_IDENTIFIER", "Expected parameter name").value
  --           table.insert(parameters, paramName)
  --           if match("T_COMMA") then
  --               consume("T_COMMA", "Expected comma between parameters")
  --           end
  --       until not match("T_IDENTIFIER")
  --   end
  --   consume("T_RPAREN", "Expected ')' after parameters")
  --   local body = parse_block()
  --   return AST.FunctionDefinition(name, parameters, body)
  -- end
  function parse_function_definition()
    consume("T_FUNCTION", "Expected 'function' keyword")
    local name = nil
    if match("T_IDENTIFIER") then
        local base = consume("T_IDENTIFIER", "Expected function name or table name").value
        if match("T_DOT") then
            consume("T_DOT", "Expected '.' after table name")
            local property = consume("T_IDENTIFIER", "Expected function name").value
            -- Create a TableAccess node
            name = AST.TableAccess({type = "Identifier", name = base}, {type = "StringLiteral", value = property})
        else
            -- If no dot, it's a regular function
            name = AST.Identifier(base)
        end
    else
        error("Expected function name or table.function name")
    end

    consume("T_LPAREN", "Expected '(' after function name")
    local parameters = {}
    if not match("T_RPAREN") then
        repeat
            local paramName = consume("T_IDENTIFIER", "Expected parameter name").value
            table.insert(parameters, paramName)
            if match("T_COMMA") then
                consume("T_COMMA", "Expected comma between parameters")
            end
        until not match("T_IDENTIFIER")
    end
    consume("T_RPAREN", "Expected ')' after parameters")
    local body = parse_block()

    return AST.FunctionDefinition(name, parameters, body)
  end
  function parse_statement()
    local token = peek()
    if not token then return nil end

    if token.type == "T_IF" then
      return parse_if_statement()
    elseif token.type == "T_IDENTIFIER" or token.type == "T_LSQUARE" then
      -- local j=i+1
      -- while tokens[j].type~="T_OPERATOR" and tokens[j].type~="T_LPAREN" do j=j+1 print(j,token[j].type)end
      -- if tokens[j].type=="T_LPAREN" then
      --   parse_function_call()
      if tokens[i+1].type=="T_LPAREN" then --fix?
        local ident=parse_primary()
        return parse_function_call(ident)
      else
        return parse_assignment_statement()
      end
    elseif token.type == "T_WHILE" then
      return parse_while_loop()
    elseif token.type == "T_BREAK" then
      next_token()
      return AST.Break()
    elseif token.type == "T_FOR" then
      return parse_for_loop()
    elseif token.type == "T_SEMICOLON" then
      next_token()
      return nil
    elseif token.type == "T_FUNCTION" then
      return parse_function_definition()
    elseif token.type == "T_RETURN" then
      return parse_return_statement()
    else
      error("Unexpected token at start of statement: " .. token.type)
    end
  end
  function parse_function_call(name)
    consume("T_LPAREN", "Expected '(' after function name")
    local arguments = {}
    if not match("T_RPAREN") then
        repeat
            local arg = parse_expression()
            table.insert(arguments, arg)
            if match("T_COMMA") then
                consume("T_COMMA", "Expected comma between arguments")
            end
        until not (match("T_IDENTIFIER") or match("T_NUMBER") or  match("T_STRING") or match("T_BOOLEAN") )
    end
    consume("T_RPAREN", "Expected ')' after arguments")
    return AST.FunctionCall(name.name, arguments)
  end

  function parse_return_statement()
    consume("T_RETURN", "Expected 'return'")
    local expression = parse_expression()
    -- consume("T_SEMICOLON", "Expected ';' after return statement")
    return AST.ReturnStatement(expression)
  end
  function parse_while_loop()
    consume("T_WHILE", "Expected 'while' keyword")
    consume("T_LPAREN", "Expected '(' after 'while'")
    local condition = parse_expression()
    consume("T_RPAREN", "Expected ')' after while condition")
    local body = parse_block()
    return AST.WhileLoop(condition, body)
  end
  function parse_for_loop()
    consume("T_FOR", "Expected 'for' keyword")
    consume("T_LPAREN", "Expected '(' after 'for'")
    local variable = consume("T_IDENTIFIER", "Expected loop variable name").value
    consume("T_OPERATOR", "Expected '=' after loop variable")
    local start = parse_expression()
    consume("T_COMMA", "Expected ',' after start value")
    local endValue = parse_expression()
    local step = nil
    if  match("T_COMMA") then
      consume("T_COMMA", "Expected ',' after end value")
      step = parse_expression()
    else
      step = AST.NumberLiteral(1)
    end
    consume("T_RPAREN", "Expected ')' after for conditions")
    local body = parse_block()
    return AST.ForLoop(variable, start, endValue, step, body)
  end
  function parse_program()
      local statements = {}
      if match("T_LBRACE") then
          -- Parse the entire program as a single block
          local block = parse_block()
          table.insert(statements, block)
      else
          -- Parse a sequence of statements
          while not match("T_EOF") do
              local stmt = parse_statement()
              if stmt then
                  table.insert(statements, stmt)
              end
          end
      end
      return AST.Program(statements)
  end

  return parse_program()
end

function print_ast(node, indent)
    indent = indent or ""
    if not node then return end
    print(indent .. "Type: " .. node.type)
    for k, v in pairs(node) do
        if k == "elseifBlocks" and type(v) == "table" then
            print(indent .. "  elseifBlocks:")
            for i, elseifBlock in ipairs(v) do
                print(indent .. "    [" .. i .. "]:")
                print(indent .. "      Condition:")
                print_ast(elseifBlock.condition, indent .. "        ")
                print(indent .. "      Block:")
                print_ast(elseifBlock.block, indent .. "        ")
            end
             elseif k == "fields" and type(v) == "table" then
                print(indent .. "  fields:")
                for key, value in pairs(v) do
                    print(indent .. "    " .. tostring(key) .. ":")
                    print_ast(value, indent .. "      ")
                end
            elseif type(v) == "table" and v.type then
                print(indent .. "  " .. k .. ":")
                print_ast(v, indent .. "    ")
            elseif type(v) == "table" then
                print(indent .. "  " .. k .. ":")
                for i, item in ipairs(v) do
                    if type(item) == "table" and item.type then
                        print(indent .. "    [" .. i .. "]:")
                        print_ast(item, indent .. "      ")
                    else
                        print(indent .. "    [" .. i .. "]: " .. tostring(item))
                    end
                end
            else
                print(indent .. "  " .. k .. ": " .. tostring(v))
            end
        end
end

function generate_env()
  local env={}
  --setup build-in functions
  env["print"]=function(a)
    print(table.unpack(a))
  end
  env["input"]=function()
    return io.read()
  end
  return env
end

function create_interpreter()
  local env = generate_env() -- the environment
  local function evaluate(node)
    if node.type=="Program" or node.type=="Block" then
      for _,statement in pairs(node.statements) do
        if evaluate(statement)=="Break" then
          return "Break"
        end
      end
    elseif node.type == "NumberLiteral" then
      return node.value
    elseif node.type == "BooleanLiteral" then
      return node.value == true
    elseif node.type == "StringLiteral" then
      return node.value
    elseif node.type == "NullLiteral" then
      return nil
    elseif node.type == "TableLiteral" then
      local table={}
      for key,elem in pairs(node.fields) do
        table[key]=evaluate(elem)
      end
      return table
    elseif node.type == "FunctionDefinition" then
      if node.name.type=="Identifier" then
        env[node.name.name]=node --store function
        return nil
      elseif node.name.type=="TableAccess" then
        --eval?
        env[node.name.base.name][node.name.index.value]=node
      end
    elseif node.type == "FunctionCall" then
      local func=env[node.name]
      if type(func)=="function" then --system call
        local args = {}
        for _, argNode in ipairs(node.arguments) do
          table.insert(args, evaluate(argNode))
        end
        local success,result=pcall(func,args)
        if not success then
          error("System call fail: "..result)
        end
        return result
      end
      if not func or func.type ~= "FunctionDefinition" then
        error("Attempt to call undefined function '" .. tostring(node.name) .. "'")
      end
      local args = {}
      for _, argNode in ipairs(node.arguments) do
          table.insert(args, evaluate(argNode))
      end
      local oldEnv=env
      for i,paramName in ipairs(func.parameters) do
        env[paramName]=args[i] or nil
      end
      local result=nil
      for _, statement in ipairs(func.body.statements) do
        local stmtResult = evaluate(statement)
        if statement.type=="ReturnStatement" then
          result=stmtResult
          break
        end
      end
      env=oldEnv
      return result
    elseif node.type == "BinaryExpression" then
      local left = evaluate(node.left)
      local right = evaluate(node.right)
      if node.operator == "+" then
        return left + right--str
      elseif node.operator == "-" then
        return left - right
      elseif node.operator == "*" then
        return left * right
      elseif node.operator == "/" then
        return left / right
      elseif node.operator == "==" then
        return left == right
      elseif node.operator == ">" then
        return left > right
      elseif node.operator == "<" then
        return left < right
      elseif node.operator == ">=" then
        return left >= right
      elseif node.operator ==" <=" then
        return left <= right
      elseif node.operator == "!=" then
        return left ~= right
      elseif node.operator == "//" then
        return math.floor(left/right)
      elseif node.operator == "%" then
        return left%right
      else
        error("Unknown operator: " .. node.operator)
      end
    elseif node.type == "Identifier" then
      return env[node.name]
    elseif node.type == "TableAccess" then
      local base = evaluate(node.base) -- Evaluate the base expression FIRST
       if type(base) ~= "table" then
            error("Attempt to index a non-table value")
          end
      local index = evaluate(node.index)
      if type(index) ~="number" and type(index) ~="string" then
        error("Table index must be a string or a number")
      end
      return base[index]
    elseif node.type == "Assignment" then
      if node.target.type=="TableAccess" then
        evaluate(node.target.base)[node.target.index.value]=evaluate(node.value)
      elseif node.target.type=="Identifier" then
        env[node.target.name] = evaluate(node.value)
      end
      return env[node.target.name]
    elseif node.type == "ReturnStatement" then
      return evaluate(node.expression)
    elseif node.type == "IfStatement" then
      if evaluate(node.condition)==true then
        return evaluate(node.thenBlock)
      elseif node.elseBlock then --elseifs?
        return evaluate(node.elseBlock)
      end
    elseif node.type == "WhileLoop" then
      if #node.body.statements==0 then
        print("!warn! empty while loop")
        return
      end
      while evaluate(node.condition)==true do
        if evaluate(node.body)=="Break" then
          break
        end
      end
    elseif node.type == "ForLoop" then
      env[node.variable]=node.start.value
      if not node.step then node.step=AST.NumberLiteral(1) end
      while env[node.variable]<=node.endValue.value do
        if evaluate(node.body)=="Break" then
          break
        end
        env[node.variable]=env[node.variable]+node.step.value
      end
    elseif node.type == "Break" then return "Break"
    else
      error("Unknown node type: " .. node.type)
    end
  end

  return evaluate, env
end

-- Example Usage (assuming you have the lexer and Token defined)
local source_code = [[
m={}
function f(){print(2)}
function m.func(){print(1)}
f()
//m.func()
]]
local start_time=os.clock()
local tokens = lex(source_code)
for _, token in ipairs(tokens) do
  print(token)
end
local ast = parse(tokens)
print_ast(ast)
print("---Parse time: "..tostring((os.clock()-start_time)*1000).."ms")
start_time=os.clock()
local eval,env=create_interpreter()
print("---Program Output----")
eval(ast)
print("---Execution time: "..tostring((os.clock()-start_time)*1000).."ms")
print(env["m"]["func"])

--[[
TODO (ordered)
m.functions
elseif
more system functions(main,string,table etc)
include(modName)
custom env
web3 libs
]]