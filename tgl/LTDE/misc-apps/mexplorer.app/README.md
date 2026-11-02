# MExplorer

An optional AE2 ME network client for LTDEv1. Requires TGLv9, tgl-ui, and an
OpenComputers Adapter connected to an ME Interface or Controller. ME import/export
bus components are also listed when available. The window is 72x22 characters
and fits a Tier 2 desktop. Large networks benefit from more RAM.

Copy the whole `mexplorer.app` folder into `/ltde/apps`. Open MExplorer from Start,
or run `run mexplorer.app` in CMD. It runs in trusted system mode, like the other
LTDEv1 apps.

If there is one ME component, it connects automatically. With several components,
use File > Connect to choose an address. Changing connections clears the loaded
inventory but keeps this session's crafting requests, each with its source address.

- **Overview:** compact energy readings with a green storage bar, input/usage/idle
  consumption, and busy/total CPUs with their own bar.
- **Items:** names, quantities and craftable status. Search matches labels and
  registry IDs locally. Sort by name or quantity; Details shows the selected item.
- **Fluids:** names and quantities in mB, with the same search and sorting controls.
- **Crafting:** known recipes and their output batch sizes, including items not
  currently stored. Select Craft, enter a quantity, then choose Automatic or a
  named CPU. The chooser refreshes CPU data before opening. Unnamed CPUs are
  listed with numbered display labels; these are not names AE2 can select.
- **Requests:** switch from the Crafting page to track this session's submissions.
  States are Planning, Running, Complete, Canceled and Failed. The footer counts
  completed requests without inventing an individual crafting percentage.
- **CPUs:** names, crafting storage in bytes, co-processor counts and busy state.

Click to select a row. Use the scrollbar, mouse wheel, arrows, Page Up/Down or
Home/End to navigate. Search applies after Enter or leaving the field. F5 or
Refresh reloads the current view. Selection and scroll position are retained
where the same entry can be identified after refresh.

Power, CPUs and submitted requests poll every two seconds; View can disable this.
Item, fluid and recipe lists refresh manually to avoid repeatedly loading large
inventories. A failed list refresh keeps the last successful data and marks it
STALE. API errors appear in dialogs or the status line.

Refresh progress uses the bottom bar instead of opening a progress dialog. The
bar is reserved for operations; energy is displayed only in Overview. Connect
and Export are in File, rather than duplicated along the bottom.

## CPU names and NBT

AE2 does not automatically name crafting CPUs. Rename one block from each CPU
in an Anvil (or with AE2's Inscriber), then place it back in that CPU. Give each
CPU a distinct name and refresh MExplorer. Standard OC selects a CPU by that
name; unnamed CPUs can only be chosen automatically. Display labels such as
`CPU 1 (unnamed)` distinguish rows but do not change AE2 names.

Select an item or recipe and press View NBT for a scrollable, read-only view.
MExplorer decodes ordinary and gzip-compressed binary tags without a Data Card,
and shows exposed lore, enchantments and other supported metadata. Full item
tags require `allowItemStackNBTTags` in the OpenComputers configuration; when
they are unavailable, the viewer explains that restriction. Refresh after
changing the server setting. Binary decoding is limited to 32 KiB and 4096
nodes, with display/depth limits, to avoid exhausting a small computer's RAM.

Cancel request attempts the component's cancellation method. Standard 1.7.10
integration may not provide it; MExplorer reports that error. Closing the app
does not cancel crafting, but the tracking handles are not restored on reopening.
Up to 64 requests are retained; completed/canceled/failed entries are retired
when needed to make space. Tagged or ambiguous items should be requested from
the Crafting recipe list, rather than guessed from inventory entries.

## Export

File > Export inventory offers Items, Fluids or Craftables as CSV, and a full
snapshot as a Lua file. It exports the loaded data, including stale entries;
missing lists are loaded first. Refresh first if you need a new inventory count.

CSV contains capture time, component address and the relevant item/fluid fields.
For craftables, `quantity` is the recipe's output batch size. Full snapshots
include all three lists, power readings, CPUs, tracked requests, per-list capture
times and recorded errors. They contain plain data, not component proxies or
crafting handles. The Lua file returns a table and has `format="mexplorer-1"`.

Enter a destination path and confirm before replacing a file. Exports stream
rows to a temporary file, show real row progress and allow cancellation. The
destination is replaced only after writing succeeds. A single blocking ME call
shows a loading status; it cannot offer a meaningful percentage or cancel until
the component call returns.
