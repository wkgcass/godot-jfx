# VFX source build and Intro smoke

Launch the full interactive Demo with `java -jar artifacts/vfx/libs/vfx-demo.jar`.
Build it on the target platform with `scripts/build-vfx.ps1` or `./scripts/build-vfx.sh`
after the shared Godot library and Media-enabled SDK are available. The JAR contains
the original Intro application, its pages, images, Godot shader controls and
platform-native libraries. Both run scripts select this JAR by default. Their driver options pass the same JVM property. Use `./scripts/run-vfx-demo.ps1 -Driver d3d12 -Smoke` on Windows or `./scripts/run-vfx-demo.sh --driver metal --smoke` on macOS.
On Windows, the Demo defaults to D3D12. To choose another driver, run
`java "-Djavafx.godot.driver=vulkan" -jar artifacts/vfx/libs/vfx-demo.jar`
or pass `--driver opengl` after the Demo JAR name for OpenGL. The Demo CLI takes
precedence over the JVM property. JavaFX starts the host automatically after the Demo configures the driver and startup window.
On macOS, omit the property for the Metal default or use
`java -Djavafx.godot.driver=metal -jar artifacts/vfx/libs/vfx-demo.jar` to request Metal explicitly.
To check startup and shutdown, add `--smoke` to the JAR command. This starts the
same Intro UI, checks the visible Stage and its menu, then sends a close request.
[Windows build](build-windows.md) · [macOS build](build-macos.md).

The host uses Viewport + safe on mobile or OpenGL. Dated RD/separate results
below describe prior builds, not current backend choices or current-build
acceptance. See [acceptance-status.md](acceptance-status.md) for the latest coverage.

Menu animation/ripple performance can be measured without physical input using
`./scripts/profile-vfx-menu.ps1`; see [menu profiling](frame-benchmark.md#menu-redraw-and-ripple-profiling).

`run-vfx-demo.ps1` passes two engine pacing switches through: `-DisableVsync`
switches every window's swapchain from FIFO to immediate presentation
(windowed output stays DWM-composited, so there is no tearing) and implies
`-MaxFps 60` to keep the loop CPU-paced; `-MaxFps <n>` overrides that value,
and can also be used alone with VSync still enabled. The host's one-shot
`check_vsync_pacing` fallback leaves both manual settings untouched.

## Linux Wayland page captures on Intel Arc B390

The release with engine `ace7814e1e52…` and Toolkit class `ab7b90061449…` captured all 35 Intro pages per driver with Fusion animation frozen. Each capture was 2560×1600 at scale 2. For Vulkan and OpenGL, 33 complete images per driver matched the preceding same-driver captures pixel for pixel. Pages 18 and 19 contain generated table data. Both runs ended with zero host-owned resources. A fresh native JavaFX ES2 run supplied 35 reference images at the same size. The median normalized RGB errors against ES2 were 0.000638 on Vulkan and 0.0000153 on OpenGL. Full-frame differences and the paired image sheets are in `wayland-toolkit-publication-QI3DyI7e/frozen-pages/` under the LCD publication archive.

With the normal Fusion animations enabled, the same release completed both 35-page runs and released all host-owned resources on exit. Page images used the same 2560×1600 dimensions and the native ES2 reference was captured at the same scale and logical content size. Across all pages, the median normalized mean absolute RGB error in the content region was 0.000818 for Vulkan and 0.0000153 for OpenGL. The largest difference on each driver was on the randomized table on page 18 (0.01184 and 0.01133 respectively). On both drivers, 26 of 35 content regions matched the corresponding frozen capture pixel for pixel. The two comparisons and the crop coordinates are in `normal-pages/` in the same release archive.

The regular Linux build with engine `906cf6d68fa4…` completed all 35 Intro
pages with Fusion animation frozen on Vulkan and OpenGL. Both runs saved
2560×1600 images at scale 2 and reported zero host-owned resources on exit.
In the normal content comparison region, 33 of 35 pages per driver matched
the previous `da0a4ee0ac9a…` build pixel-for-pixel. The other two pages
contain regenerated table data (18 and 19). The per-page channel errors,
library hashes and comparison images are in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/frozen-pages/`.

The November 25 full regression on engine `da0a4ee0ac9a…` produced 35
scale-2 captures per driver at 2560×1600 and released all host-owned
resources on exit. Against engine `20e839a2fcf2…`, each driver reproduced
26 of 35 content regions exactly. The largest changes were the regenerated
tables on pages 18 and 19. Every other page had a normalized mean absolute
RGB difference below 0.0002 on each driver. The separate GTK/ES2 comparison
had a median error of 0.01184 on Vulkan and 0.01188 on OpenGL. Its largest
difference was the illustrated background on page 32. The numerical
comparisons and contact sheets are in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/vfx-visual/`.

The source-built engine `20e839a2fcf2…` completed all 35 Intro pages on
Vulkan/mobile and OpenGL/gl_compatibility. Each case produced 35 new
2560×1600 PNGs at scale 2 and reported zero host-owned resources at exit.
Against the previous package on the same driver, 26 of 35 content regions
were pixel-identical on each driver. The two largest differences were the
tables on pages 18 and 19, which generate fresh cell values at startup.
For every other page the normalized mean absolute RGB difference stayed
below 0.0001 on both drivers.

Against native GTK/Prism ES2, the median content difference was 0.01184 on
Vulkan and 0.01188 on OpenGL. Page 32 had the largest difference on both
(0.09281 and 0.09244). Its illustrated background in the reference appeared
about 4.8% larger along both axes. Matching eight background patches and
checking six separate patches at quarter resolution reduced their median
difference from 0.103 to 0.012 on each driver. This diagnostic only measures
the illustration. The original page scores and contact sheets use the
uncorrected images. The ES2 capture also shows different navigation placement.

The contact sheets, previous-package comparisons and background measurements
are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/verified-release-lZUp7QMq/restart-suite-n8jhXQQK/vfx-visual/`.

## Ripple Effect in the Intro menu

The initially unchecked `Ripple Effect` checkbox follows `Blackhole Effect`.
It is available only when `FXUtils.isPrismGodot()` succeeds. The ripple effect
attaches to the main Demo Scene root, so the title bar, menu drawer, content and
bottom navigation all participate. Separate native Stage windows are unaffected.
It can run together with the content-scoped blackhole effect; either checkbox
can be switched off independently.

A Scene event filter observes left-button presses without consuming them. Each
press spawns a ripple at the target-local normalized pointer position; right and
middle buttons do not spawn ripples. There is no automatic/random spawning.
An AnimationTimer updates up to sixteen GPU ripple slots using monotonic time.
Each drop expands outward at 0.32 times the window height per second and fades
over 3 seconds. Active offsets add together; when all slots are occupied, further
presses do not add a ripple until a slot expires. The timer stops when no drops
remain and restarts on the next accepted press.
No per-frame texture upload, CPU image processing or physical pointer polling
is used. The shader is embedded as Java 11-compatible strings in
`RippleEffectControl.java`, with explicit float uniforms rather than shader arrays.
It adapts the supplied water shader's primary/secondary waves, Gaussian wave
width (0.025), wavelength (0.035), strength (0.012), decay power (1.3), and
component-wise displacement cap (0.035). Screen UV/sampling is replaced by
node-local UV/input-texture sampling; array entries are expanded into sixteen
individual vec4 uniforms. Zero-offset pixels bypass sampling displacement, and
the original output alpha is preserved, including window corners.

Disabling restores the previous root effect and stops the timer. Re-enabling
starts with no active drops. Window hiding removes the event filter and cleans
up the controller. Controls retain
their original JavaFX hit-testing positions while their rendered pixels move.

```powershell
.\scripts\build-vfx.ps1
.\scripts\test-vfx-ripple.ps1
.\scripts\test-vfx-ripple.ps1 -Driver opengl
.\scripts\test-vfx-ripple.ps1 -NativeD3D
```

The fixture checks the actual menu, root attachment, independent blackhole toggle,
and native-backend absence. Synthetic clicks on a test grid check idle stability,
left-only spawning, unconsumed events, correct positions and overlapping drops,
visible GPU distortion and expansion, transparent corners, expiry, disabling,
resize and cleanup on hiding. The Godot
wrapper checks window/resource teardown. Logs and snapshots use the
`agentdir/logs/vfx-ripple-*` and `artifacts/reference/vfx-ripple-*` prefixes.
These tests use no real mouse/keyboard input and are not a frame-rate benchmark.

## Blackhole Effect in the Intro menu

The Intro drawer includes an initially unchecked checkbox labeled
`Blackhole Effect`. Open the top-left menu and scroll to the bottom.
Checking enables the effect; unchecking turns it off.
This is an intentional addition to the Demo, not a change to VFX library controls.

In the full Linux JAR on private labwc, a Wayland virtual pointer scrolled
the Intro drawer, clicked the checkbox, dismissed the drawer and moved the
lens back and forth over the welcome text. The pointer sent 240 motion
steps during each four-sweep pass. With the checkbox off, the sampled text
region remained identical. With it on, the same region showed 236 sampled
changes on Vulkan and 221 on OpenGL. A centered lens changed 11,391 and
10,611 pixels by at least 3/255 respectively in a 405×80 crop. Turning the
effect off restored every pixel in that crop on both drivers within the same
tolerance. Both standalone processes exited through Alt+F4 with code zero.
Screenshots, click traces and sampler timings are in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-release-MIuxEnnx/lens-jar-input-yOW44Wds/`.

The control applies the public `javafx.scene.effect.GodotShaderEffect` to the
Demo content VSceneGroup node. Only its pages are shaded; the window title bar,
menu drawer and bottom navigation remain unaffected. Mouse move, drag and press
events update the center in target-local
coordinates; resize updates the input extent. The shader samples the GPU input
texture using the user-supplied pure lens template, with no accretion disk,
photon ring, black core or time animation. The default lens and influence radii
are 0.18 and 0.33 times the target height (1.5 times the supplied template);
aspect correction keeps them circular.
Positive distortion moves sampling toward the center, with a soft outer warp.
The default distortion strength is 0.13341541, making the central inverted region
radius 2.5 times its previous size at strength 0.045, with the other parameters
unchanged (the inversion boundary satisfies distance = total displacement).
Outside the influence radius sampling is unchanged. Sampled alpha follows the
distortion, and the VSceneGroup clip keeps output inside its boundary. Hit testing continues to use the original JavaFX layout.

The pointer is tracked across the Scene, including outside the Demo content.
A lens centered outside the VSceneGroup still affects any content within its
influence radius; output remains clipped to the VSceneGroup. Leaving the Scene
temporarily removes the effect; reentry restores it if selected.
Turning it off restores the previous target effect. Window hiding detaches event
filters and the resize listener. No animation timer is needed. The shader uses
node `UV`/`TEXTURE` and the target extent instead of screen sampling, so the same
source uses the Viewport path. No Robot, screen capture or CPU frame
upload is used by the feature. Additional native Stages are independent windows
and are not shaded by the Demo content effect.

The shader is the `SHADER_SOURCE` constant in `BlackholeEffectControl.java`
beside `IntroFXMain.java`, using ordinary concatenated strings compatible with
Java 11. No shader resource file is loaded. The local build uses JDK 25.
The public extension is resolved lazily to avoid a compile-time dependency for
upstream JavaFX builds. `FXUtils.isPrismGodot()` reflectively reads the public
boolean `javafx.application.GodotRuntime.PRISM_GODOT_ENABLED`, set only after
Godot Prism initializes successfully and cleared on disposal. Missing classes,
missing/inaccessible fields, incompatible field types, and false values return
false. The first result is cached, including false: call it after JavaFX startup;
a call before startup will cache false for that class loader's lifetime. No
internal JavaFX exports or `prism.order` assumptions are needed.
The Demo only creates the control when this check succeeds; on native D3D and
ordinary JavaFX the control is absent.

```powershell
.\scripts\build-vfx.ps1
.\scripts\run-vfx-demo.ps1
.\scripts\test-vfx-blackhole.ps1
.\scripts\test-vfx-blackhole.ps1 -Driver opengl
.\scripts\test-vfx-blackhole.ps1 -NativeD3D
```

The fixture uses the actual Intro menu and synthetic JavaFX events, never real
mouse/keyboard input. GPU snapshots check visible changes, stationary-pointer
stability, pointer movement,
unchanged pixels outside the radius, alpha at a window corner, restoration after
disable, and mapping after resize. An edge marker verifies distortion inside
the group when the pointer is outside it, while title bar pixels remain unchanged.
It also checks Scene exit/reentry and final host
resource cleanup. Captures are under `artifacts/reference/vfx-blackhole-*` and
logs under `agentdir/logs/vfx-blackhole-*`. The Windows regression matrix runs
the pixel checks on Godot D3D12, Vulkan and OpenGL. The separate `-NativeD3D`
case checks that the Godot-only control is absent on the standard JavaFX pipeline.
See [current Windows results](acceptance-status.md#validation-evidence) for
the per-driver outcome.

2026-11-12 validation of the pure lens shader and checkbox: the source VFX build
and the complete fixture pass on
mobile/safe with RD off and on, plus OpenGL/safe. GPU captures were
inspected. Native D3D also passes the absent-control check. No Runtime or
physical-input acceptance is claimed for this addition.

2026-11-03 animation graph: `test-vfx-animation.ps1` exercises original page 23
through host clicks. It selects a/b, plays to b, then selects a/d and soft-stops
before d. The observer checks actual Circle movement and endpoint, selection
indices, button enabled states and their reset. Host readbacks require red pixels
while playing and final cleanup requires zero owned resources. OpenGL/safe,
Vulkan/separate and packaged Runtime Vulkan/separate pass. A GL test timing assumption initially
missed intermediate frames; sampling now starts immediately after Play without
changing the original animation. The capture was inspected. This is bounded
interaction/model-motion/render-visibility coverage, not a frame-rate measurement.

The motion check measures the center of the original red circle in two GPU
readbacks from distinct presentations and requires at least 20 pixels of
displacement. The probe finds the circle on an eight-pixel grid, then measures
the filled red area around that hit. On B390 a captured circle covered 288
red pixels but only four lay on the original fixed grid. Counting all grid
offsets keeps the five-hit check independent of the circle's position.

2026-11-03 LoadingStage interaction: `test-vfx-loading.ps1` selects original page
26 and uses host clicks to open its LoadingStage and dismiss the completion alert.
It observes the original TaskManager/100-item flow, changing item labels,
monotonic progress reaching 1.0, automatic loading-window closure and the original
"loading complete" message. Loader and alert must have distinct independent
native identities; final window/presentation drain and zero owned resources are
required. OpenGL/safe, Vulkan/separate and packaged Runtime Vulkan/separate pass.
The loading/complete GPU captures were inspected. Run with `-Driver`,
`-RenderThread` and optionally `-Runtime`; outputs use the `vfx-loading-` prefix.
`-Cancel` additionally clicks the original loading-window CloseButton before
completion and requires the localized cancellation alert. It waits 500 ms for
in-flight work to settle, clicks Ok, then observes one second without progress
changes or new windows. OpenGL/safe, Vulkan/separate and packaged Runtime
Vulkan/separate pass this branch with independent native windows and zero final
owned resources; the Runtime cancellation capture was inspected. Cancel outputs
have a -cancel suffix. Injected item failure, physical input and animation
smoothness are not established by these tests.

The [2026-11-03 full-page recheck](../agentdir/docs/progress.md#opengl-full-page-recheck)
records the 35-page OpenGL run and its D3D comparison.

2026-11-03 long-table coverage: `test-vfx-scroll.ps1` uses original Intro page 19.
Host input drags horizontally 250 logical pixels, wheels to the 50-row table's
vertical bottom, wheels back to the top, then restores horizontal position. It
checks existing container transforms and bottom geometry, visible pixel changes,
sampled left/right clip boundaries, normal drain and zero native resources.
OpenGL/safe, Vulkan/separate and packaged Runtime Vulkan/separate pass at scale 2;
the bottom capture was inspected. Artifacts use the `vfx-scroll-` prefix. These
remain GPU captures and injected input, not desktop/physical-input acceptance.

2026-11-03 interaction coverage: `test-vfx-table.ps1` observes original Intro page
18 (`_06bVTableViewDemoScene`) without changing its business handlers or data.
Host mouse/key input adds a row (10 to 11), selects a row, focuses its TextField,
uses Ctrl+A and Unicode character input to enter `Godot测试`, moves focus to another
TextField to commit, sorts bandwidth ascending and descending, and deletes the
selected data object (11 to 10). The observer retrieves the table captured by the
original Add button solely to inspect data, selection and ordering. Every action
must change the expected state before the next one is published after layout and
a render-job fence. The first fixture incorrectly assumed clicking the non-focusable
column header would commit editing; the corrected fixture explicitly moves focus.
The table closes normally and the host must drain and release all native resources.
OpenGL/safe, Vulkan/separate and packaged Runtime Vulkan/separate pass at 200% scale.
Captures of committed Chinese
text and sorted rows were inspected. This is injected character input, not native
IME composition, and does not cover multi-column sorting, horizontal scrolling or
all table variants. Run `scripts/test-vfx-table.ps1` with `-Driver`, `-RenderThread`
and optionally `-Runtime`; logs and PNGs use the `vfx-table-` prefix under artifacts.

2026-11-02 native-window update: VfxDialogProbe now uses the target JavaFX window's
Glass identity and local coordinates. Each dialog is rendered/clicked in its own
native Godot Window; the test no longer requires embedded layers inside the root.
OpenGL and Vulkan separate-thread mode pass the original number-choice dialog, Optional[2] result alert and
SimpleAlert.showAndWait flow. Captures now show each target window's GPU viewport,
not the whole root with embedded dialogs, and are not OS screenshots. The Demo
business handlers are unchanged. Native modal HWND disable/restore behavior is
separately covered by test-modals.ps1 in GL/Vulkan separate-thread mode.
The observer allows 60 seconds for target readiness, then 30 seconds for its
action (180-second host bound). Readiness uses two unchanged layout observations
followed by a queued render job and an FX-thread check that the target is still
current. This replaces an arbitrary 20-pulse wait that timed out on slow pulses
even with unchanged coordinates. Each target's actual IsWindowVisible state and
distinct native identity are checked before injection. Final presentation/native
window draining and zero resources are required. The visible-stage3-timeout and
fixed-pulse-wait logs retain the failure/diagnostic evidence. Complex-page pulse
performance remains unaccepted; injected failure shutdown has separate coverage.

Run from the workspace root:

```powershell
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-vfx.ps1
.\scripts\test-vfx-intro.ps1
.\scripts\test-vfx-intro.ps1 -Driver d3d12
.\scripts\test-vfx-intro.ps1 -AllPages
.\scripts\capture-vfx-reference.ps1
```

The separate Gradle project in scripts/vfx-build uses the source-built SDK in
jfx/build/sdk, the repository's Gradle wrapper and JDK 25. It compiles the original
VFX main module and all test sources without changing VFX business code. Maven
Central supplies VFX's declared third-party dependencies; no binary JavaFX SDK
is downloaded or substituted. The upstream JavaFX 11 / Gradle 7 build is preserved.

The build writes compiled classes, resources and dependencies under `artifacts/vfx/`.
For interactive use, `java -jar artifacts/vfx/libs/vfx-demo.jar` runs
`VfxDemoMain`, which initializes the packaged engine and calls the original
`io.vproxy.vfx.intro.IntroMain`. The scene tests use the published platform
JARs and compiled observers on the Java classpath. Logs are
agentdir/logs/vfx-build.log and vfx-intro-<driver>.log. Captures are
artifacts/reference/vfx-intro-<driver>.png and vfx-intro-next-<driver>.png.

Both GL compatibility and Vulkan mobile pass startup, the application's own
Next navigation (411 changed central samples on GL), one native window and
normal close. The inspected welcome and VStage introduction pages show text,
custom title bar and navigation controls. Welcome-page host resource count is
95; this is not a leak test or driver memory measurement. These are GPU captures,
not OS screenshots. Input is injected through Godot Input.parse_input_event,
not physical mouse input. JNativeHook emits a JDK native-access warning at close.

`-AllPages` uses a test subclass of the original IntroFXMain and the unchanged
VFX scenes. Its observer reports the current scene through the native title
only after a queued render job. Navigation still uses the Demo's Next button
through host mouse input. Fixed-delay clicking proved insufficient on LCD-heavy
table pages; it could miss pages and capture an older frame. The observer makes
those failures visible rather than counting clicks as visited pages. Captures
and a completion manifest are saved in artifacts/reference/vfx-pages-godot-<driver>.
All-page logs use vfx-intro-<driver>-all-pages.log. The two-page smoke stores its
manifest in vfx-smoke-godot-<driver>, so later smoke runs cannot replace the all-page
completion record. Earlier runs used a shared log/manifest location.

The reference helper renders all 35 original scenes using this SDK's Windows
D3D backend. It selects scenes directly for reference capture, so it is not an
input test. scripts/compare-vfx-pages.py (Python with Pillow) produces a paired
contact sheet and per-page RGB differences; it rejects incomplete capture runs.
Random table data, timestamps, animation timing and navigation-button state mean
the differences are visual triage, not an automatic correctness threshold.

The current GL and Vulkan 35-page runs pass and both paired sheets were inspected.
This covers navigation and visible content, not each button or modal dialog.
Older separate-mode completion and render-worker shutdown fixes are historical;
those adaptations have been removed. Current navigation evidence uses Viewport
with safe threading.
OS screenshot capture was attempted with the computer-use skill but initialization
failed with `Module not found: @oai/sky`; these artifacts remain GPU captures.

The test does not establish correctness of every Demo page, native dialogs,
clipboard, IME, media, popup stages, physical input, DPI or prolonged animation
and resource stability. Continue page-by-page visual and interaction acceptance;
do not treat this smoke result as completion of M6 or the overall objective.

## Windows Demo logs

Run `run-vfx-demo.ps1` with PowerShell 7.4.1 or later (`pwsh`). The launcher
records Java output and warnings in the Demo log. It checks the native exit
code, the close marker and logged application errors before reporting success.

## Startup window

`run-vfx-demo.ps1` launches the Demo JAR. The engine displays the Godot logo inside
the first JavaFX window for at least one second, until the first frame is ready.
Use `-NoGodotLogo` to reveal the prepared application directly. Subsequent
windows do not repeat the logo. See [startup behavior and tests](startup-window.md).

## macOS arm64

The macOS runners are `scripts/test-vfx-*.sh` with `--driver/--render-thread`
arguments matching the PowerShell switches. The interactive launcher is
`scripts/run-vfx-demo.sh` (`--smoke`, `--driver`, `--disable-vsync`,
`--max-fps`), equivalent to `run-vfx-demo.ps1`, and the VFX classes are built
and packaged with `./scripts/build-vfx.sh` instead of
`build-vfx.ps1`. VStage emulates maximize on macOS
with manual bounds (screen minus the 24pt menu bar) instead of the native
maximize, so `tests/reference/VfxWindowControlsProbe.java` reads
`VStage.isMaximized()` and `tests/godot/vfx_window_controls.gd` expects a
windowed native window matching screen bounds minus 24pt on macOS; the Windows
assertions are unchanged. `tests/godot/vfx_table.gd` sends Cmd(Meta)+A for
select-all on macOS, mirroring the existing `fxml.gd` mapping. The Robot group also runs table scrolling with
`GODOT_JFX_DRAG_MODE=robot`, `test-hover-flicker.sh --robot`, and the
Intro hover probe with real mouse input.

On 2026-11-22 the rebuilt standalone JAR passed the isolated JDK 25 launch
on both Metal and OpenGL on the Apple M1. Each run checked the loaded Godot
dylib against its SHA-256 inside the JAR. Both `run-vfx-demo.sh --smoke`
runs also closed cleanly.

The all-page fixture navigated all 35 Intro pages on each backend. Each run
produced 35 distinct 1280×800 viewport captures at display scale 1 and
reported zero host-owned resources after shutdown. The full captures and
`run.json` are under `agentdir/logs/macos-planar-final-NonRobot/` in
`264-test-vfx-intro/reference/vfx-pages-godot-metal` and
`266-test-vfx-intro/reference/vfx-pages-godot-opengl`. The contact sheets
are in `agentdir/artifacts/macos-planar-final-demo/pages-{metal,opengl}.png`.

With both Metal and OpenGL, the standalone JAR and the hover diagnostic displayed the welcome page, opened the menu and navigated to the VStage page. The window captures for the three steps are in `agentdir/artifacts/macos-5a65cc6-demo-acceptance/{jar,hover}-{metal,opengl}/`.

Earlier desktop captures from the interactive JAR show the welcome page, open
menu and selected VStage page. They are archived in
`agentdir/artifacts/macos-751bac7/reference/vfx-portable/{homepage,menu,selection}.png`.

## Linux x64 on WSL2

The complete Linux VFX JAR with Godot library `906cf6d68fa4…` ran on a
private labwc desktop at scale 1 with an Intel Arc B390. A Wayland virtual
pointer clicked the Intro menu button and then the cover to dismiss the
drawer, four times each per launch. Each driver ran twice with ordinary
pacing and once with an explicit 120 FPS cap and VSync disabled. The app
received all 48 press/release pairs. Each opening reproduced its settled
menu image in the sampled 360×420 area, each closing restored the initial
pixels, and all six JVMs exited with code zero through Alt+F4. The test
retained the screen grabs, button event times and loaded library digest in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-release-MIuxEnnx/menu-jar-input-CZcigH7P/`. Timing is recorded in
[the frame benchmark](frame-benchmark.md).

The Linux workspace VFX JAR containing engine `da0a4ee0ac9a…` passed all 35 pages with Fusion animation frozen on both B390 drivers on 2026-11-25. Each run saved 35 distinct page files at 2560×1600 and scale 2, then closed with zero host-owned resources. A same-driver comparison against archived frozen captures from engine `a312dd9c27c1…` used the content region from the normal VFX visual comparison. Vulkan matched 33 of 35 pages pixel for pixel. OpenGL matched 31. Pages 18 and 19 displayed different generated table cells with the same row and column layout. On OpenGL pages 31 and 32 differed by at most one 8-bit channel level. The per-page differences and review sheets are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/frozen-pages/`.

The published Linux engine `a312dd9c27c1…` passed full 35-page navigation and the three-page frozen Fusion run on both B390 drivers in isolated Weston. Each full run saved 35 images at 2560×1600, reported scale 2 and closed with zero host-owned resources. Reusing the archived 2× GTK/Prism ES2 reference images, the median normalized RGB error in the comparison region was 0.01184 on Vulkan and 0.01188 on OpenGL. Page 32 had the largest difference on both (0.09281 and 0.09244). The values describe one capture per page with normal Demo animations. Case logs, images, per-page measurements and contact sheets are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/{nonrobot-full/,vfx-visual/}`.

The Linux texture-pool comparison covered all 35 pages on Vulkan and OpenGL. Each driver ran once with ordinary animation and once with Fusion frozen at each pool size. The 512 MiB reference loaded the published JAR. The 256 MiB candidate loaded the diagnostic pool class. Both used the same Godot library and 2560×1600 images at scale 2. On each driver 26/35 animated page pairs and 33/35 frozen page pairs had identical RGB content in the comparison rectangle. The median error was zero in every run. The largest normalized mean absolute RGB errors were 0.01075 and 0.01045 on Vulkan, and 0.01017 and 0.01110 on OpenGL (animated and frozen, respectively). On both drivers the two differing frozen pages were the tables on pages 18 and 19. The comparison images show different cell values and timestamps in the same layout, with a small difference along the page 18 button outlines in the frozen capture. Per-page measurements and the paired images are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/wayland-pool-pacing-SqjQY7q9/visual-256-LnDP79c2/`.

The rebuilt 256 MiB package (`GodotTexturePool.class` prefix `b0774c465b25`) also passed 35-page navigation on each driver and released all tracked host resources on exit. The screenshots were 2560×1600 at scale 2. Against the archived 2× native GTK/Prism ES2 reference, median content errors were 0.01184 on Vulkan and 0.01188 on OpenGL. The largest errors on each driver occurred on the illustrated background of page 32 (0.09281 and 0.09245). Both 35-page contact sheets and per-page measurements are in `agentdir/artifacts/wayland-linux-pool-release-j87Wdjek/vfx-visual/`.

On native Wayland with DISPLAY unset, the complete VFX JAR passed isolated
launch and clean shutdown on both Intel Arc B390 drivers. After fixing the
Wayland startup scale, the actual JAR presented a 2560×1600 Windows client
area for the 1280×800 logical Stage at 192 DPI.

The all-page navigation and three-page frozen Fusion tests passed on Vulkan
(mobile) and OpenGL (gl_compatibility). Each full run captured 35 pages at
2560×1600 and reported zero host-owned resources at shutdown. The OpenGL run
passed the log check after switching IME completion to the active Wayland
protocol. Against the 2× native GTK/Prism ES2 captures, the median normalized
RGB error over all pages was 0.01184 for Vulkan and 0.01188 for OpenGL. The
largest difference on both was page 32 (0.09280 and 0.09243). These are
image comparison measurements. Native GTK initially reported a 1242×752
Scene for a 1280×800 Stage. The reference adjusted the outer Stage to
capture 1280×800 logical content at scale 2. VStage sizes its inner scene
group from the outer Stage, so this comparison includes layout differences
as well as differences in animation and rendering. The reference used
`JAVA_TOOL_OPTIONS=-Dglass.gtk.uiScale=2`. The four case results, page manifests and paired contact
sheets are under `agentdir/artifacts/linux-wayland-regression-NN0563Lp/`
in `intro/` and `visual/artifacts/reference/`.

The Intro calls `GlobalScreenUtils.unregister()` on close. The method checks
VFX's enable records before touching JNativeHook, so an unused hook does not
initialize a global input hook during Wayland shutdown. The last `disable()`
call releases the hook before removing its final enable record.

On private Weston at 2× scale, the regular dialog fixture completed five clicks
and exited successfully on Vulkan and OpenGL. The injected-failure variant
passed on Vulkan. On OpenGL, the process logged a missing texture allocation
and render-target creation failure, then received SIGSEGV before the expected
Java exception. The first return address on the native stack is inside
`RasterizerCanvasGLES3::_render_items`, which copies into a mapped GL buffer.
The Wayland backend now selects a remaining mapped EGL surface before closing
the current one. After rebuilding, the regular dialog and the injected-failure
variant each passed three consecutive OpenGL runs. Each injected run reported
the expected Java exception and completed the host shutdown check. Vulkan
also passed both variants. These results are in `dialog/`, `opengl-2/` and
`opengl-3/` under `agentdir/artifacts/wayland-egl-check-ed9P5d30/`.
Cases 260–263 are in `agentdir/artifacts/wayland-full-GRn6iHqe/tests/`.

The serial Wayland table and Stage reruns passed in all eight driver and fixture combinations. Window controls passed maximize, restoration of the original 400×300 logical geometry, and the minimize request with each driver. Both the default and runtime cases then stopped at the request to restore from minimize. xdg-shell exposes no client operation to perform that restoration. The Robot table-scroll cases require desktop-wide Robot input. The corresponding logs are in `wayland-egl-check-ed9P5d30/window-recheck/`, `wayland-egl-check-ed9P5d30/extra/` and `wayland-drag-source-9QinZ5Mn/robot/`.

On labwc 0.9.3 the original window-controls fixture subsequently passed all
four driver and runtime combinations. Godot requested activation using the
seat event serial and restored the reported mode after the child regained
focus. Each trace contains the minimize request, token request, activation
and the compositor's keyboard enter on the child. The VFX and Godot probes
both completed. The registry, logs and per-case serials are under
`agentdir/artifacts/wayland-activation-aPQfvnC7/`.

The additional `--weston-restore` variant uses the compositor's task switcher
after the child requests minimization. A focus change to the main Stage must
leave the child iconified. A focus change back to the child must restore the
original native geometry, deliver the JavaFX state change, and allow the VFX
close control to finish the fixture with zero host resources. On 24 November all
four Vulkan/OpenGL and default/runtime combinations passed. Protocol traces
and screenshots are in `agentdir/artifacts/wayland-shell-restore-P8ZWu1G3/`.

The packaged JAR also passed a pointer-driven table check in private Weston
at scale 2. The virtual desktop seat clicked the Demo's Next button until the
long-table page appeared, performed three vertical drags and reversals, then
dragged horizontally and back. Each driver received eight press/release pairs
with a total of 256 Wayland motion events during the drags. The row text moved
600 output pixels vertically while the header stayed in place. A horizontal
drag translated the header and the row text together by 400 pixels. Both
applications exited through the VFX close button. The Vulkan screenshots and
protocol events are in `wayland-vfx-table-seat-cgQUmL9v/repeat-vulkan/` and
the OpenGL results in `final-opengl/` under the same archive.

On a private labwc desktop at scale 1, the public JavaFX Robot also drove the VFX table scroll fixture on both B390 drivers. Both runs checked displacement after three sweeps. The physical LoadingStage hover fixture passed its Java event and Godot pixel checks on both renderers. These four runs used a 2560×1800 output, with the compositor placing the stage at (640,333) to match the fixture. The original 1280×720 session lost focus during the table gesture. Per-case logs are under `agentdir/artifacts/wayland-robot-2RIjHyHr/{pilot,vfx-robot}/`.

The abrupt Stage test waits for a distinct child window ID to appear alongside
the main window in the display server before requesting shutdown. The first
Vulkan run failed when it checked the window list during registration. After
waiting for both IDs, Vulkan and OpenGL each passed the exit request and Java
return checks in `agentdir/artifacts/wayland-rebuild-UCYJ3nrm/abrupt-stage/`.

On 24 November the same release completed the three-round navigation soak
on private Weston with both B390 drivers. Each recorded 205 page samples and
zero host-owned resources after shutdown. The table shows private process
memory and host render-target materials at the three returns to page zero.

| Measurement | Round 1 | Round 2 | Round 3 |
| --- | ---: | ---: | ---: |
| Vulkan private memory (MiB) | 1750 | 1882 | 1960 |
| Vulkan target materials | 1604 | 2015 | 2232 |
| OpenGL private memory (MiB) | 2619 | 2951 | 3139 |
| OpenGL target materials | 1549 | 1998 | 2326 |

Long-run memory stability remains open. Cases 280 and 281 in
`agentdir/artifacts/wayland-release-nOfa55Xe/nonrobot/` contain the sample
series, final resource count and process exit status. The preceding release
showed growth at the same checkpoints in cases 017 and 018 under
`agentdir/artifacts/wayland-rebuild-UCYJ3nrm/nonrobot-tail/`.

On the native Wayland release with engine hash `78d43359aab3…`, Vulkan/dzn completed eight 35-page round trips on the B390 and released all host-owned resources on shutdown. Private memory still grew during the second half. The last return added 130 cached materials, including 129 net on previously live render targets. [Eight-round memory measurements](memory-validation.md#eight-vulkan-rounds-on-native-wayland)

## Dragging the custom title bar on Linux

On Wayland, pressing the VFX title bar starts a compositor-managed move. The menu and content keep their own mouse handlers. On a private labwc desktop at scale 1, dragging the packaged VFX window moved its top-left corner from (60, 80) to (230, 190) on both Vulkan/mobile and OpenGL/gl_compatibility. An owned Stage fixture also moved by (170, 110). A separate check constructed an actual VFX `VStage` around an owned JavaFX Stage using the classes from the release Demo JAR. Dragging its custom title bar moved the red content bounds from (781, 301) to (951, 411) on both drivers, with the blue owner's bounds stationary. Each trace recorded the child's `xdg_toplevel.move` request. The before/after desktop images and protocol traces are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/verified-release-lZUp7QMq/restart-suite-n8jhXQQK/owned-vstage-gLGPe6s1/`.


### Linux drawer timing verification

The source-built Intro JAR with the corrected animation timer and Linux Godot drawer cache passed all 35 frozen pages on both B390 drivers at scale 2. Compared with the preceding build on the same driver, 33 of the 35 page regions matched pixel for pixel. The two generated table pages (18 and 19) differed on both drivers, with mean normalized RGB error below 0.011. Each driver released all host-owned resources on exit. Eight actual menu endpoints per driver matched the preceding JAR pixel for pixel within the drawer comparison region. Both rebuilt extra demos passed their Vulkan and OpenGL interactions. The comparison and raw screenshots are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-timeline-release-vJsyDaug/validation/`. See [the animation timing measurements](frame-benchmark.md#vfx-animation-timing-on-linux-wayland).

### Current-source Linux ES2 reference

All 35 frozen Intro pages were captured with native JavaFX GTK/Prism ES2 from the same VFX sources as the content-cache build. The native control used a private display and the B390 D3D12 OpenGL driver. The two Godot captures used Wayland at the same scale of 2. All three sets contain 2560×1600 images of a 1280×800 scene.

The reference desktop initially placed its pointer at (1560, 1040). In the native control, it hovered the central button on pages 6, 26 and 31. Moving only the private pointer to (4, 4) before a second ES2 launch removed the highlight. For example, the normalized mean absolute RGB error on page 26 fell from 0.01287 to 0.0000153 against Godot OpenGL, and from 0.01306 to 0.000208 against Godot Vulkan. The Godot image used in each pair was identical.

With the pointer in the margin, the 35-page median was 0.000638 on Vulkan and 0.0000153 on OpenGL. The largest difference for both was on generated table page 18 (0.01161 and 0.01047 respectively). The comparison measures the page content between logical y=35 and y=710. Whole-window gestures and input have separate acceptance fixtures. Per-page metrics, both captures and the pointer coordinates are archived with the content-cache release. The comparison summary is `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-content-release-1JbNFKJu/native-pointer-reference-ay2VURi8/summary.json`.
