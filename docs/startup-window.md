# JavaFX startup window

On Windows, `scripts/run-vfx-demo.ps1` sets `GODOT_JFX_STARTUP=logo` before
starting Godot. The native window stays hidden during engine and JVM startup.
The first JavaFX window requested with `show()` becomes the startup window:
its current size, position, title and decorations are used for the Godot logo.
The host draws an opaque logo layer over that window, displays it for at least
one second, then fades its background and image out linearly over 0.5 seconds.
The fade starts only after the first JavaFX presentation completes.
Slow initialization can therefore extend the logo beyond one second.
Application input is withheld for this window while the startup layer is active;
window close requests remain available. Later shows do not repeat the logo.
Hiding or destroying the startup window cancels its pending startup display.

Use `scripts/run-vfx-demo.ps1 -NoGodotLogo` to set
`GODOT_JFX_STARTUP=hidden`: startup stays hidden until the first JavaFX frame is
ready, then the application appears directly. The launcher restores the previous
environment values when it exits. `-Smoke` can be combined with either mode.

Other launchers can set the same environment variable **before launching Godot**.
With the variable absent, existing Godot startup and test behavior is retained.
These modes are for a Windows game process hosting JavaFX; the Godot editor UI
is excluded. They are implemented by the Windows display server and JavaFX host,
so an application does not need VFX-specific startup code. The logo reuses
Godot's built-in splash image; it is not a separate native window. Like the
native default splash, the full image is displayed at its original pixel size
and centered on integer pixels, without scaling. Small windows clip the image.

## Validation

Build the source Editor with `build-windows.ps1 -Target godot-editor
-WithJavaFXModule` and the JFX SDK, then run:

```powershell
.\scripts\test-startup.ps1
.\scripts\test-startup.ps1 -RenderThread separate
.\scripts\test-startup.ps1 -Renderer gl_compatibility
.\scripts\run-vfx-demo.ps1 -Smoke -NoGodotLogo
```

The independent fixture exercises both modes, delays the first JavaFX frame,
hides and reopens the primary Stage, and opens another Stage. Additional cases
hide the window before its first frame and reopen it after the logo deadline
to verify cancellation without a delayed show or a repeated logo. It checks the
minimum logo and fade durations, a blended GPU frame during the fade, completion of the first frame before reveal, GPU pixels
for the logo backdrop and application content, and a single logo count.
It samples visible Godot HWNDs every 20 ms to reject the initial validation
window. This sampling cannot exclude visibility changes shorter than 20 ms;
GPU readback also does not prove physical monitor presentation timing.
No physical keyboard or mouse input is generated. Logs use
`artifacts/logs/startup-<mode>-<renderer>-<thread>`; the logo readback is
`artifacts/reference/startup-logo.png`. Require `STARTUP_PASS` and no errors.

Checked on Windows x64 on 2026-11-12: source Editor build; normal logo/hidden
cases on mobile/safe, mobile/separate and gl_compatibility/safe; both
cancellation cases on mobile/safe; VFX Demo smoke with and without the logo;
and the existing native-window pixel test on mobile/safe with startup mode
unset. The release template was not rebuilt in this check.

The 0.5-second fade is checked on mobile/safe, mobile/separate and
gl_compatibility/safe using timing assertions and a blended GPU readback
(`artifacts/reference/startup-fade.png`). The full startup runner still catches
an empty native window title in a later no-logo lifecycle case; that existing
visibility failure is not resolved by the fade change.
