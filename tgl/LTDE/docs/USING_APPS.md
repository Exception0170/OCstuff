# Using the bundled apps

Open apps from Start, or use `run name.app` in CMD. Start rescans apps when it
opens; Find filters app names and paths after Enter. Clear Find and press Enter
to restore the full list. Click outside or press Escape to dismiss Start.

## Explorer

Double-click a file to open its associated app. Double-click a `.app` folder to
launch it. Ctrl-click selects several items. Copy/Cut and Paste share a file
clipboard between Explorer windows.

Find filters names in the current folder; Find in files searches their contents.
Neither is recursive. Refresh clears the search. Bookmarks are saved between
sessions. View controls the sidebar, statusbar, hidden files, and List/Details;
Properties shows the selected item or current folder, including recursive size.
A partial size means links, other mounted devices, or unreadable items were skipped.

Copy/move progress counts nested files and folders, including empty folders.
Conflicts offer Replace, Rename, Skip and Cancel. Apply to all repeats Replace
or Skip for the rest of that operation. A move removes its source tree only
after the whole copy succeeds; skipped or cancelled moves keep the original
and any copies already completed. Deletion is permanent. Undo only reverses the
last rename, not deletion or other file operations.

Duplicate makes a numbered copy when needed. Folder transfers reject symbolic
links, destinations inside the source, and source trees containing other mounted
filesystems. File handlers and shared colors are described in
[Configuration](CONFIG.md).

## Notepad and Command Prompt

Notepad opens text files from Explorer or `edit path` in CMD. Save your changes
before closing it or ending its task. CMD provides LTDE's own commands, history,
Tab completion and scrollback. See [CMD](CMD.md) for commands and shortcuts.

## Control Panel

Choose a page, click a setting to select it, then click it again to edit. Apply
saves without closing; OK saves and closes; Cancel discards changes since the
last Apply. A `*` marks a setting that needs an LTDE restart. Wallpaper and drag
cursor changes take effect on Apply. Settings descriptions appear in the window.

## Task Manager and My Computer

Task Manager lists application snapshots, allows switching to a window and can
end an app after confirmation. End Task does not save the app's work. Memory
figures describe the whole computer/GPU, not each app. The service action buttons
call the service API; the current public process list supplies application rows
only, so it does not populate service selections.

My Computer shows system versions, architecture, memory, display information,
uptime and a scrollable component list. Refresh updates it; component changes
also refresh the view.

## Calculator

Use buttons or type an expression. Enter or `=` calculates, Backspace deletes,
Escape/Delete clears, and F2 switches Basic/Extended. The `neg` button negates
the whole expression. `ans` recalls the last successful result in that window.

Basic mode has arithmetic and parentheses. Extended mode adds powers, constants
and functions. Angles use radians. CMD's `calc` always enables all functions;
[the command guide](CMD.md#calculator) lists them.

## Redstone Control

Normal and Bundled tabs show inputs and outputs. Select a card and one of the
six sides from the dropdowns. Sides are relative to the computer's orientation.
Bundled mode lists all 16 color channels; select one before using Set output.

Set output changes only that side/channel. Closing the app, changing tabs, or
selecting another side leaves hardware outputs as set. Vanilla redstone uses
0-15; modded/bundled systems can use other ranges, often 0-255. The prompt accepts
non-negative integers up to 2147483647; actual support depends on the hardware.
Missing cards or unavailable bundled functions are reported in the window.

## Hello World

A small example window with a button that sends a notification. Its source is
in `/ltde/apps/hello.app`.
