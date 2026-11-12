# VFX source build and Intro smoke

## Blackhole Effect in the Intro menu

The Intro drawer now ends with an initially unchecked checkbox labeled
`Blackhole Effect`. Open the top-left menu and scroll to the bottom.
Checking enables the effect; unchecking turns it off.
This is an intentional addition to the Demo, not a change to VFX library controls.

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
source works in Viewport and RD modes. No Robot, screen capture or CPU frame
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
.\scripts\test-vfx-blackhole.ps1 -RD
.\scripts\test-vfx-blackhole.ps1 -Renderer gl_compatibility
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
logs under `artifacts/logs/vfx-blackhole-*`. The D3D case only checks that the
unsupported control is absent. These checks are not physical-input or
frame-rate acceptance.

2026-11-12 validation of the pure lens shader and checkbox: the source VFX build
and the complete fixture pass on
Editor mobile/safe with RD off and on, plus OpenGL/safe. GPU captures were
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

2026-11-03 LoadingStage interaction: `test-vfx-loading.ps1` selects original page
26 and uses host clicks to open its LoadingStage and dismiss the completion alert.
It observes the original TaskManager/100-item flow, changing item labels,
monotonic progress reaching 1.0, automatic loading-window closure and the original
"loading complete" message. Loader and alert must have distinct independent
native identities; final window/presentation drain and zero owned resources are
required. OpenGL/safe, Vulkan/separate and packaged Runtime Vulkan/separate pass.
The loading/complete GPU captures were inspected. Run with `-Renderer`,
`-RenderThread` and optionally `-Runtime`; outputs use the `vfx-loading-` prefix.
`-Cancel` additionally clicks the original loading-window CloseButton before
completion and requires the localized cancellation alert. It waits 500 ms for
in-flight work to settle, clicks Ok, then observes one second without progress
changes or new windows. OpenGL/safe, Vulkan/separate and packaged Runtime
Vulkan/separate pass this branch with independent native windows and zero final
owned resources; the Runtime cancellation capture was inspected. Cancel outputs
have a -cancel suffix. Injected item failure, physical input and animation
smoothness are not established by these tests.

2026-11-03 full-page recheck after native-memory fixes: OpenGL/safe completes all
35 original pages at 200% scale (2560x1600), using host Next-button input and
rendered-page acknowledgements, then releases all host resources. The completed
manifest is artifacts/reference/vfx-pages-gl_compatibility/run.json. D3D comparison
uses the same scale and page count; vfx-comparison-gl_compatibility.png/.json
contain the paired sheet and per-page differences. The sheet plus full-size
FusionPane, table and component/image-background captures were inspected.
Randomized table data/timestamps and animated borders prevent treating raw image
differences as an automatic correctness gate. This run does not exercise every
page action. LoadingStage completion/cancellation and animation-graph actions
now have the dedicated coverage described above. Subsequent Vulkan/safe all-page
captures also pass; see acceptance-status.md for the current evidence.

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
all table variants. Run `scripts/test-vfx-table.ps1` with `-Renderer`, `-RenderThread`
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
.\scripts\test-vfx-intro.ps1 -Renderer mobile
.\scripts\test-vfx-intro.ps1 -AllPages
.\scripts\capture-vfx-reference.ps1
```

The separate Gradle project in scripts/vfx-build uses the source-built SDK in
jfx/build/sdk, the repository's Gradle wrapper and JDK 25. It compiles the original
VFX main module and all test sources without changing VFX business code. Maven
Central supplies VFX's declared third-party dependencies; no binary JavaFX SDK
is downloaded or substituted. The upstream JavaFX 11 / Gradle 7 build is preserved.

Outputs are artifacts/vfx/classes/java/{main,test}, resources/{main,test} and
dependencies. The Godot host runs the original io.vproxy.vfx.intro.IntroMain
entry point on the classpath, with JavaFX modules from the local SDK. Logs are
artifacts/logs/vfx-build.log and vfx-intro-<renderer>.log. Captures are
artifacts/reference/vfx-intro-<renderer>.png and vfx-intro-next-<renderer>.png.

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
and a completion manifest are saved in artifacts/reference/vfx-pages-<renderer>.
All-page logs use vfx-intro-<renderer>-all-pages.log. The two-page smoke stores its
manifest in vfx-smoke-<renderer>, so later smoke runs cannot replace the all-page
completion record. Earlier runs used a shared log/manifest location.

The reference helper renders all 35 original scenes using this SDK's Windows
D3D backend. It selects scenes directly for reference capture, so it is not an
input test. scripts/compare-vfx-pages.py (Python with Pillow) produces a paired
contact sheet and per-page RGB differences; it rejects incomplete capture runs.
Random table data, timestamps, animation timing and navigation-button state mean
the differences are visual triage, not an automatic correctness threshold.

The current GL and Vulkan 35-page runs pass and both paired sheets were inspected.
This covers navigation and visible content, not each button or modal dialog.
Godot `--render-thread separate` initially failed pixel comparison because a
deferred post-draw notification could prematurely release a pending pass. The
host now orders a draw and synchronizes the render queue before releasing it.
Effects and GodotView probes pass on both backends with `-RenderThread separate`.
A minimal Godot shutdown fix also returns the RenderingDevice to main after
joining the render worker; editor/runtime empty-scene shutdown tests pass in both
modes. VFX's 35-page captures above use the default `safe` mode; they do not
establish full Demo acceptance in separate mode.
OS screenshot capture was attempted with the computer-use skill but initialization
failed with `Module not found: @oai/sky`; these artifacts remain GPU captures.

The test does not establish correctness of every Demo page, native dialogs,
clipboard, IME, media, popup stages, physical input, DPI or prolonged animation
and resource stability. Continue page-by-page visual and interaction acceptance;
do not treat this smoke result as completion of M6 or the overall objective.

## Windows PowerShell stderr handling

`run-vfx-demo.ps1` supports both Windows PowerShell 5.1 and PowerShell 7.
Native stderr is captured as text while temporarily using `Continue` for the
native invocation. This prevents Windows PowerShell 5.1 from treating benign
JDK native-access warnings as terminating errors when KeyChooser loads
JNativeHook. The previous error preference is restored afterward; file-write
errors, nonzero native exit codes, missing close markers and logged application
errors still fail the launcher. Warnings remain in the log.

2026-11-12 validation: the launcher smoke passes in PowerShell 5.1 and 7.
The same launch pipeline in a bounded Components Demo diagnostic accepts the
actual JNativeHook warning, opens and closes KeyChooser through synthetic Godot
input, and completes normally on PowerShell 5.1. A diagnostic native command
returning exit code 7 is still rejected even when it prints the close marker.
No physical mouse or keyboard input was synthesized.

## Startup window

`run-vfx-demo.ps1` hides engine/JVM startup and displays the Godot logo inside
the first JavaFX window for at least one second, until the first frame is ready.
Use `-NoGodotLogo` to reveal the prepared application directly. Subsequent
windows do not repeat the logo. See [startup behavior and tests](startup-window.md).
