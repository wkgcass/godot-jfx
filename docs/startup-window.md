# JavaFX startup window

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


The VFX Demo sets `javafx.godot.startupWindow` before JavaFX starts the host automatically. Its default is `logo`; ordinary applications default to `hidden`.
The native window stays hidden while the engine starts.
The first JavaFX window requested with `show()` becomes the startup window:
its current size, position, title and decorations are used for the Godot logo.
The host draws an opaque logo layer over that window, displays it for at least
one second, then fades its background and image out linearly over 0.5 seconds.
The fade starts only after the first JavaFX presentation completes.
Slow initialization can therefore extend the logo beyond one second.
Application input is withheld for this window while the startup layer is active;
window close requests remain available. Later shows do not repeat the logo.
Hiding or destroying the startup window cancels its pending startup display.

Use `scripts/run-vfx-demo.ps1 -NoGodotLogo` or `scripts/run-vfx-demo.sh --no-godot-logo` to select `hidden`. The first completed JavaFX frame reveals the application. Applications can pass `-Djavafx.godot.startupWindow=hidden|normal|logo` before the JAR or main class. The logo uses Godot's built-in splash image centered at its original size.

## Validation

Build the shared engine, SDK and platform JARs, then run:

```powershell
.\scripts\test-startup.ps1
.\scripts\test-startup.ps1 -RenderThread safe
.\scripts\test-startup.ps1 -Driver opengl
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
`agentdir/logs/startup-<mode>-<driver>-<thread>`; the logo readback is
`artifacts/reference/startup-logo.png`. Require `STARTUP_PASS` and no errors.
