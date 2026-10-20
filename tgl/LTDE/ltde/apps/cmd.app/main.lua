local tgl=require("tgl")
local unicode=require("unicode")
local keyboard=require("keyboard")
local complete=loadfile("/ltde/sys/slib/ltcomplete.lua")()
local completions=nil
local completionIndex=0
local lterm=loadfile("/ltde/sys/slib/lterm.lua")()
local done="cmd_done_"..tostring(math.random(1,100000000))
local events={}
for _,name in ipairs({"new","copy","copyinput","paste","clearinput","pageup","pagedown","top","bottom","clear"}) do
  events[name]=done.."_"..name
end
local frame,cs=ltwapi.addWindow(64,20,"Command Prompt",{
  onClose=function() ltevent.push(done) end,
  toolbar=true,
  menuItems={
    {label="File",items={
      {label="New Command Prompt",eventName=events.new},
      {label="Close",eventName=done}
    }},
    {label="Edit",items={
      {label="Copy output",eventName=events.copy},
      {label="Copy input",eventName=events.copyinput},
      {label="Paste",eventName=events.paste},
      {label="Clear input",eventName=events.clearinput}
    }},
    {label="View",items={
      {label="Page up       PgUp",eventName=events.pageup},
      {label="Page down     PgDn",eventName=events.pagedown},
      {label="Top",eventName=events.top},
      {label="Bottom",eventName=events.bottom},
      {label="Clear screen",eventName=events.clear}
    }}
  }
})
if not frame then return end
local term=lterm:new(cs.sizeX-1,cs.sizeY-1)
local session=ltcmd.newSession(term)
local col=tgl.Color2:new(term:getColors())
local input=""
local cursor=0
local history=session.history
local histIndex=1
local draft=""
local view=tgl.Frame:new({},cs,col)
frame:add(view,"terminal")
local scrollbar=tgl.Scrollbar:new(tgl.Size2:new(cs.sizeX,1,1,term.height),col)

-- Rebuild the visible lines so window moves and focus redraws retain the console.
local function redraw()
  col=tgl.Color2:new(term:getColors())
  view.col2=col
  view.objects={}
  for i,spans in ipairs(term:getRows()) do
    local x=1
    for j,span in ipairs(spans) do
      view:add(tgl.Text:new(span.text,tgl.Color2:new(span.foreground,span.background),tgl.Pos2:new(x,i)),"line"..i.."_"..j)
      x=x+unicode.wlen(span.text)
    end
  end
  scrollbar.maxScroll=math.max(0,#term.lines-term.height)
  scrollbar.visibleSize=term.height
  scrollbar.scroll=scrollbar.maxScroll-term.scroll
  scrollbar.col2=col
  view:add(scrollbar,"scrollbar")
  local prompt=session.cwd..">"
  local before=prompt..unicode.sub(input,1,cursor)
  local after=unicode.sub(input,cursor+1)
  while unicode.wlen(before)>=term.width do before=unicode.sub(before,2) end
  local line=before..after
  while unicode.wlen(line)>term.width do line=unicode.sub(line,1,unicode.len(line)-1) end
  view:add(tgl.Text:new(line,col,tgl.Pos2:new(1,cs.sizeY)),"input")
  local caret=tgl.Text:new(unicode.sub(after,1,1)~="" and unicode.sub(after,1,1) or " ",
    tgl.Color2:new(term.background,term.foreground),tgl.Pos2:new(unicode.wlen(before)+1,cs.sizeY))
  caret.z_index=1
  view:add(caret,"caret")
  local wm=tgl.sys.wm
  local m=wm and wm:getManagedWindow(frame)
  if m and not frame.hidden then wm:renderRegions({wm:getWindowBounds(m)}) end
end

scrollbar.onChange=function(value)
  term.scroll=scrollbar.maxScroll-value
  redraw()
end

local function insert(text)
  text=text:gsub("[\r\n]"," ")
  local room=4096-unicode.len(input)
  text=unicode.sub(text,1,math.max(0,room))
  input=unicode.sub(input,1,cursor)..text..unicode.sub(input,cursor+1)
  cursor=cursor+unicode.len(text)
end

term:print("LTDE "..tostring(_G._ltde_version or ""))
term:print("Type help for available commands.")
redraw()
scrollbar:enable()
while not session.closed do
  local ev,a,b,c,d=ltevent.pull()
  if ev==done or ev=="ltde_shutdown" then break end
  local changed=false
  if (ev=="key_down" and c~=15) or ev=="clipboard" or ev==events.paste or ev==events.clearinput then
    completions=nil completionIndex=0
  end
  if ev==events.new then
    local code,err=ltcmd.execute("run cmd.app")
    if code~=0 then term:print(err) changed=true end
  elseif ev==events.copy then ltcmd.setClipboard(term:getText())
  elseif ev==events.copyinput then ltcmd.setClipboard(input)
  elseif ev==events.paste then insert(ltcmd.getClipboard()) changed=true
  elseif ev==events.clearinput then input="" cursor=0 changed=true
  elseif ev==events.pageup then changed=term:scrollBy(term.height)
  elseif ev==events.pagedown then changed=term:scrollBy(-term.height)
  elseif ev==events.top then changed=term:scrollBy(#term.lines)
  elseif ev==events.bottom then changed=term:scrollBy(-#term.lines)
  elseif ev==events.clear then term:clear() changed=true
  elseif ev=="key_down" then
    if c==15 then
      if not completions then completions=complete.matches(input,cursor,session) end
      if #completions>0 then
        completionIndex=completionIndex%#completions+1
        local match=completions[completionIndex]
        input=match.line cursor=match.cursor changed=true
      end
    elseif c==28 or c==156 then
      local line=input
      term:print(session.cwd..">"..line)
      input="" cursor=0 histIndex=#history+1 draft=""
      local code,output=session:execute(line)
      histIndex=#history+1
      if code~=0 then term:print(output) end
      changed=true
    elseif c==200 or c==208 then
      if histIndex==#history+1 then draft=input end
      histIndex=math.max(1,math.min(#history+1,histIndex+(c==200 and -1 or 1)))
      input=history[histIndex] or draft cursor=unicode.len(input) changed=true
    elseif c==203 then cursor=math.max(0,cursor-1) changed=true
    elseif c==205 then cursor=math.min(unicode.len(input),cursor+1) changed=true
    elseif c==199 then cursor=0 changed=true
    elseif c==207 then cursor=unicode.len(input) changed=true
    elseif c==201 then changed=term:scrollBy(term.height)
    elseif c==209 then changed=term:scrollBy(-term.height)
    elseif c==14 and cursor>0 then
      input=unicode.sub(input,1,cursor-1)..unicode.sub(input,cursor+1)
      cursor=cursor-1 changed=true
    elseif c==211 then
      input=unicode.sub(input,1,cursor)..unicode.sub(input,cursor+2) changed=true
    elseif b==3 then
      term:print(session.cwd..">"..input.."^C") input="" cursor=0 changed=true
    elseif b and b>=32 and not keyboard.isControlDown() then insert(unicode.char(b)) changed=true end
  elseif ev=="clipboard" then
    insert(b or "") changed=true
  elseif ev=="scroll" then
    local wm=tgl.sys.wm
    local m=wm and wm:getWindowAt(b,c)
    if m and m.frame==frame and tgl.util.pointInSize2(b,c,tgl.sys.activeArea)
    and tgl.util.pointInSize2(b,c,view.size2) and b<scrollbar.size2.x1 then
      changed=term:scrollBy(d*3)
    end
  end
  if changed and not session.closed then redraw() end
end
scrollbar:disable()
frame:disableAll()
local wm=tgl.sys.wm
if wm and wm:getManagedWindow(frame) then ltwapi.removeWindow(frame) end
return 0
