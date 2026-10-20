# LTDE 1.0

LTDE is a small desktop shell for OpenComputers, built on OpenOS and TGL. It has a
Windows 95 style interface with movable windows, a taskbar, a Start menu, and
applications for everyday file and system tasks.

## What you need

- OpenComputers with OpenOS, running the **Lua 5.3** architecture.
- A Tier 2 GPU and screen or better.
- At least **1 MB RAM**. More RAM helps when several apps are open.
- A writable disk and a keyboard.

Redstone Control needs a redstone component. Bundled mode also needs compatible
hardware and a supported redstone mod.

## Install and start

Extract the release ZIP on your host computer, then copy its contents to your
OpenComputers disk:

- `ltde` goes to `/ltde`.
- Merge `usr` into `/usr`, keeping the existing OpenOS files.
- `docs`, `README.md` and `CHANGELOG.md` are reference files; they can stay on
  your host computer.

At the OpenOS prompt, run:

```
ltde
```

For an upgrade, back up `/ltde/cfg` and your own files first. The archive contains
fresh default settings, so copying them over existing settings will reset them.

You do not need to flash an EEPROM or change the OpenOS startup files. The
included `/ltde/etc/autorun.lua` is optional and is not installed as an autorun
script automatically.

## Using the desktop

Click Start to open an app. Drag a window's title bar to move it. The title-bar
buttons minimize or close it; taskbar buttons restore windows or bring them to
the front. Start's power menu can exit to OpenOS, restart LTDE, or shut down or
restart the computer.

The release includes:

- **Explorer:** files, mounted devices, copy/move/delete, search, bookmarks and
  file properties. Double-click to open; Ctrl-click for multiple selection.
- **Notepad:** edit text files. Explorer opens unassociated files here.
- **Command Prompt:** LTDE commands, command history, Tab completion, colored
  output and scrollback. Type `help` for the command list.
- **Control Panel:** display and system settings.
- **Task Manager:** inspect running applications and manage their lifecycle.
- **My Computer:** memory, display and installed-component information.
- **Calculator:** buttons, keyboard input and an optional scientific view.
- **Redstone Control:** normal/bundled signals, side selection and output control.
- **Hello World:** a small example app.

CMD runs LTDE's own commands. It does not host the OpenOS shell in this version.
Try `dir`, `edit notes.txt`, `run calc.app`, or `calc "sqrt(81)+2^3"`.

## Settings and logs

Settings are in `/ltde/cfg/*.conf`. Use Control Panel for its supported settings;
file associations and file colors can also be changed in their config files.
Restart LTDE after manual changes unless the relevant documentation says otherwise.

Session logs are written to `/ltde/logs/latest.log`; older sessions are archived.
App crash reports are under `/ltde/logs/crashlogs`. If something fails, keep the
error text and the relevant log, along with your hardware details.

TGL debug logging and LTDE's manual crash shortcut are disabled in this release.
Normal session logs and error reports are still available. `dbgev.app` is not
included.

## Writing apps

Version 1 apps run in system mode. Install apps you trust: this version does not
provide a complete application sandbox. A `.app` is a folder containing a
manifest and a Lua entry point. See [Writing an app](docs/APPS.md) for an example.

## More information

See [the documentation index](docs/README.md) for internals, app APIs and usage notes.
