# My Computer

Open **My Computer** from Start, or use `run mycomputer.app` in CMD.
The 44-column window shows LTDE/OpenOS versions, Lua architecture, installed
and free RAM, display resolution/depth, uptime, and a scrollable component list.
Each component row contains its type and the first eight address characters.

Refresh updates all values. Attaching or removing components also refreshes
the view. There is no polling timer. Close and LTDE shutdown clean up the window
and its controls. The application uses system mode.

Architecture and component enumeration follow the OpenComputers APIs:
https://ocdoc.cil.li/api:computer and https://ocdoc.cil.li/api:component.
