# Start menu

Start uses TGL Frames, Text, Buttons, an InputField, and a ScrollFrame. It opens
above the taskbar with `LTDEv1` reading from top to bottom along the blue strip.

All installed `.app` directories are listed alphabetically by manifest name.
The app list shows up to twelve rows and scrolls to the rest. Apps are rescanned
when Start opens. The **Find** field sits below the app list, above **Shut Down...**.
Click it, type a name, and press Enter to filter; matching
ignores case and also checks the app path. Clear the field and press Enter to
restore the full list. Click a result to launch it.

Click outside or press Escape to close. **Shut Down...** opens a TGL-based power
menu with Exit to Shell, Restart LTDE, Shut Down Computer, Restart Computer, and
Cancel. Both popups use managed modal overlays and restore the desktop on close.

Startup progress follows completed initialization stages. `[splash] delay` in
`core.conf` now controls one pause at completion, rather than one pause per stage.
`delay=0` adds no pause; `enabled=false` skips the splash and its pause. Loading
and rendering still take their normal execution time.
