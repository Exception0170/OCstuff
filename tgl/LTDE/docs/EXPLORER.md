# File Explorer v0.2

Explorer uses a 60x20 window for Tier 2 displays. Dates show `DD/MM/YYYY`;
filesystem timestamps in milliseconds are converted before formatting. Missing
or invalid timestamps show `?`.

Double-click files to open their associated application, or `.app` folders to
launch them. Ctrl-click selects several items. Selection preserves scrolling.
Copy and Cut share a file clipboard between Explorer windows.

- **Find** filters names in the current folder, ignoring case.
- **Find in files** searches contents of files in the current folder, ignoring
  case. Reads use small chunks; matches are cached for the current search.
- An empty search or **Refresh** clears the filter. Searches are not recursive.
- **Duplicate** creates `name (Copy)` (or a numbered copy), preserving extensions.
- **Undo rename** reverses the last rename in that Explorer window, provided the
  original name is free and the renamed item still exists. It does not undo
  copies, moves, or permanent deletion.
- **Bookmarks** adds/removes the current folder and saves entries in
  `/ltde/cfg/bookmarks.conf`.
- **View** toggles the sidebar, statusbar, hidden files, and List/Details.
- **View > Properties** shows the selected file/folder's name, path, type, size,
  modification date, and device access. With no selection it shows the current
  folder. Folder sizes include nested and hidden files, plus file/folder counts.
  Links, other mounted devices, and unreadable items are excluded and reported
  as a partial size. Sizes measure file contents, not allocated disk space.

Copy/move conflicts offer Replace, Rename, Skip, or Cancel. A source tree is
removed only after its entire copy succeeds. On a skipped, cancelled, or failed
move, the original remains; copies already completed at the destination remain
as well. Symbolic links, nested destination folders, and source trees containing
other mounted filesystems are rejected. Deletion is permanent and asks first.

## File associations

Applications declare `opens={"txt","lua"}` in `manifest.lua`, or `opens={"*"}`
for a fallback. Manifests are read at desktop startup in alphabetical app order;
the first app claiming an extension wins. Extension matching ignores case.
Notepad declares the fallback.

`/ltde/cfg/associations.conf` overrides these defaults:

```ini
default=/ltde/apps/notepad.app
[extensions]
txt=/ltde/apps/notepad.app
```

Restart LTDE after changing manifests or associations. An invalid override
reports an error instead of silently opening another application.

`ltwapi.openFile(path)` returns the launched program, or `nil,error`. It resolves
an extension through `_G._ltde_associations` and passes the file path as the
application's first positional argument. This is a system-mode API.

Custom system dialogs may use `ltnotify.openModal(frame)` and retain its returned
state. Always pair it with `ltnotify.closeModal(frame,state)`, including after
errors, to restore focus restrictions and remove the overlay.

## Ocelot checks

Check dates, double-clicking an app folder and a text file, selecting after
scrolling, all three layout toggles, bookmarks after restarting Explorer, and
copy/paste between two Explorer windows. Exercise conflict choices and cancelled
moves with disposable files, then verify that the sources remain. Check modal
stacking while other windows are open and listener cleanup after closing LTDE.

Copy/move progress counts files and folders recursively across the selection,
including empty folders. The counting pass runs before copying. Each successful
file copy or completed folder advances the counter; failed/skipped entries do
not. A move removes its source only after the entire selected tree copies
successfully, as before.

The file-conflict dialog includes **Apply to all (Replace / Skip)**. When
checked, Replace or Skip is reused for subsequent conflicts in the current
copy/move operation, including nested files. A new operation starts unchecked.
Rename still requests an individual name, and Cancel stops the operation.
Existing type-conflict and move-safety checks remain in effect.
