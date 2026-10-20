# Redstone Control

Open **Redstone Control** from Start or use `run redctl.app`.
The 46-column window provides Normal and Bundled tabs, a redstone-card selector,
and a side dropdown covering Bottom, Top, Back, Front, Right and Left.
These sides are relative to the computer's orientation, not world directions.

Normal shows the selected side's input and output. Bundled shows all 16 color
channels in a scrollable list; select a channel before pressing **Set output**.
The prompt accepts a non-negative integer (up to 2147483647). Vanilla redstone
uses 0–15; bundled/modded ranges depend on the connected hardware (often 0–255).
The displayed output is read back from the component after writing.

Only Set output writes to hardware, and it changes only the selected side and
channel. Opening the app, selecting a card or side, switching tabs, refreshing,
and closing do not reset outputs. Hardware errors are shown in a dialog.
Unsupported bundled mode and missing/disconnected cards have an unavailable
view; Refresh and component-change events rescan the available cards.

Readings refresh on redstone events and every 0.75 seconds while idle. The UI
redraws only when values or selection change. No separate timer or listener is
installed; window controls are disabled and removed on close/shutdown.

API references:
- https://ocdoc.cil.li/component:redstone
- https://ocdoc.cil.li/api:sides
- https://ocdoc.cil.li/api:colors
