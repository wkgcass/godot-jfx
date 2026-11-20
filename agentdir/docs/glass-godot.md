# glass-godot — historical verification

## Drag and resize at 2× DPI

Default synthetic mobile/separate and GL/safe runs pass the exact drag/resize
path checks after this change. At that stage the physical Robot branch was compiled but not run. A later
authorized mobile/separate Robot run passed drag and resize assertions
(`physical_drag-mobile-separate-robot.log`, both Java and Godot PASS markers).
This covers the tested 2x-DPI desktop path, not other displays or injected
failure/timeout cleanup.
