# LTDE Command Prompt and command API

## Overview

Command Prompt is an LTDE console with its own commands. It does not execute OpenOS shell commands or Lua entered at the prompt.

| File | Responsibility |
| --- | --- |
| `/ltde/apps/cmd.app/main.lua` | Window, menus, input editing, history, terminal display |
| `/ltde/sys/slib/lterm.lua` | Text output, stored colors, wrapping, scrollback |
| `/ltde/sys/slib/ltcmd.lua` | Public API facade initialized by the LTDE core |
| `/ltde/sys/cmd.lua` | Parsing, discovery, authorization, command execution |
| `/ltde/sys/cmd/*.lua` | Command implementations |

Each CMD window owns a session, working directory, output buffer, colors, input, and history. The LTDE clipboard is shared between CMD windows.

## Using the window

- Enter submits the command. Left/Right, Home/End, Backspace/Delete edit input.
- Up/Down browse command history; returning past the newest entry restores the draft.
- Ctrl+C clears the current input and prints `^C`. It does not interrupt a running command.
- Paste from the host arrives through OpenComputers' `clipboard` signal. Newlines become spaces; pasting does not execute a command.
- Scroll with the mouse wheel, Page Up/Page Down, View menu, or by dragging the right-hand scrollbar.
- The prompt stays at the bottom while output scrolls. New output returns the view to the bottom.
- Scrollback holds 200 wrapped lines; history holds 100 commands; input is limited to 4096 characters.
- Output uses buffered redraw. If there is insufficient GPU memory, TGL falls back to direct drawing.

Menus:

| Menu | Items |
| --- | --- |
| File | New Command Prompt, Close |
| Edit | Copy output, Copy input, Paste, Clear input |
| View | Page up, Page down, Top, Bottom, Clear screen |

Copy output copies all retained output as plain text, not just the visible page. Copy input copies the current editable command. Menu Paste uses the internal LTDE clipboard, including copies made in another CMD window. This does not write to the host computer's clipboard. Arbitrary mouse text selection is not implemented.

## Commands

| Command | Behavior |
| --- | --- |
| `help [command]` | Compact command-name grid, or usage for one command/alias |
| `echo [text]` | Print arguments separated by spaces |
| `date`, `time` | Display `os.date` date/time as supplied by the environment |
| `pwd` | Print the session working directory |
| `cd [path]` | Change directory; without a path, print the current directory |
| `dir [options] [path]` | Windows-style dated listing with sizes, `<DIR>` markers, totals, and free space |
| `alias [name[="command"]]`, `alias -d name` | List, inspect, define, or delete a session alias |
| `mkdir <path>` | Create a directory, including missing parents |
| `rmdir <path>` | Remove an empty directory; reject root and mounted device roots |
| `edit <file>` | Create a missing file when possible, then open the configured editor with its absolute path |
| `del <file> [file ...]` | Delete files; reject directories and report failures |
| `cmd` | Open a new Command Prompt window starting in `/home` |
| `cls` | Clear output and reset scroll position; retain colors |
| `color [attribute]` | Change console colors and recolor existing output; defaults to `07` |
| `run <app> [arguments...]` | Start an application through runctl |
| `ps` | Aligned PID, state, and process-name columns |
| `type <file> [file ...]` | Print text files; alias `cat` |
| `copy [-f] <source-file> <destination>` | Copy one file; alias `cp` |
| `move [-f] <source-file> <destination>` | Copy then remove the source after success; alias `mv` |
| `ren <path> <new-name>` | Rename a file or directory within its parent |
| `tree [-a] [-d] [-L depth] [path]` | Show a directory tree |
| `df` | Mounted filesystem total/free capacity and percentage used |
| `history` | Numbered command history for the session |
| `mem`, `uptime` | Computer RAM usage and time since boot |
| `notify [options] <message>` | Transient notification, warning, error, or dialog |
| `shutdown` | Request computer power-off through LTDE cleanup |
| `quit-ltde` | Exit LTDE through cleanup and return to OpenOS |
| `ltwm refresh` | Buffered full-screen desktop redraw to clear artifacts |
| `ltwm windows` | List stable window IDs, owner PIDs, titles, and states |
| `ltwm focus/minimize/restore/close <id>` | Operate on a non-system window |
| `ver` | Open an LTDE/TGL version dialog |
| `exit` | End this command session and close its CMD window |

Examples:

```text
cd /home
run notepad.app "/home/My Documents/notes.txt"
ltwm windows
ltwm focus 3
color 1f
color 2
```

`run notepad` and `run notepad.app` resolve under `/ltde/apps`. An app path containing `/` is resolved against the CMD working directory unless absolute. `.app` is appended when absent. Application arguments are passed unchanged as separate strings, including empty quoted arguments. The CMD working directory is not imposed on the launched application; use absolute file arguments when the application requires them.

Command names are case-insensitive at invocation. Modules have lowercase filenames. Double quotes group arguments and may surround empty arguments. Spaces inside quotes are preserved. There is no quote escaping, variable expansion, pipe, wildcard expansion, command chaining, or shell fallback. Output redirection supports `>` and `>>` as described below. Backslashes are literal characters.

## Color attributes

Two hex digits mean background then foreground. One digit means foreground on black. For example, `1f` is white on blue and `2` is green on black. Matching foreground/background digits are rejected to avoid invisible text.

| Digit | Color | Digit | Color |
| --- | --- | --- | --- |
| 0 | Black | 8 | Dark gray |
| 1 | Dark blue | 9 | Blue |
| 2 | Dark green | A | Green |
| 3 | Dark cyan | B | Cyan |
| 4 | Dark red | C | Red |
| 5 | Dark magenta | D | Magenta |
| 6 | Olive | E | Yellow |
| 7 | Light gray | F | White |

Colors are RGB requests; the OpenComputers GPU approximates them to its available palette. These commands do not change the desktop's hardware palette. Tier 2 may map some attributes to the same displayed color.

## Public command API

During LTDE, trusted system applications can use the global `ltcmd` facade. The file `slib/ltcmd.lua` is a factory initialized by the core, not an independently configured singleton.

```lua
local code,text=ltcmd.execute('echo "Hello from an app"')

local session=ltcmd.newSession()
session:execute("cd /")
local code,text=session:execute("dir")
```

| API | Result |
| --- | --- |
| `ltcmd.execute(line)` | `exitCode, outputOrError`; fresh session starting in `/home` |
| `ltcmd.newSession([terminal])` | Persistent session; optionally use an existing lterm instance |
| `session:execute(line)` | `exitCode, outputOrError`; retains cwd, colors, output |
| `ltcmd.setClipboard(text)` | Replace LTDE clipboard, capped at 65536 bytes |
| `ltcmd.getClipboard()` | Current LTDE clipboard string |

Session fields: `cwd`, `term`, `closed`, `aliases`, `history`. `exit` sets `closed=true`; the embedding application decides how to respond. Command errors return a nonzero code and an error message; CMD prints that message. Successful output is returned as plain text and also written to the terminal, unless redirected to a file (then the returned output string is empty). Output written before an error remains in the terminal. Output capture includes both `ctx:write/print` and direct `ctx.term:write/print` calls.

Execution is synchronous. A launched app runs separately through runctl. A command such as `ver` may block until its dialog closes. Live redraw while a long command is running and cancellation of running commands are not implemented.

## Terminal API

```lua
local lterm=loadfile("/ltde/sys/slib/lterm.lua")()
local terminal=lterm:new(63,17)
terminal:setColor("1f")
terminal:print("White on blue")
terminal:setColor("2")
terminal:print("Green on black")
local session=ltcmd.newSession(terminal)
```

| Method | Behavior |
| --- | --- |
| `lterm:new([width,height])` | Defaults to 60 columns and 16 visible rows |
| `terminal:write(text)` | Append text; wrap by character-cell width |
| `terminal:print(text)` | Append text and newline |
| `terminal:clear()` | Clear stored output; retain colors |
| `terminal:setColor([attribute,recolor])` | Set hex attribute; `recolor=true` also recolors stored spans; returns `true` or `nil,error` |
| `terminal:setColors(foreground,background)` | Set RGB integers `0..0xFFFFFF` for subsequent output; returns `true` or `nil,error` |
| `terminal:getColors()` | Current foreground and background RGB values |
| `terminal:scrollBy(n)` | Positive moves toward older output; returns whether position changed |
| `terminal:getLines()` | Visible rows as plain strings |
| `terminal:getRows()` | Visible rows as arrays of `{text,foreground,background}` spans |
| `terminal:getText()` | All retained output joined with newlines, without styling |

The `color` command recolors the entire retained transcript. Programs using `setColor` without `recolor`, or using `setColors`, affect subsequent writes only, allowing mixed-color output. CMD's blank area, prompt, and caret follow the terminal's current colors.

`width`, `height`, `limit`, and `scroll` describe the terminal. `scroll=0` means bottom. Keep positive dimensions and a positive line limit. `lines` and `styles` are implementation storage; treat them and returned spans as read-only. `onWrite(text)` is an optional observer; the processor temporarily chains it to capture command output. Tabs become two spaces, carriage returns are ignored, and ANSI escape sequences are not interpreted. Cursor-addressed output is not yet supported.

## Adding commands

Place a lowercase module such as `/ltde/sys/cmd/greet.lua` in the commands directory. Names may contain `a-z`, `0-9`, `_`, and `-`. Commands are discovered on each execution, so adding, editing, or removing a module requires no processor edit or restart. Symbolic-link command files are rejected.

```lua
return {
  usage="greet [name]",
  run=function(ctx,args)
    local fg,bg=ctx.term:getColors()
    ctx.term:setColor("a")
    ctx:print("Hello, "..(args[1] or "world").."!")
    ctx.term:setColors(fg,bg)
    return 0
  end
}
```

A module returns a table with:

- `usage`: optional help string, defaults to the command name.
- `permissions`: optional array of additional named permissions to require before `run`.
- `validate(ctx,args)`: optional preflight called before opening an output redirection; return `false,errorMessage` to reject.
- `run(ctx,args)`: command function; return `0` or nothing for success, or `nonzeroCode,errorMessage` for failure.

A bare returned function remains supported for compatibility, using the filename as help text. Keep module top-level code free of side effects: `help <command>` loads a module to read its usage; plain `help` only lists discovered names. Modules are loaded afresh, not cached.

Command context:

| Member | Purpose |
| --- | --- |
| `ctx:write(text)`, `ctx:print(text)` | Captured terminal output |
| `ctx.term` | Terminal instance, including color controls |
| `ctx.cwd` | Session directory; changes are retained after normal return |
| `ctx:resolve(path)` | Resolve absolute/relative paths using session cwd |
| `ctx.closed` | Set true to request session closure |
| `ctx.commands` | Discovered command-name set |
| `ctx.history` | Session command history, oldest first; includes the current command |
| `ctx.redirectPath` | Resolved output path when redirected, otherwise nil; available during validation/execution |
| `ctx.aliases` | Mutable per-session alias map; defaults to `ls=dir`, `clear=cls`, `rm=del`, `cat=type`, `cp=copy`, `mv=move` |
| `ctx:column(text,width[,right])` | Format a cell-width column, truncating with `~`; optional right alignment |
| `ctx:getUsage(name)` | Usage string, nil for unknown command, diagnostic for invalid module |
| `ctx.services.launch(path,args)` | Launch an app; returns program or nil,error |
| `ctx.services.programs()` | Snapshot array of `{id,name,running}` |
| `ctx.services.dialog(title,text,buttons)` | Blocking dialog; returns chosen button label |
| `ctx.services.notify(title,text[,timeout])` | Transient information notification |
| `ctx.services.warn(title,text[,timeout])` | Transient warning notification |
| `ctx.services.error(title,text)` | Blocking error dialog |

`ctx.services.caller()` and `.permissions` belong to processor authorization; commands should not replace them. Commands must use the context output API, rather than global `print`, to write into CMD. Calling `run` launches an independent application; it does not attach that app's stdout to this terminal.

## Permission boundary

Every execution resolves the calling coroutine through LTDE/runctl. The caller must be a registered application in `system` mode with `rootAccess`. This check occurs before module discovery/loading. A module's additional permissions are checked after loading its trusted metadata and before calling `run`.

Command modules are trusted LTDE code, not sandboxed plugins. Do not install untrusted Lua into this directory. The existing manifest mechanism is not a secure approval system for untrusted applications. Sandboxed application command access is not exposed in this version. Session fields and command text cannot supply a PID or permission grant to the dispatcher.

## Directory formatting and options

The default `dir` view uses `DD/MM/YYYY HH:MM`, a right-aligned size or `<DIR>` marker, and the name. The summary counts displayed files/directories and file bytes; free space is device-wide. Directories sort before files. Hidden names beginning with `.` are excluded by default.

| Option | Meaning |
| --- | --- |
| `-a`, `--all` | Include hidden entries |
| `-b`, `--bare` | Names only, one per line; no headings, metadata, or totals |
| `-d`, `--dirs-only` | Directories only |
| `-f`, `--files-only` | Files only; mutually exclusive with `-d` |
| `-r`, `--reverse` | Reverse sorting within directory/file groups |
| `--sort name`, `--sort size`, `--sort date` | Choose sort key; defaults to name |
| `--` | End option parsing, allowing a path beginning with `-` |

Short flags can be combined: `dir -abf` prints names of all files, including hidden files. One path is accepted. Recursive listing and wildcard patterns are not implemented.

## Aliases

Aliases belong to a session and are not saved to disk. New sessions start with `ls=dir`, `clear=cls`, `rm=del`, `cat=type`, `cp=copy`, and `mv=move`.

```text
alias
alias ls
alias ll="dir -a"
ll /home
alias -d ll
```

An alias expands the first command word and prepends its stored arguments to the caller's remaining arguments. Aliases may refer to other aliases; cycles are rejected. An alias cannot replace `alias` itself. Alias expansions cannot contain output redirection; place redirection on the invocation instead. Arguments inside an expansion are parsed with the normal double-quote rules.

## Output redirection

```text
echo "aa" > /home/example.txt
echo "bb" >> /home/example.txt
dir -b > "file list.txt"
```

`>` creates or overwrites; `>>` creates or appends. Targets are relative to the session directory unless absolute. A redirection must be the final operator and filename; multiple redirects are rejected. Operators inside double quotes are literal text, so `echo ">"` prints `>`.

Redirected stdout goes to the file instead of terminal scrollback. Errors remain returned to the caller and displayed by CMD. Both context writes and `ctx.term:write/print` are redirected. Terminal controls such as `clear` and color changes still affect the session. A target is opened only after command lookup/loading and permission checks; once opened, an overwrite truncates it even if the command subsequently fails. Files are closed on command failure as well as success. This is text output redirection, not an OpenOS shell invocation.

## Default editor

`edit notes.txt` resolves the file against the session directory and passes the absolute path to the editor. The default is `/ltde/apps/notepad.app`. Set `text_editor` in the `[system]` section of `/ltde/cfg/core.conf` to another editor app's absolute path. The chosen editor must accept the filename as its first argument. A missing file is created in append mode before the editor launches, preserving any file created concurrently. Existing files are not truncated. A creation failure returns an error in CMD without launching the editor. Missing parent directories are not created automatically; use `mkdir` first. If editor startup fails after successful creation, the empty file remains. Restart LTDE after changing this configuration.

## Deleting files

`del one.txt "two files.txt"` deletes the specified files. `rm` is a built-in alias for `del` in new sessions. No wildcard expansion or recursive deletion is provided. The command validates every argument before starting and rejects directories; use `rmdir` for an empty directory. Duplicate paths are deleted once. A failure during removal stops the operation, so earlier successful deletions remain in effect. Deletion is permanent; there is no recycle bin.

## Text, copying, and moving

```text
type /home/notes.txt
cat /home/notes.txt
cp notes.txt backup.txt
copy -f notes.txt backup.txt
mv backup.txt /home/archive
ren notes.txt draft.txt
```

`copy` and `move` accept one source file and one destination; a destination directory receives the source basename. They refuse an existing destination unless `-f`/`--force` is supplied. Use `--` before paths beginning with `-`. Directory copying/moving and symbolic-link paths are not supported in these commands yet. Mount aliases identifying the same source/destination file are rejected. Moving removes the source only after copying succeeds; if removal fails, the error explicitly reports that the copy succeeded. Overwrite failures may leave a partial destination.

`ren` accepts a new basename, not a destination path, and refuses an existing destination or a mounted device root. It can rename directories. `type` concatenates text files without extra headers or separators. It reads in chunks, preserves newlines, and rejects redirecting a source onto itself before the output file is opened. With redirection, symbolic-link source/destination paths are rejected.

## Tree, storage, and session information

`tree` defaults to depth 3. `-L`/`--depth` accepts 0 through 16; `-a`/`--all` includes hidden entries; `-d`/`--dirs-only` omits files. Symbolic-link directories are listed but not traversed. Output stops at 1000 entries. `df` lists mount points, so a filesystem mounted twice appears twice; capacity reads are protected against unavailable devices.

`history` uses the same 100-entry history as CMD's arrow keys. Session API calls are recorded too, consecutive duplicates are suppressed, and the current `history` command appears in its own listing. `mem` reports total, used, and free RAM in KB. `uptime` reports days and `HH:MM:SS` since computer startup.

## Notifications and dialogs

```text
notify "Finished copying"
notify -t warn -T Storage -d 5 "Disk almost full"
notify -t error -T Editor "Could not open file"
notify -t dialog -T Confirm -b "Yes,No" "Continue?"
```

| Option | Meaning |
| --- | --- |
| `-t`, `--type` | `info` (default), `warn`, `error`, or `dialog` |
| `-T`, `--title` | Title; defaults to Command Prompt |
| `-d`, `--duration` | Positive seconds, for info/warn only |
| `-b`, `--buttons` | Comma-separated dialog button labels; default OK |
| `--` | End options, allowing a message beginning with `-` |

Remaining arguments form the message, separated by spaces. Info and warning notifications return immediately; errors and dialogs block until dismissed. A dialog prints the selected button label as command output, including when output is redirected. Invalid option combinations return an error rather than being ignored.

Transient notifications use LTWM overlays above the current windows, restore the underlying region on expiry, and are removed during notification cleanup. The existing limit of three simultaneous notifications still applies; additional notifications are silently dropped. Long transient titles/messages are truncated to fit; dialogs wrap their body text.

`shutdown` and `quit-ltde` take no arguments and use the same cleanup paths as LTDE’s desktop controls. They do not add a save prompt or save unsaved documents automatically. `exit` still closes only the current CMD session.

### kill

`kill <pid>` forcibly ends a running application and closes its managed windows.
Use `ps` to find its PID. Unsaved changes are lost; no confirmation dialog is
shown. The calling application cannot kill itself (use `exit` in CMD). Services
must be stopped or restarted through Task Manager's service controls. Invalid
PIDs and already-exited processes return an error.

### Tab completion

Press Tab to complete a command, alias, app name after `run`, or a filesystem
path relative to the terminal's current directory. Press Tab again to cycle
through sorted matches. `cd` completes directories only; output redirection
completes paths. Directory candidates end with `/`. Filenames containing
spaces are double-quoted automatically. Completion works at the end of a token,
keeps following arguments, and never executes the command. Editing or moving
the cursor resets the cycle. Command names are discovered from `/ltde/sys/cmd`,
so newly added command modules also become completion candidates.

### Calculator

`calc <expression>` evaluates arithmetic using the same engine
as Calculator. Example: `calc "sqrt(81)+2^3"`.
`run calc.app` opens the button/keyboard UI.

CMD `calc` accepts decimal/scientific numbers, `+ - * /`, unary signs,
parentheses, and `^`. Powers associate right-to-left; `-2^2` is `-4`.
Constants are `pi` and `e`. Functions take one argument in parentheses:
`sqrt abs sin cos tan asin acos atan ln log exp floor ceil`.
Trig uses radians, `ln` is natural logarithm and `log` is base 10.
There is no implicit multiplication, percentage operator or complex support.

Each invocation starts independently (`ans` is initially 0). Expressions have
a 512-character limit and bounded nesting. Results show 12 significant digits.
Invalid input, division by zero and non-finite results return errors. Output
can be redirected like other commands.

The window and command share `/ltde/sys/slib/ltcalc.lua`. System code can load it
with `loadfile(...)()`. `evaluate(expression,extended,ans)` returns a number or
`nil,error`; `format(number)` returns the display string. The command passes
`true` for extended mode. The engine parses its own grammar and never executes
an expression as Lua code.
