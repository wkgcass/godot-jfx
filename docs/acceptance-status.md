# Acceptance status

Last cross-platform review on 2026-11-19. This page describes the supported configuration and
validation limits. Earlier implementation rounds and removed-mode measurements
are historical evidence in [progress](../agentdir/docs/progress.md) and Git history; current
commands are in [TESTS.md](../TESTS.md).

Tests write logs under `agentdir/logs/` and captures under `artifacts/reference/`. The [archived run reports](../agentdir/docs/acceptance-status.md) identify the original logs and captures for each platform.

## Supported configuration

Windows x64, macOS arm64 and Linux x64 have source-built platform JARs. Linux validation runs on WSL2 with native Wayland windows. The platform sections below give the test results and outstanding capabilities.
The Godot Editor and shared library build with `accesskit=no`, which disables Godot's screen-reader integration.
JavaFX hosting uses **Viewport + safe**. The `mobile` renderer uses D3D12 or Vulkan on Windows, Metal on macOS and Vulkan on Linux. The `gl_compatibility` renderer uses OpenGL. The custom
RD-direct backend, translator, build/runtime switches and dedicated probes are
removed, as are separate-thread host adaptations. Godot's own RenderingDevice
and renderers remain. Unsupported separate hosting is rejected before bridge registration.

JavaFX keeps its application and Prism render threads. The host consumes the
bounded command queue on Godot's main thread. Primary Stage presentation and
native secondary windows still use the shared texture-layer compositor;
GodotView is an embedded scene control, not a Stage window.

The cleanup also removed orphan probe/mesh wrappers, unused clipboard JNI
entry points, redundant callback dispatch, the unused full-shadow region-upload
branch and an unwritten window GPU counter. Region uploads use packed patches;
referenced textures retain immutable revisions. Active protocol diagnostics,
reflection/virtual callbacks and resource-lifetime fixes are retained.

## Validation evidence

### Wayland merge compatibility review

This review restored desktop-coordinate pointer routing on Windows and macOS and restricted the Wayland-only native window flags to Linux. The Windows x64 build ran on Intel Arc B390 with D3D12/mobile, Vulkan/mobile and OpenGL/gl_compatibility. The first run passed 453 of 457 NonRobot invocations and all 42 Robot invocations. All 457 NonRobot invocations passed including repeats. The Vulkan/runtime clipboard peer initially missed its custom format. The D3D12 resize check initially sampled a black pixel with one retained layer. Both passed unchanged on repeat.

The D3D12 and OpenGL synthetic-hover cases missed the green fill during the first button hold. Both the preceding engine and the reviewed engine reproduced this on the same desktop. An input trace recorded the native pointer leaving the relocating host immediately after the synthetic motion. Parking the physical pointer outside both the initial host and the final Stage before launching the original cases allowed both to pass. The three physical Robot hover cases passed on the first run. Per-case Windows ledgers and the diagnostic traces are archived under `agentdir/artifacts/platform-review-jXMrW2O7/windows/`.

For macOS arm64, the pre-merge and post-merge Metal/OpenGL runner plans matched across all 317 NonRobot and 22 Robot invocations. This review covered shared code, platform-specific sources and the runner arguments. The 26 November 2026 acceptance record covers the Windows and WSL2 runs. The full 339-case macOS regression remains pending until an Apple Silicon Mac with a GUI session is available.

The Linux x64 build with the desktop pointer-coordinate and native window flag fixes (engine SHA-256 `3756c7cc159c…`) completed all 344 cases on private Wayland desktops using the Intel Arc B390. Vulkan/mobile and OpenGL/gl_compatibility each completed 205 VFX page visits during their navigation soak. The first run passed 312 of 322 NonRobot cases and 20 of 22 Robot cases. The twelve failures matched the preceding release at the same assertions. Six queried global stacking, two required global placement and lowering, two timed out restoring a minimized Stage at step 12, and two received drag events but failed the absolute Stage position check.

The local audit under `agentdir/artifacts/platform-review-jXMrW2O7/` contains the per-case results (`comparison.json`), matching failed assertions (`window-parity.json`) and 323 fixture logs checked for driver, display and loaded engine identity (`fixture-routes.json`).

### Linux x64 on WSL2

The Linux x64 release with engine `50490cf27698…` uses native Wayland for every graphical window. On the Intel Arc B390, the packaged engine ran Vulkan/mobile through Mesa dzn and OpenGL/gl_compatibility through Mesa D3D12. Both drivers passed the private-desktop checks for VFX title-bar movement and resizing, overlapping owned Stages, and restoration through the Weston task switcher.

All 344 manifest invocations ran serially on private Wayland desktops. Each result after repeats matches the same invocation in the preceding release.

| Group | Executed | First-run passes | Passed including repeats |
| --- | ---: | ---: | ---: |
| NonRobot | 322 | 296 | 312 |
| Robot | 22 | 19 | 20 |

The ten outstanding NonRobot cases cover six global stacking queries, two global placement and lowering checks, and two application-initiated restores of a minimized Stage at step 12. Both remaining Robot cases received drag events and failed the final absolute Stage position check. All 309 cases for which the preceding release recorded a fixture-level driver have a matching engine, Wayland display, renderer and B390 device record.

On a 1280×720 labwc desktop, default decorations left a 1280×694 maximized client area for both the preceding and current engines. With the fixture's client-decoration rule, both releases reported the full work area. The current engine passed the normal and runtime window-control cases on both drivers. The Vulkan Shadow JAR passed after an idle Gradle daemon released its cache lock. A Vulkan video playback timeout and an initial OpenGL Robot pointer-position failure both passed on fresh private desktops.

Both renderers captured all 35 VFX pages at scale 2 with animation running and with Fusion animation frozen. The three-round navigation soak on each driver produced 205 paired page observations and ended with zero tracked host resources and zero shared target shaders. The complete process traces start about one second after launch. Both standalone demo JARs contain the same engine as the VFX JAR. On each renderer the first demo rotated, paused, responded to a drag and resumed. The second completed its room smoke test and produced a 2200×1440 preview.

The local evidence is under `agentdir/artifacts/wayland-only-PI3LSNkB/`. It includes the per-invocation comparison, matched window assertions, runtime driver records, VFX captures, process samples, and standalone demo logs.

#### Preceding Wayland release

On 25 November 2026, the Linux x64 package completed the 344-case Wayland manifest on the Intel Arc B390. All GUI cases ran serially on private desktops. Vulkan used Godot mobile through Mesa dzn. OpenGL used gl_compatibility through Mesa D3D12. The ordinary build and the two independent demo JARs used the same native engine as the VFX JAR.

| Group | Executed | First-run passes | Passed on the same release including repeats | Outstanding |
| --- | ---: | ---: | ---: | ---: |
| NonRobot | 322 | 295 | 312 | 10 |
| Robot | 22 | 20 | 20 | 2 |

Fourteen cases that failed on Weston passed on labwc. The two synthetic hover cases passed with the native pointer isolated. OpenGL Stage churn first stopped at cycle 30, then passed the unchanged 36-cycle test on a fresh Weston desktop. A separate instrumented 180-cycle run also passed. The first observed increase of one root canvas slot remains recorded in [memory validation](memory-validation.md).

| Outstanding assertion | Cases | Observed behavior |
| --- | ---: | --- |
| Read the global native stacking order | 6 NonRobot | The Wayland client reports the global query unavailable. The owned-child overlap probe passed on both drivers. |
| Apply global placement and lower a top-level window | 2 NonRobot | The composition fixture reports unsupported placement and lowering on xdg-shell. |
| Reverse a minimized Stage from the application | 2 NonRobot | Both drivers stopped at step 12. A labwc taskbar client saw the minimized flag persist. With taskbar restoration the same fixtures completed. |
| Move a Stage using absolute coordinates | 2 Robot | Both fixtures received drag events and failed the final absolute position check. The public VFX title-bar gesture moved the window by (+180, +75) logical pixels on both drivers. |

Both renderers completed all 35 VFX pages with animation enabled and with Fusion animation frozen, and three round trips at a 256 MiB Java heap. Both extra demo JARs ran on both renderers. The platform tests include an explicit unsupported result for Wayland touch-keyboard requests. Physical IME candidate UI and Windows desktop integration have separate acceptance scopes.

The archive is `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/wayland-toolkit-publication-QI3DyI7e/`. It contains the first and repeat results (`nonrobot-with-repeats.csv`, `robot-current.csv`), outstanding assertions (`window-results.json`), and runtime display and GPU records (`display-route-audit.json`). Fixture logs gave complete Wayland, renderer and B390 records for 287 non-Robot cases and all 22 Robot cases. Additional evidence includes package consumer runs, normal and frozen VFX captures, both standalone demos and the measured menu, shader and table timings.

This earlier Linux package paired engine `ace7814e1e52…` with `Toolkit.class` `ab7b90061449…`. In the preceding OpenGL launch test, a JVM returned the requested exit code 37 while an FX idle callback threw `Godot host is STOPPING`. The FX thread was retrieving its existing toolkit during shutdown. The corrected lookup reuses the initialized toolkit under its class lock. A shutdown observer reproduced the failure on the previous package on both drivers. With the rebuilt package, main-thread exit, FX-thread exit and the new shutdown observer all passed on Vulkan and OpenGL, with one engine per process. An explicit attempt to initialize an engine that is stopping still fails. The detailed logs and JAR comparisons are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/wayland-toolkit-publication-QI3DyI7e/`.

The Maven consumer suite subsequently passed all 34 Vulkan child cases and all 35 OpenGL child cases. Both resolutions used graphics classifier SHA-256 `7c3155fc8e30…`. In each driver run, the main-thread exit, FX-thread exit and toolkit shutdown observer returned 37 with one engine and one render loop. The per-driver evidence is in `library-consumers.json` in the current package archive.

Both drivers initially failed the synthetic hover check on the shared private Weston desktop. A Vulkan trace on that same desktop captured a native pointer leave on the Stage during the first synthetic hold. JavaFX reported the intended button hovered, then cleared it about 12 ms later. All 151 sampled frames lacked the hover color. The NonRobot runner now isolates this fixture in Weston with native input disabled, as it does for synthetic resizing. The full hover checks passed on both drivers with the original pixel and cleanup assertions. First-hold misses fell to 9 of 157 samples on Vulkan and 8 of 160 on OpenGL. The trace and screenshots are in the current package archive under `hover-diagnosis/`, and the two reruns are under `retries/hover-no-input/`.

The staged `ace7814e1e52…` engine fixed a startup ordering defect on labwc. With the previous `906cf6d68fa4…` build, clicking the overlap of two Stages shown in the same event reached the owner. With the new build the click reached the child, including after clicking the exposed owner and after hiding and reopening the child. Vulkan and OpenGL both passed with simultaneous and deferred show. Each trace contains one parent request for the original child, after the owner's first mapped buffer and before the child's first buffer. The independent JavaFX Robot fixture and the source Editor toplevel protocol test passed on both drivers. Results are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-owned-present-N9JLMSUt/`. Global toplevel order remains controlled by the compositor.

The same staged `ace7814e1e52…` engine passed all 35 frozen VFX Intro pages at 2× on each driver. Both runs ended with zero owned resources. On each driver 33 of the 35 content regions matched the preceding build pixel for pixel. Only the generated tables on pages 18 and 19 differed. Against the native ES2 reference with the pointer parked, median normalized RGB differences were 0.0006384 for Vulkan and 0.0000153 for OpenGL. The two standalone Demo JARs also ran on both drivers. In the first Demo the model rotated, paused, responded to a drag and resumed. The second Demo's 2200×1440 preview matched the previous build byte for byte in RGB on each driver. The captures and comparisons are under `visual/` in the same archive.

The ordinary source build reproduced the staged `ace7814e1e52…` library. All 7,874 file payloads in the VFX JAR and all 8,586 and 8,585 payloads in the two Demo JARs matched their staged counterparts. The ordinary build also passed both drivers’ VFX launch and shutdown, title-bar move and resize, overlapping owned Stage, Editor toplevel and interactive Demo checks. Package identities and logs are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-timeline-release-vJsyDaug/regular/`.

The complete VFX JAR containing engine `906cf6d68fa4…` accepted real Wayland pointer input in
the Intro drawer, the 50-row table and the Blackhole control on both drivers.
Six 216-pixel table strokes were recovered exactly from desktop images. The
new OpenGL package showed 98 and 100 distinct moving-table updates during
the six input strokes in two launches, compared with 52 on the preceding
published package. Both drivers restored the original welcome-text pixels
after the lens was turned off. At 1× and 2× on labwc, all 96 menu clicks
reached the JAR and produced the expected settled drawer state. Both scales
kept a 1280×800 logical window, and the drawer edge agreed within 0.5 logical
pixels. At 2× OpenGL showed a longer opening latency than Vulkan. The capture
method, sample intervals and package identities are recorded in
[frame-benchmark.md](frame-benchmark.md) and [vfx-demo.md](vfx-demo.md).

An isolated Linux build on November 25 produced engine `906cf6d68fa4…`
with small LCD region copies selected from the actual Wayland/Mesa D3D12
OpenGL backend. The source-built editor, library, JFX SDK with Media, VFX
and both separate demos built. Ten fixtures, both VFX smokes and both demos
on each driver passed. The released code moved the table by 2,325 pixels
in 96 pulse intervals. OpenGL p95 was 30.2 ms and Vulkan p95 was 41.1 ms.
The automatic path produced region-copy commands on OpenGL. On Vulkan it
used pass boundaries. A separate mixed clipped/overlapping text check tested
automatic, forced and disabled region copies against LCDBuffer on both
drivers. No pixels exceeded the existing two-level channel tolerance.
The regular LCD overlap fixture also exercises a cached glyph layer.
The isolated package, fixture logs and hash audit are under
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-release-MIuxEnnx/verified-tests.json`. The full matrix below belongs to earlier
packages. The menu timing limits are in [the frame measurements](frame-benchmark.md#linux-table-dragging-on-the-published-runtime).

The regular Linux source build subsequently produced the same engine
`906cf6d68fa4…`. It matched the isolated build in every non-directory JAR
member of VFX and both demos. VFX started and closed on both drivers. The
tetrahedron accepted pause, resume and drag input on both, and the room
passed on OpenGL. The initial Vulkan room run missed the light switch
during movement. Three fresh sessions with the identical JAR passed the
full smoke test and produced pixel-identical 2200×1440 startup captures,
including a match to the failed run. The cause of the intermittent input
failure is unresolved. Six additional instrumented Vulkan launches followed
all 108 press and release events through Godot's panel hit test and JavaFX
picking. The largest deviation from the scale-2 coordinate mapping was
0.493 logical pixels, and both sides reported the same nine device states
in every launch. On one successful click JavaFX still reported an unfocused
Stage at press time and a focused Stage at release. The trace summaries are
in `room-input-trace-rf6kSZJW/verified.json`. See `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/`,
particularly `package-comparison.json`, `demos/results.txt` and
`room-recheck-BtcBXdFW/results.txt`.

With the regular `906cf6d68fa4…` package, the isolated Robot group passed
20 of 22 cases on its first run. Both failures asserted absolute desktop
coordinates after dragging. The compositor independently observed the actual
window and owned Stage move by (170, 110). In the supplementary labwc group,
25 of 28 passed on the first run. Both rapid restore cases failed, and a
Vulkan icon case reached all seven expected icon states before its final
Next click failed to close the fixture. The identical icon case passed in
a fresh session. Results are in `robot-current.csv`, `labwc/results/results.csv`
and `retries/icon-vulkan-default/results/results.csv` under the regular
LCD publication archive above.

The complete 322-case NonRobot run on this package passed 298 cases on the first Weston run and 312 including the same-release supplemental runs. Six remaining cases require a global stacking query, two require global placement and lowering, and two failed to restore a rapidly minimized Stage. All 322 invocations matched the manifest. The runtime audit also matched the loaded shared library for 287 cases. Both 256 MiB VFX soak runs completed three round trips through 35 pages, each with 205 matching Java and native navigation samples and zero final owned resources and shared target shaders. The counts, original failures and supplemental logs are indexed in `window-results.json` and `nonrobot-with-repeats.csv` in that archive.

The next VFX source build fixed the resize grip after an actual title-bar
move. The old grip applied a change in Glass screen origin to its width and
height. The new grip uses the pointer delta in scene coordinates. With the
same physical input, the primary window grew and shrank by the requested
amounts on both B390 drivers. All four pixel boundaries matched at 1× and
2×. The owned window also resized on both drivers while its owner stayed
fixed. The independent JavaFX Robot probe measured the original failure and
the correction using compositor output. The two VStage class files were the
only changed JAR members compared with the preceding source build, in the
Intro and in both extra demos. Results are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-geometry-release-MrQkS9GG/`.
[Gesture details](glass-godot.md#resizing-the-vfx-grip-after-an-interactive-wayland-move).

The VFX build with both the geometry correction and scrollable-content
cache passed 35 frozen pages on each driver, the menu endpoint comparisons,
the separate physical geometry fixture, both Demo smoke launches and both
interactive extra demos on Vulkan and OpenGL. The blackhole and 50-row
table profiles also passed. GPU identity, engine digest and per-driver
results are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-content-release-1JbNFKJu/verified-tests.json`.
[Performance measurements](frame-benchmark.md#caching-the-scrollable-drawer-content).

The engine SHA is shared by several VFX builds. Hashing the sorted JAR entry
names and their individual SHA-256 digests distinguishes the earlier package
(`b37d678c29c327a1` prefix) from the staged content-cache package
(`cc2b97942079b948` prefix). For the latter, 359 of 364 compiled VFX classes on
the fixture classpath matched the JAR byte for byte. Five anonymous alert
classes differed only in a constructor parameter name in their debug
information. The animation timer, window drag and resize handlers, and Intro
menu classes all matched exactly. Both extra demo JARs contained the complete
224-class VFX main set. The per-package record is `vfx-fixture-inputs.json`
alongside the verified tests above.

The published engine `da0a4ee0ac9a…` finished all 322 NonRobot cases
and all 22 Robot cases on November 25. NonRobot passed 296 on the initial
run and 312 including targeted repeats. Six remaining cases required a
global window-stacking query, two required placement and lowering, and two
failed to restore a rapidly minimized Stage from the application. Robot
passed 19 initially and 20 including a fresh-session repeat. Its two
remaining cases asserted an absolute Stage position after a drag. Separate
compositor captures verified movement of the VFX window and an owned Stage.
Each driver also passed three full VFX navigation round trips. Logs, repeat
identities and per-case classifications are in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/window-results.json`.

The 2026-11-25 isolated source build of the optimized Linux mesh path produced
Godot library `da0a4ee0ac9a…`. The editor, library, VFX JAR and both
independent demo JARs built successfully. Ten native Wayland fixtures (blit,
mesh transforms, LCD overlap, node shaders and VFX table dragging on each
B390 backend) loaded this engine and passed. Each table drag moved 2,325
pixels at scale 2 in 96 intervals. OpenGL p95 was 51.2 ms and Vulkan p95
was 41.9 ms. The standalone VFX smoke and both independent demo smoke checks
also passed on both backends. Package hashes, application logs and images
are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-release-eVFhfCPk`.
The ordinary Linux workspace build produced the same native library SHA-256.
Every non-directory JAR member matched the isolated build byte for byte, with
7,874 members in VFX, 8,586 in the tetrahedron demo and 8,585 in the room
demo. The comparison is in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/normal-package-comparison.json`.
See the [mesh and frame measurements](frame-benchmark.md#linux-table-dragging-on-the-published-runtime).

On this publication, the first native Wayland Robot run passed **19/22**.
The ordinary OpenGL Robot test initially failed while saving the cursor position.
It passed unchanged in two fresh labwc sessions, one with default pointer state
and one with a known initial position. Both runs reported one click and one
wheel action on the published B390 engine. Counting each case once, the result
is **20/22**. The two physical drag probes received drag events but failed the
absolute Stage position check. Separate title-bar gestures moved the main
window and an owned window on each driver. The 28-case labwc NonRobot subset
passed **26/28**. Both rapid Stage minimize/restore variants failed at step 12.
The publication archive contains `robot-with-repeats.csv`,
`released-window-moves.json` and `labwc/results/results.csv`.

A labwc taskbar observer saw both the owner and child become minimized on
the rapid request. In a Vulkan trace the application requested activation
of the child's surface and the desktop still reported the child minimized.
In a separate run on each driver, a taskbar client focused the minimized
child. The desktop reported both windows restored and the original Stage
test continued through its pixel, mode, size and teardown checks. These
desktop-assisted runs are recorded separately in
`rapid-stage-cHFWlT9M/verified.json` within the publication archive.


The rebuilt Linux graphics classifier with SHA-256 prefix `8711ee8993ae`
includes the Wayland modal focus fix and sampler-state invalidation.
The revised scene fixture uses one host-stop exit path. The JFX SDK, VFX
JAR and both separate demo JARs built successfully. A content check matched
the SDK classes, generated shaders and native libraries in VFX and the
graphics classes and exported scene pack in each demo. The published
encoder wrote 72 bytes on its first shader state, then zero on an equal
repeat with suppression enabled. Its two-mode regression passed. The build
and per-file evidence are in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-jfx-revision-xsBlG2d3/`.
On this classifier, both VFX smoke launches reported Wayland and the Intel
Arc B390. On labwc the main window moved from (60, 80) to (230, 190)
and the owned Stage moved from (781, 301) to (951, 411) on both drivers.
Each trace recorded a compositor move request. Both standalone demos also
passed on each driver, including the tetrahedron pause, drag and resume
sequence and the room smoke check. The four external GTK drag cases passed
on niri. The release archive contains the logs and screenshots under
`gestures/`, `secondary/`, `demos/` and `canonical/results/`.

The 22-case Robot run passed 19 cases on its first attempt. The OpenGL
cross-window drag fixture stopped before its first drag because the compositor
had not reported an initial pointer position. On a fresh private labwc desktop
the same case completed all seven drag sequences and three drops. Counting
the repeat gives **20/22**. The two outstanding cases assert absolute Stage
positions during a drag. See `robot-current.csv` and `robot-with-repeats.csv`
in the release archive. The targeted labwc NonRobot run passed **26/28**.
Only the two rapid Stage minimize/restore cases timed out at step 12.

The complete NonRobot counts below refer to the previous graphics classifier,
which uses the same native engine.

On the B390 build with native library SHA-256 `20e839a2fcf2…`, the
first complete isolated Robot run passed **19/22**. Each fixture log was
checked against the packaged engine hash, Wayland display driver and B390.
The four external drag cases on niri passed, as did both drivers' VFX table
drag and hover cases on labwc. The two physical Stage drag cases received
drag events but failed their absolute-position check. The third failure was
the Vulkan/runtime Robot reading the initial cursor before a position was
reported, not a Vulkan initialization failure. See
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/verified-release-lZUp7QMq/restart-suite-n8jhXQQK/robot-current.csv`.
That Vulkan/runtime case passed on two fresh labwc sessions, one with an ordinary seat and one with a seeded initial pointer position. Both matched the release engine and reported one click and one wheel action. Including retries, **20/22** Robot cases passed. Logs are in `restart-suite-n8jhXQQK/robot-runtime-repeat/{ordinary,seeded}/results/`.

The complete NonRobot manifest on the same engine ran **322/322** cases.
Isolated Weston passed **293/322** on the first run. Fourteen first-run
failures passed unchanged on labwc, for 307/322 cases with at least
one pass on those two runs. They covered native Stage input (2), native window bridge (2),
VFX window controls (4), window drag (2) and window icons (4).

Fresh Vulkan screen-association and OpenGL synthetic-hover runs passed the original assertions. With those repeats, **309/322** cases passed at least once.

| Cases without a pass in those published-run ledgers | Count | Observed outcome |
| --- | ---: | --- |
| Native order, window composition and window order | 8 | The assertions require global stacking or placement information unavailable through xdg-shell. Both composition runs completed six pixel and cleanup phases. |
| Owned modal focus | 2 | The owner lacked JavaFX focus immediately after the application-modal Stage returned on both renderers. |
| Rapid Stage minimize/restore | 2 | The application-driven test timed out at step 12 on both compositors. |
| Host shutdown | 1 | Vulkan/runtime returned from Application.launch with live Glass peers. |

The scene fixture now leaves host-stop shutdown to the Glass frame receiver.
The previous fixture also called `Platform.exit()` from a second watcher.
A controlled schedule reproduced `Application.launch()` returning before
the termination hook completed with both callers. The revised fixture
passed the original host-stop assertions on both B390 drivers, with and
without `--runtime`. All four runs closed the three Glass peers and
disposed the renderer with zero texture-pool bytes. These post-fix runs
are under `restart-suite-n8jhXQQK/stop-race-szX0UA1s/revised/`.

The ordered manifest, every first result, repeat logs and engine-hash audit
are in `restart-suite-n8jhXQQK/{nonrobot-manifest.txt,nonrobot-full/results.csv,nonrobot-with-repeats.csv,nonrobot-full-audit.json}`
in the release archive above. The encoder regression added after case 198
also ran against a separate candidate graphics JAR. Its result is outside
the first-run count.

For this release, the staged and installed Linux Maven classifiers match
their publication hashes. The VFX JAR contains byte-identical copies of
all 3,411 graphics classes and generated shaders, 175 media classes, and
15 native libraries (including the Godot engine) checked against the
source-built SDK and engine. Both independent demo JARs match their
declared graphics classifier and their own exported scene-pack
files in `build/pack`. The per-package counts and pack hashes are in
`restart-suite-n8jhXQQK/package-content.json` in the same archive.

The same B390 engine passed both native Stage input and the native window
bridge on labwc with Vulkan and OpenGL. On Weston the input probe timed out
at step 1 on both drivers, and the bridge probe failed to observe restoration
after Wayland activation. The rapid Stage mode-change test stopped at step 12
on both compositors and both drivers. These runs used isolated Wayland
desktops. The individual results and application logs are in
`restart-suite-n8jhXQQK/{labwc/results,nonrobot-full}/` under the release
archive above.

Separate compositor screenshots on this build verified a 170×110-pixel
move of the packaged VFX main window and of an owned Stage on both
drivers. Unlike those gestures, the physical Stage fixture calls
`Stage.setX/setY` on every mouse drag. Godot caches the requested window
position even though its Wayland display server cannot apply that request
to a toplevel. The host adds that cached origin to subsequent surface-local
mouse coordinates; feeding the result back into the next position request
can amplify the reported displacement. The failing Stage coordinate is not
a measurement of the compositor moving the window.

The Linux x64 package built on 2026-11-24 at 17:09 uses a 256 MiB initial texture reclamation target. The source-built SDK, both local Maven graphics JARs, VFX and the two independent demo JARs contain the same `GodotTexturePool.class` (SHA-256 prefix `b0774c465b25`). The five runtime JARs contain the published Godot library `a312dd9c27c1…`. The packaged SDK passed the locked-texture pressure and cancellation checks. VFX and both demos ran on native Wayland with both B390 drivers (6/6). The tetrahedron checks exercised pause, resume and drag. The room checks exercised its JavaFX controls. Package hashes and application logs are in `agentdir/artifacts/wayland-linux-pool-release-j87Wdjek/{after.json,app-checks.json}`.

On that 256 MiB package all 22 Robot cases ran. Fourteen passed on their first invocation. The first niri session lost its parent compositor before the test clients could complete, affecting all four external GTK drag cases. Two other cases terminated at the initial cursor-position query. All six passed when repeated on fresh private desktops. Counting each case once, 20/22 passed with verified B390 and native Wayland logs. On both drivers the physical Stage-drag case received mouse events beyond the window and failed at its absolute-position assertion. The first runs and repeats are recorded in the same package archive's `robot-observations.json`. The independent labwc window subset passed 14/18, with modal focus and rapid Stage restore failing on both drivers.

The same 256 MiB package executed the complete 322-case NonRobot manifest on private Weston. It passed 294/322 on the first run and 310/322 including the labwc subset and fresh Weston repeats. In the first Vulkan hover check the initial button missed its green hold color. The Vulkan media churn timed out on decoder cycle 19. The unchanged tests passed on fresh desktops, including all 24 media cycles with zero host-owned resources on exit. The 12 cases with no passing observation are listed below. The package archive contains `nonrobot-full-audit.json` (first run, logs and device checks) and `nonrobot-with-repeats.csv` (all observations). Together with Robot, 330 of 344 distinct cases passed at least once. The two drivers' physical Stage-drag results are counted separately from the passing synthetic drag and resize checks.

The earlier 512 MiB package with library `a312dd9c27c1…` completed all 322 NonRobot and 22 Robot invocations on isolated native Wayland desktops using Intel Arc B390. The full Weston NonRobot run passed **293/322**. Including fresh, targeted or second-compositor runs, **310/322** passed at least once. Robot passed **19/22** initially and **20/22** including one repeat. Initial failures are preserved in both ledgers. The complete manifest, case-by-case results, renderer headers and release hash checks are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/{nonrobot-full-audit.json,nonrobot-with-repeats.csv,robot-with-retries.csv}`.

A subsequent Linux build adds compositor-managed interactive movement for the VFX custom title bar. On private labwc, both B390 drivers passed the packaged main-window gesture and the owned-Stage gesture, moving each target by 170 × 110 screen pixels. The owner stayed stationary during the owned-Stage test. These checks cover interactive movement only. The release-level counts below retain the absolute-position assertions. See [VFX title-bar results](vfx-demo.md#dragging-the-custom-title-bar-on-linux).

| Outstanding on the published application | NonRobot | Robot | Observed requirement |
| --- | ---: | ---: | --- |
| Native window order and composition | 8 | 0 | Query the global stacking order or lower a regular toplevel. |
| Native Stage restore | 2 | 0 | Reverse a rapid minimize request from the application. labwc restored both windows when its desktop controller requested it. |
| Modal focus | 2 | 0 | Observe owner focus synchronously when the application-modal nested loop returns. |
| Physical Stage drag | 0 | 2 | Move a regular toplevel to absolute screen coordinates with `Stage.setX/setY`. |

Regular xdg-shell clients can identify a window's parent and request an interactive move using an input event serial. The compositor chooses the toplevel's screen position. The protocol also exposes a minimize request and leaves restoration to the compositor. Activation extensions allow a client to request focus, with the final decision made by the desktop. The immediate modal-owner focus failure in the table was observed on the tested desktops. [xdg-shell protocol](https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/main/stable/xdg-shell/xdg-shell.xml) and [xdg-activation protocol](https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/main/staging/xdg-activation/xdg-activation-v1.xml).


The Linux release `a312dd9c27c1…` shares immutable offscreen shader programs between live render targets. The VFX JAR and the two independent demo JARs contain the same source-built Godot library and JavaFX SDK modules. Both B390 drivers passed the five shader-cache, render-target and queued-texture cases (10/10). GPU pixel readback confirmed that each target draws with its own color and that releasing the first owner preserves the second target. Both demos passed their four Wayland smoke runs across Vulkan/mobile and OpenGL/gl_compatibility. The publication hashes, per-case logs and demo results are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/`.

On `a312dd9c27c1…`, 19/22 Robot cases passed on the first run and 20/22 passed including one fresh-session repeat. All four external GTK drag cases passed on niri. The OpenGL cross-Stage drag stopped at the first cursor-position query on labwc, then passed all seven scenarios on a fresh labwc desktop with ordinary startup. The two outstanding cases received drag events after the pointer left the Stage and failed the assertion about its absolute screen position. The first run and the repeat are recorded separately in `robot-current.csv` and `robot-with-retries.csv` in the same release archive.

On the same release the 18-case labwc NonRobot window run passed 13 cases initially. The Vulkan/runtime icon test timed out at step 5 after four successful icon updates, then passed in a fresh labwc session. Both drivers still failed native Stage step 12 during the rapid mode changes, and both failed the immediate owner-focus assertion on return from the application-modal dialog. Thus 14/18 of these selected window cases passed including the repeat. Logs are in `labwc/results/` and `retries/icon-vulkan-runtime/results/` in the release archive. A separate desktop controller restored both minimized windows on labwc, after which both drivers reached the final Stage assertion. Independent native GTK traces also reproduced the delayed modal focus notification. [Compositor comparisons](glass-godot.md#window-stacking-and-focus-on-wsl2)

The default synthetic resize on OpenGL failed in the full Weston run after four of eight drag events. Its Java trace contains a buttonless move between the pressed moves. A controlled repeat parked the private desktop pointer just outside the Stage. As the Stage grew beneath the stationary pointer, Wayland delivered a pointer enter at (485, 105) logical pixels, Godot delivered a buttonless motion at (970, 210) output pixels, and Java lost the drag after three moves. Parking outside the entire resized window passed. With the same edge placement and a seatless Weston, the eight pressed moves reached Java without the extra event. On the updated test runner both unmodified B390 fixtures passed in private seatless Weston. Physical Robot retains its normal input desktop and its two absolute-position failures. Traces and the button-mask sequences are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/synthetic-resize-RbukZeEn/`.

The full OpenGL popup-bounds run finished the Java checks but missed the host completion marker. The fixture now polls shutdown on scene-tree process frames after the eighth geometry check. Geometry and popup pixel capture still wait for rendered frames. An OpenGL control stopped drawing after Java exited, the native windows closed and composition became idle. The original fixture stalled and the revised fixture completed its zero-resource checks. Both unmodified drivers passed the revised fixture. The first-run log is in `nonrobot-full/174-test-popup-bounds/`. Controls and final repeats are in `popup-shutdown-plCgMTpv/` and `retries/popup-bounds/` in the release archive.

The VFX JAR passed isolated launch and shutdown on both drivers. Both drivers passed all 35 page captures and three full round trips on the published library. Each released every tracked host resource and shared target shader at shutdown. Separate Vulkan diagnostics traced the retained offscreen targets to JavaFX’s effect-image pool. At the second home-page return, 195 images were unlocked and available for reuse. A temporary lower reclamation target reduced that count to 42, with a smaller change in process private memory. This release's counts and memory samples are in [VFX memory validation](memory-validation.md#shared-target-shader-lifetime-in-the-linux-release).

The published `a312dd9c27c1…` engine completed twelve consecutive VFX round trips per driver. Both applications produced 817 paired page observations and released all tracked resources on exit. The OpenGL test script exited successfully. The initial Vulkan script exited with code 2 after writing its successful application report. A fresh twelve-round Vulkan run with a read-only launcher exited with code zero, matched all 817 page observations and released all tracked resources. Its latter-half private-memory slope was +3.01 MiB/min. The earlier measurements were +0.17 MiB/min on OpenGL and +4.86 MiB/min on Vulkan. Cached materials continued to increase on both drivers. [Twelve-round measurements](memory-validation.md#twelve-vulkan-rounds-on-the-published-shared-shader-engine)

The B390 release `64f8f54d265b…` completed all **322 NonRobot and 22 Robot cases** on isolated native Wayland desktops. Weston passed 292/322 on its full NonRobot run. Across the full run and the documented targeted repeats on Weston and labwc, **310/322 passed in at least one run**. The Robot matrix passed 19/22 initially and **20/22 with retries**. Both drivers also passed the VFX demo, 35-page navigation and both independent demos. Three round trips through VFX finished with zero host-owned resources, while private process memory continued to grow on both drivers. A separate four-round Vulkan diagnostic that shared identical target shaders reduced first-to-fourth-return live native heap growth from 354.9 to 50.5 MiB. [VFX memory measurements](memory-validation.md#three-rounds-on-the-b390-msaa-release)

| NonRobot cases with no passing run | Count | Observation |
| --- | ---: | --- |
| Native order, window order, window composition | 8 | The fixtures require the global order of native toplevels or client-controlled stacking. Standard xdg-shell leaves global stacking to the compositor. |
| Native Stage mode transitions | 2 | Step 12 timed out while restoring the Stage family on Weston and labwc. The protocol allows requesting minimization. There is no client request to reverse it. |
| Modal owner focus | 2 | At the second return from `showAndWait`, the owner lacked focus on Weston, labwc and niri. No synchronous focus guarantee has been established. |

The two remaining Robot cases require the Stage to follow absolute desktop coordinates while the physical pointer is outside its surface. The logs show JavaFX drag delivery on each driver. Each initial NonRobot case and its matching supplemental observations are indexed in `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/nonrobot-verification.csv`. The complete first-run logs are in `nonrobot-full/` there. For 287 cases the audit also matched the extracted fixture library to the release hash. Robot results and raw logs are under `agentdir/artifacts/wayland-niri-WMYYUVqs/`.

The `64f8f54d265b…` release ran both independent demo JARs on native Wayland with Vulkan/mobile and OpenGL/gl_compatibility on the B390. The tetrahedron fixture clicked pause and resume, dragged its view, compared model and axis pixels, and closed the Stage through the compositor. Both room smoke runs checked the wall controls, mouse capture and release, saved a 2200×1440 preview and exited normally. The demo kept its 2× MSAA request. Vulkan now selects the device's supported 4× mode before allocating viewport render buffers. The same Vulkan request previously triggered an invalid single-sample resolve and a driver crash. See the [Linux implementation and driver diagnostics](build-linux.md).

Both drivers passed VFX JAR launch and shutdown, the full 35-page Intro and native multiwindow checks. Dedicated viewport readbacks showed antialiased 3D edges on both drivers and antialiased 2D edges on Vulkan. The OpenGL renderer explicitly reports that 2D MSAA is unsupported. An initial 2D probe expected antialiased edges on OpenGL and failed. The backend capability check verifies the GLES3 warning and byte-identical single-sample pixels there. Logs and publication hashes are under `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/{publication.json,release-demos/,release-tests/,msaa/2d3d/}`. The Wayland NonRobot manifest now includes the two viewport regression cases, for a total of 322.

On the same release, all four external GTK drag Robot cases passed on isolated niri `02ee0585`. Both drivers completed bidirectional COPY, checked the custom four-byte payload, and cancelled the final drag with Escape. GTK measured the visible 8×6 preview. The four raw results are under `agentdir/artifacts/wayland-niri-WMYYUVqs/canonical/results/`.

The complete 22-case manifest on this release passed 19/22 on its first run (four external drag cases on niri and 15/18 on labwc). Each JVM log identified the B390, the Wayland display server and the matching shared-library hash. Both absolute Stage-drag assertions failed after the pointer left the Stage. The Vulkan/runtime general Robot case failed before its first action when labwc had not reported the initial pointer location. The same Vulkan/runtime case passed in two fresh desktops, once with an explicit initial virtual-pointer motion and once with ordinary startup. The missing initial cursor position is intermittent. With targeted reruns, 20/22 passed. The two absolute Stage-drag cases still failed. The first-run audit is in `agentdir/artifacts/wayland-niri-WMYYUVqs/robot-current.csv` and the separate rerun ledger in `robot-with-retries.csv` in that directory.


The full Weston NonRobot run on `64f8f54d265b…` missed the first plain button's hover color on every frame in the first hold, on both drivers. Java observed eight hover entries and zero stationary exits counted as flicker. The unmodified fixtures passed on both drivers when run sequentially again on a fresh Weston desktop. Separate diagnostic runs confirmed the hovered button, the 2× output scale and the expected green pixels. The original cause remains open. Results are in `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/nonrobot-full/` (cases 87 and 88) and `agentdir/artifacts/wayland-niri-WMYYUVqs/{hover-unmodified,hover-repeats}/`.

A separate 12-case labwc run on this release passed ten cases. Both drivers passed Stage input, VFX window controls (regular and runtime), and window icon (regular and runtime). Both failed the immediate owner-focus assertion after application-modal close in round two. The full Weston run and two independent niri cases also failed that assertion in round two. The niri results are under `agentdir/artifacts/wayland-niri-WMYYUVqs/niri-modal/results/`. Each log was checked against the release hash and the B390 driver. Results are under `agentdir/artifacts/wayland-niri-WMYYUVqs/labwc-desktop/`.

In the original OpenGL nested-menu run Java completed its actions, but the host completion marker was absent. The fixture now checks shutdown on scene-tree process frames after the outside dismissal. Menu navigation and popup pixel capture still wait for actual draws. Both drivers passed. A separate OpenGL control waited until the application had finished, all popup windows were gone and composition was idle, then disabled further display draws just before the final wait. The old wait missed host completion and the new wait reached the zero-resource assertion. This demonstrates the failure mode. The original run did not trace its final draw. Evidence is in `agentdir/artifacts/wayland-niri-WMYYUVqs/nested-menu-shutdown/`.

On 24 November the native Wayland release (`78d43359aab3…`) passed **16 of 22 Robot cases** on the Intel Arc B390. The tests ran serially on isolated labwc 0.9.3 desktops using Vulkan/mobile and OpenGL/gl_compatibility. The audit matched each case to the runner's manifest and verified the Wayland display driver, GPU and extracted engine hash in each JVM log. Both drivers passed basic and runtime Robot, all seven cross-Stage drag scenarios, VFX table scrolling, hover and hover-flicker, child IME and virtual keyboard. The two synthetic drag checks also passed. The VFX fat JAR and both independent demo JARs include the verified SDK classes and shared library. Results, raw logs and publication hashes are under `agentdir/artifacts/wayland-cross-stage-tn1HHwAW/{robot-current.csv,final/,publication.json}`.

| Remaining Robot cases | Count | Observation |
| --- | ---: | --- |
| External drag, default and runtime | 4 | All four GTK peers verified bidirectional COPY, custom bytes containing embedded and trailing NUL, and the 8×6 preview. In the cancellation scenario labwc completed a second COPY on button release. The earlier Vulkan protocol trace recorded the virtual Escape press and release without a press reaching the source. The tested wlroots 0.19.2 drag keyboard grab ignores key events. See [Wayland drag and drop](glass-godot.md) for the matching compositor source. |
| Moving the Stage with the pointer outside it | 2 | Drag events reached JavaFX. Standard xdg-shell provides a seat-driven interactive move. It has no request to assign the absolute desktop positions used by this fixture. |

The same release completed eight full VFX navigation rounds on Vulkan and released all tracked resources on exit. Private process memory rose from 1714 to 2281 MiB between the first and last return to the home page. Long-run stability remains open. [VFX memory measurements](memory-validation.md#eight-vulkan-rounds-on-native-wayland)

The previous release (`c6c976dfbd96…`) passed 13/22 initially and 14/22 after a Vulkan/runtime retry. Its cross-Stage cases rejected the fixture's custom MIME type. Logs are in `agentdir/artifacts/wayland-robot-2RIjHyHr/{robot-current.csv,robot-with-retry.csv}`. The complete 320-case NonRobot run below predates both Robot releases.

The first full B390 Robot regression with the native Wayland Robot backend passed **11 of 22** cases on isolated labwc 0.9.3. Each case loaded the same source-built engine (`566a85ec0c45…`). The four VFX hover-demo and table-scroll cases passed, as did both IME and both virtual-keyboard cases. Three of the four general Robot cases passed. The fourth failed while saving the initial pointer position in a reused session. The six drag and two window-drag cases and the two hover-flicker cases failed. In all four external drag cases the GTK peer independently measured the composited 8×6 preview before the COPY assertion failed. The full results and per-case log paths are in `agentdir/artifacts/wayland-robot-2RIjHyHr/robot-matrix.csv`. The VFX JAR and both additional demo JARs contain matching engine and SDK classes. [Wayland Robot](glass-godot.md#robot-on-linux-wayland)

On native WSLg Wayland the source editor passed the multiwindow probe on Intel Arc B390 with Vulkan/mobile and OpenGL/gl_compatibility. Separate surfaces, transient parenting, hide/show, parent destruction, and continued rendering in an independent peer were verified with protocol traces and pixel readback. Each driver completed three consecutive launches and shutdowns after fixing the Wayland event-thread wakeup. The graphics JAR also passed the Wayland device and color readback probe on each driver. The complete JavaFX VFX JAR passed isolated launch and clean shutdown on both drivers with DISPLAY unset. Each driver passed the four startup modes, including a primary-window remap and a separately mapped secondary window. A protocol trace checked the title at the first buffer commit and the application show timing. After the Wayland IME and startup scaling fixes, both drivers passed all 35 VFX Intro pages and the three-page frozen Fusion variant. Both complete runs captured 2560×1600 images and ended with zero host-owned resources. Windows-side measurements of the actual JAR confirmed a 2560×1600 client area at 200% for a 1280×800 logical Stage. See the [Linux build and probe instructions](build-linux.md).

The published-module consumer passed on Wayland with both drivers, including separate Stages, synthetic input, Unicode project paths, scene messaging, all 39 effect tiles, and the Oracle and Lk media samples. The native GTK/ES2 reference JVM queried the Wayland output scale for its reference pixels. The independent Shadow consumer on both drivers also passed its cold-cache, warm-cache, concurrent extraction and bundled-scene cases. Run records are under `agentdir/artifacts/linux-wayland-regression-NN0563Lp/` in `rest/` and `published-vulkan/`.

On a private Weston 14 desktop at scale 2, both drivers passed the native multiwindow protocol and pixel checks on the B390. The VFX animation default, timing-only and runtime cases passed on both drivers. Before the sizing fix, the 720-unit VFX alert produced a 2880-pixel-wide viewport, twice its requested width at scale 2. Window creation now converts Glass pixel sizes for standalone JavaFXHost child Stages as well as for startup-mode Stages. A Vulkan rerun completed all five clicks and captured the 900-unit chooser at 1800 physical pixels and both 720-unit alerts at 1440. The process exited with code 1 after the pass markers because its test cleanup initialized an unused global input hook. A standalone JVM reproduced this exit with no display and returned zero with the corrected cleanup. After the cleanup fix, both regular dialog cases completed the five clicks and exited successfully. The first injected-failure run passed on Vulkan and crashed in OpenGL teardown (cases 260–263 of `wayland-full-GRn6iHqe`). After restoring a valid EGL context during surface destruction, three consecutive OpenGL runs passed both the regular and injected-failure dialog cases. Logs are in `wayland-egl-check-ed9P5d30/{dialog,opengl-2,opengl-3}/`. Logs and images are in the sibling `single-dialog/` directory. In the earlier Blackhole run 767 left-edge pixels changed alpha by at least 3/255 between the unwarped frame and centered lens. The probe now waits for the animated menu drawer to detach before capturing its reference. Both drivers passed the distortion, transparency, restore and resize assertions. For each driver the alpha plane is identical at all 1280×800 pixels between the unwarped frame and the centered lens. Cases 258 and 259 in the private Weston regression contain the images and logs.

The WSL2 Wayland regression has recorded one or more invocations for all
320 NonRobot cases and 22 Robot cases. These runs span multiple builds.
The first 265 NonRobot results are in `wayland-full-GRn6iHqe/tests/`;
the continuation, Robot group and targeted reruns are in
`wayland-rebuild-UCYJ3nrm/` under `agentdir/artifacts/`. The continuation
recorded 39 passes and 18 failures in 57 invocations. It repeated two Intro
cases at its start. Its Vulkan table case finished all eight actions, but
the archive also collected an OpenGL log from a separate Stage rerun and
failed driver verification. The isolated serial rerun passed all four table variants, all four Stage variants and all six file-dialog fixture variants. All four window-icon cases failed because the compositor did not advertise the toplevel icon protocol. See `wayland-egl-check-ed9P5d30/window-recheck/results.csv`.

The private Weston reruns passed the Glass window and render-scale tests in
default and runtime modes on both drivers. The standalone native-window,
menu-click, nested-menu, popup-edge and popup tests also passed on each
driver. Closing an application-modal Stage still failed the immediate
owner-focus assertion. Cases 005–030 of `wayland-rebuild-UCYJ3nrm/recheck/`
contain per-case logs.

On 24 November the private Weston 14 session ran every case against the same
Linux release on the B390. The initial NonRobot run passed 289 of 320, and
the Robot run passed 4 of 22. With targeted reruns, the latest results are
294/320 and 4/22. All 342 entries, their invocation counts and per-case logs
are in `agentdir/artifacts/wayland-release-nOfa55Xe/audit.csv`. The original
two result sets remain in the sibling `nonrobot/` and `robot/` directories.

The four published-module and Shadow consumer tests passed with a local
mirror of public build plugins. The Vulkan hover pixel check initially counted
183 missing-color frames out of 1407, although Java observed no stationary
hover loss. Three Vulkan reruns with per-phase logging passed at 29/1416,
30/1418 and 26/1414. The original miss remains unexplained. The prior
cross-build ledger is in `agentdir/artifacts/wayland-egl-check-ed9P5d30/coverage.csv`.

A subsequent Linux build corrected an incorrect restore notification when a
different Stage was selected. The private Weston task-switcher test passed
with Vulkan and OpenGL in both default and runtime modes. Selecting the main
Stage kept the VFX child iconified. Selecting the child restored its original
400×300 logical bounds and the VFX close button then closed it. Logs for the
four cases are in `agentdir/artifacts/wayland-shell-restore-P8ZWu1G3/`.
These additional cases exercise desktop-initiated restoration. The 342-case
ledger above measures the preceding release.

| Remaining NonRobot cases at this checkpoint | Count | Observation on the private Wayland desktop |
| --- | ---: | --- |
| Native order, window order and window composition | 8 | The compositor manages global positioning and stacking. The composition probes checked per-window content and failed the global-order requirement. |
| Native Stage, native bridge and VFX window controls | 8 | xdg-shell has no client operation to undo minimization. The native Stage probes first completed fullscreen, maximization and return to ordinary bounds on both drivers. |
| Modal and Stage input focus | 4 | The application-modal owner lacked focus when `showAndWait` returned. Weston subsequently focused the previously active native window. In a separate run with a private-seat click on the owner before opening the dialog, the owner regained focus. The Stage input fixture also failed to activate its requested root Stage. Neither local compositor advertises xdg-activation. |
| Window icon | 4 | Neither the local WSLg compositor nor private Weston advertises xdg-toplevel-icon. |
| Window drag | 2 | The fixture constructs a desktop Robot even when selected by the NonRobot group. |

Of the 22 Robot cases, two child-Stage IME cases and two virtual-keyboard contract cases passed. The remaining 18 depend on a desktop-wide input and capture implementation. The separate compositor-driven drag probe verified actual Wayland transfers with GTK on the B390. The published VFX test names account for 42 passing NonRobot cases out of 46, plus two Robot scrolling cases that could not run their gestures. See [Wayland drag and Robot results](glass-godot.md#drag-and-drop-on-linux-wayland) and [VFX evidence](vfx-demo.md#linux-x64-on-wsl2).

On the B390, labwc 0.9.3 advertised both the activation and toplevel-icon
extensions. Its four original window-icon cases passed, including per-window
replacement and teardown. The rebuilt host supplied the seat serial and
surface from the same real event when requesting activation. Both Stage input
cases and all four VFX window-control cases then passed. In each VFX case
the trace recorded keyboard entry on the child after the activation request.
The four task-switcher restoration checks on Weston remained green. The
compositor comparison and traces are in
`agentdir/artifacts/wayland-activation-aPQfvnC7/`.
The bridge fixture now observes host snapshots for up to five seconds after
command acknowledgement, checking that the visible child keeps its owner and
ordinary mode while its parent restores. Both drivers completed this fixture
on labwc and timed out at the same restore requirement on Weston. The latest
labwc results cover 12 passing cases out of 16 selected NonRobot cases.
The outstanding pairs are modal-owner focus on return from `showAndWait` and
the rapid native Stage mode transition, which timed out at step 12 on both
repeat runs. Its full Robot group passed 4/22, with the other eighteen logs
explicitly reporting the missing Glass Wayland Robot backend. See
`labwc-latest.csv` and `robot/results.csv` in the same archive.
The 342-case Weston tally above remains a separate run.

The native Stage step-12 failure on labwc was traced to its window-family
minimization and focus policy. In two independent runs, private-seat Alt+Tab
restored the family and both original probes completed. The unassisted case
remains a failure on both renderers. Subsequent builds also advertise owned
modal Stages through xdg-dialog-v1 when available. All three dialogs in the
nested/application-modal fixture acquired that native role on labwc, and
both backends still failed the immediate owner-focus check. See
[Wayland modal roles and family restoration](glass-godot.md#owned-modal-stages-on-wayland).

A later Vulkan repetition exposed a race between native key delivery and
publication of the JavaFX focus snapshot. The release that records focus in
the key event passed the original Stage input fixture 10/10 times per driver
on labwc. On this release, the 13 selected NonRobot cases passed 11/13
on labwc and 9/13 on Weston. The complete labwc Robot group passed the
two child-Stage IME and two virtual-keyboard cases. Each of its 18 failures
reported the missing Glass Wayland Robot backend.
The final SDK classes and engine library in VFX and both additional
demos matched the local source builds. The repeated checks and hashes are in
`agentdir/artifacts/wayland-key-focus-K1V6MLTx/`.

The native GTK chooser also mapped with the expected parent on an
independent Wayland connection for each driver and each of the two Stage
owners. Alt+F4 canceled all four panels and Java received a null selection.
Results and screenshots are in
`agentdir/artifacts/wayland-family-CCWBZZMD/chooser-close/`.

On isolated native Wayland, the production VFX JAR also completed vertical
and horizontal table drags on both drivers. The six-round VFX navigation
fixture recorded 409 Java and 409 native samples per driver and released
all host-owned resources on exit. By the sixth return to the home page the
private memory and target-material counts were still growing. See the
[table gesture evidence](vfx-demo.md#linux-x64-on-wsl2) and
[six-round measurements](memory-validation.md#recorded-results).

In the private Weston regression, the published modules, Shadow JAR and VFX Demo JAR passed on both drivers. The GodotView default, transformed and runtime fixtures passed on each driver, including the embedded scene's pixel readback, pointer, touch, key routing and resize. Host lifetime, host stop, IME and input-lifecycle cases also passed on both drivers. The Vulkan ownership test exchanged the clipboard between two independent Wayland JVMs. Per-case logs and captures are under `agentdir/artifacts/wayland-full-GRn6iHqe/tests/`.

### Windows and macOS

On 2026-11-21, after the public driver names changed to `d3d12` and `opengl`,
the rebuilt Windows M1 pixel test and Demo smoke launch passed on D3D12,
Vulkan and OpenGL. The Demo also used D3D12 with no driver argument. An ordinary
module-path JavaFX application accepted both new JVM property values and
reported the native drivers `d3d12` and `opengl3`. See
`agentdir/logs/driver-rename-20261121-225048/` and
`agentdir/logs/windows-NonRobot-20261121-225028/`.

The Windows VFX Demo now relies on JavaFX automatic startup. On 2026-11-21
the rebuilt Demo JAR completed smoke runs with the default D3D12 driver, Vulkan
selected by JVM property and OpenGL selected by the Demo argument. A test scene
observed the engine receive `logo` by default and `hidden` with `--no-godot-logo`.
The default module-path run also exercised automatic startup with an imported
directory, a PCK and the shader and effect observers. Evidence is under
`agentdir/logs/auto-start-20261121-223340/`.

On 2026-11-21, Windows x64 was rebuilt from the local driver-interface changes
on root `6eea3f2`, JFX `c77a14c82f` and Godot `25d1e624eb`. The M1 pixel
fixture, render-thread shutdown and the VFX Demo smoke launch passed with each
of D3D12, Vulkan and OpenGL. The OpenGL-only rejection case passed in the full
driver plan. The default module-path suite passed 28 cases and the explicit
OpenGL launch group passed 12, including programmatic driver selection. The
standalone Shadow consumer passed five OpenGL cases. The isolated Demo JAR
passed both with no driver argument (D3D12) and with Vulkan. The three-page
frozen VFX comparison used separate Godot D3D12 and native JavaFX captures. Driver markers and results are in
`agentdir/logs/windows-NonRobot-20261121-220156/`,
`agentdir/logs/windows-NonRobot-20261121-221353/` and
`agentdir/logs/driver-interface-20261121-220439/`.

On 2026-11-21, the standalone Windows M1, Glass window (`-Runtime`) and
GodotView tests passed with no driver or renderer argument. Each engine log
reported D3D12 12_0. The module-path launch group passed all 11 cases,
including conflicting concurrent initialization and a plain JavaFX launch.
Its evidence is in `agentdir/logs/windows-standalone-default-20261121-214954/module-path/`.

The Windows D3D12 regression on 2026-11-21 used the public JVM driver property
for the M1 pixel fixture, render-thread shutdown, nine module-path cases, five
Shadow consumer cases, the isolated Demo JAR and the Demo smoke launcher. All
passed. The M1 fixture also confirmed D3D12 when its scene arguments requested
`gl_compatibility`. Results are under `agentdir/logs/unified-driver-20261121-213049/`.

On 2026-11-21 a projectless JavaFX Shadow JAR, a module-path Application with
no main method and the isolated VFX Demo each launched on Windows using all three Godot drivers. Logs confirmed the
requested backend on the Intel Arc B390. The Shadow JAR and Demo also used
D3D12 when the property was omitted. Empty and unknown values failed at startup.
The per-application logs are under `agentdir/logs/public-driver-20261121-210501/`.

After switching the Windows default to D3D12 on 2026-11-21, a rebuilt,
isolated VFX Demo JAR launched with plain `java -jar` reported D3D12 12_0
on the Intel Arc B390 and passed the window and shutdown checks. The standalone
render-thread shutdown test and the default runner's M1 pixel test also passed.
See `agentdir/logs/vfx-demo-jar-isolated.log` for the default launch.

On 2026-11-21 the Windows driver matrix ran the source-built DLL from the
platform JAR on an Intel Arc B390. Godot reported D3D12 feature level 12_0
and Vulkan 1.4.330 with `mobile`, and OpenGL 3.3.0 with `gl_compatibility`.
The checkout was based on `6eea3f2` with the local driver-matrix and
AccessKit changes. Each driver passed the 35-page VFX Intro run, the
three-round soak with zero host-owned resources at exit, module-path
rendering, Shadow consumers and the isolated Demo JAR.

Of 454 NonRobot cases, 449 passed on the first run. Vulkan clipboard HTML,
modal focus restoration and snapshot stress passed on retry, as did D3D12
clipboard HTML in the standalone fixture project. The OpenGL VFX blackhole
probe failed twice. Its first run lost the distortion after a drag and its
retry showed no distortion at the initial pointer position. In both failing
captures the pixels matched the unwarped snapshot. D3D12 and Vulkan passed
the same assertions. A diagnostic OpenGL run recorded the expected JavaFX
pointer events and lens centers and passed. The original probe then passed
without changes. The cause of the intermittent distortion failure remains open.

All 42 Robot cases passed on their first run. The touch-keyboard fixture
verified Java calls, continued host ticks and cleanup. Windows denied a keyboard
close request, and the fixture does not verify system keyboard visibility.
In total, 491 of 496 entries passed on their first run and all 496 passed at
least once (158 per driver and 22 run once). The local report at
`agentdir/logs/windows-NonRobot-matrix-1795256112868/matrix-summary.csv`
records initial and final exit codes, attempt counts and log paths.

On 2026-11-21 the Windows Editor and packaged shared library both reported
`DisplayServer.FEATURE_ACCESSIBILITY_SCREEN_READER` as unavailable with the
Windows display driver, OpenGL and `--accessibility always`. The rebuilt VFX
Demo passed the Vulkan startup and close check.

Windows x64 passed the six-module Maven packaging checks, all 27 module-path cases, five Shadow consumers and the isolated VFX Demo JAR test. In the November 19 regression, two of 108 NonRobot entries passed on retry after a fixture rename failed. All ten Robot entries passed. [Historical verification](../agentdir/docs/acceptance-status.md).

## macOS arm64 verification scope

On 2026-11-22, a clean source checkout at `64fff7e` (Godot `e6f83ddcd`, JFX `e3f57378`) was rebuilt on Apple M1 with JDK 25.0.5. After staging the modules, `./scripts/test-godot-library.py --runtime artifacts/godot-library --group scene-message` passed on Metal 3.1. JavaFX rejected the invalid calls, the Godot main thread received all five messages in order, including the duplicate, and the application exited with code 0. The log and result are in `agentdir/logs/macos-64fff7e-demos/scene-message/{scene-message.log,results.json}`.

The macOS launchers and test matrix accept `metal` (default) and `opengl`.
The 2026-11-22 cold rebuild on Apple M1 produced the arm64 Godot Editor, shared library, Media-enabled SDK and standalone Demo JAR. The source checkout was `5a65cc6` with local macOS changes, Godot `25d1e624` and JFX `19e43307`. Build logs are in `agentdir/logs/macos-rebuild-{godot-editor,godot-library,jfx,vfx}.log`.

Running `./scripts/maven_local.py install` packaged and installed `1.0.0-7be59b46-73d8b63b`. The module path contained six JARs under the checkout's `.m2/repository/io/vproxy`, with the `mac-aarch64` classifier on graphics and media. Scroll settings, screen layout, render-command validation and all four Metal startup cases passed. The default M1, isolated Glass window and GodotView probes also passed. Evidence is in `agentdir/logs/macos-rebuild-maven.log`, `macos-accepted-module-path.txt` and `macos-standalone-test-*.log`. The [macOS verification checklist](../TESTS.md#跨平台待验证清单) tracks the remaining coverage.

The Lk paused-seek regression required a local AVFoundation change on top of JFX `19e43307`. After rebuilding the SDK, Demo and publication, the 7.434 s seek, decoded-frame assertions and replay passed on Metal, OpenGL and native Mac Glass. A separate Maven consumer compiled `DirectApplication` and tested that classes from all six modules loaded from the project repository. Both `mvn clean verify` and `mvn -o clean verify` passed one test with zero failures, errors or skips and produced the consumer JAR. The final publication passed 33 module-path cases, nine Shadow JAR cases and the isolated Demo JAR check on each driver. The project-local Maven logs are in `agentdir/logs/macos-planar-final/maven-{online,offline}.log`. The per-driver results are entries 002–004 and 007–009 in `agentdir/logs/macos-planar-final-NonRobot/`.

The final AVFoundation build also prefers planar 4:2:0 for video output. Each driver passed three consecutive 1080p60 trials with zero queue backpressure. The Oracle and Lk playback checks passed on Metal, OpenGL and native Mac Glass. Both rebuilt native binaries matched byte for byte across the staged classifier, local Maven classifier and standalone Demo. The SHA-256 values are in `agentdir/logs/macos-planar-final/publication-digests.txt`. See the [format and throughput measurements](media-godot.md#macos-arm64-notes-2026-11-16).

GPU profiling needed a local OpenGL renderer change on top of Godot `25d1e624`. The Apple M1 supplies elapsed-time queries, and the VFX workload uses more queries than the former fixed 256-slot compatibility pool. After rebuilding the editor, shared library and Maven publication, Metal and OpenGL both returned nonzero GPU frame times. The final profiler runs recorded 20 positive GPU frame durations per driver. See the [GPU timing details](frame-benchmark.md) and `agentdir/logs/macos-planar-final/gpu-{metal,opengl}.log`.

A clean checkout ran `setup-env.py` twice with `ANT_HOME` and `JAVA_HOME` unset. Local Git mirrors supplied all three pinned submodule commits. At the time of this run, setup also installed Temurin. JDK 25 is now a system prerequisite. Setup installed Ant, Maven, SCons and the Python dependencies, and prepared both media samples. On the second run it reused the installations and preserved a local JFX edit. The verified tools were Temurin 25.0.5, Ant 1.10.15, Maven 3.9.9, SCons 4.11.1 and Python 3.13.3 with Pillow 13.0.0 and zstandard 0.25.0. See `agentdir/logs/macos-fresh-setup/{setup-1,setup-2,versions}.log`.

On 2026-11-22 the macOS checkout at `5a65cc6` with local script changes passed a full clean. Both SCons clean targets and OpenJFX `cleanAll` completed. A filesystem check before the cold rebuild verified removal of the SDK, native binaries, SCons state, Gradle project caches, generated fixtures and packaged outputs. It also verified retention of the local Maven repository, Gradle dependency cache, tools, media and acceptance archive. Separate temporary fixtures verified dry-run, repeat cleanup and rejection of redirected output paths. Logs are under `agentdir/logs/macos-clean-verified.log`, `macos-rebuild-pipeline.log` and `macos-clean-boundary-tests.log`.

A separate checkout ran `./scripts/clean.py --target jfx` twice. Both Gradle cleans succeeded, removed the SDK output and project cache, and preserved a sentinel in the packaged VFX directory. The log is `agentdir/logs/macos-5a65cc6-diagnostics/isolated-jfx-clean.log`.

The final NonRobot plan comprised 148 Metal, 149 OpenGL and 20 driver-independent invocations. The full run passed 315 of 317. Two OpenGL fixtures observed an intermediate frame. The VFX window-controls fixture now waits for the native window to reach the exact maximized or restored bounds. The window-order fixture allows a newly exposed viewport up to one second to present its first JavaFX frame when the sampled pixel still shows the project clear color. It verifies the top window’s color in each of ten phases. All six affected fixture variants passed five consecutive runs against the same packaged binaries. Two negative checks rejected a maximized width off by one pixel and a window that continued to show the clear color. Matching the results and raw device headers to the plan verified 317 of 317 cases. The original results are in `agentdir/logs/macos-planar-final-NonRobot/results.csv`. The reconciled results and log paths are in `agentdir/logs/macos-planar-final/NonRobot-verified.csv`.

An earlier diagnostic reproduced a transparent red source texture in 9 of 15 Metal window-layer launches when the fixture submitted its one-shot draw during startup. Submitting on the process tick after the first viewport draw passed all 15 diagnostic launches and the original 100-cycle checks on both drivers. Evidence is in `agentdir/logs/macos-layer-setup-comparison/` and the final NonRobot archive.

The final publication passed all 22 Robot invocations on the M1, 11 per driver, with zero skips. All 22 fixture JVMs reported the packaged native bundle, and its extracted engine matched the dylib in the Demo JAR byte for byte. The suite exercised physical drag and drop, hover, native IME, JavaFX Robot input, table scrolling and the macOS virtual-keyboard contract. Results are in `agentdir/logs/macos-planar-final-Robot/results.csv`. The test display reported scale 1.

The standalone Demo JAR showed Godot’s splash at startup and then the VFX welcome screen. With `--no-godot-logo`, the first captured window already showed “Welcome to VFX”. Both launches reported Metal and closed normally. The module-path launch group passed all 12 cases, including `direct-metal`. Explicit Metal and OpenGL launched the isolated Demo. D3D12 and Vulkan both returned exit code 1 with the unsupported driver identified before any device was opened. Logs are in `agentdir/logs/macos-5a65cc6-default-launch.log` and `agentdir/logs/macos-5a65cc6-diagnostics/`. The 17 window captures per mode are under `agentdir/artifacts/macos-5a65cc6-demo-startup/`.

An earlier Apple M1 run tested `28-godot.4:mac-aarch64`. The packaged Demo, 27 module-path cases and nine Shadow cases passed. NonRobot recorded 263 passes and the expected window-icon skip. All 16 Robot cases passed. The three-round soak released all host-owned resources on exit, but resource counts rose between rounds. The results from that publication precede the Maven coordinate change.

The macOS port uses Viewport + safe hosting. The packaged `mobile` renderer
reports Metal 3.1 on this M1. The compatibility renderer uses OpenGL 4.1. Vulkan is not
built (MoltenVK is not installed). Toolchain and build commands are in
[build-macos.md](build-macos.md); test entries are the same-named
`scripts/test-*.sh` runners with the macOS differences listed in
[TESTS.md](../TESTS.md).

- macOS has no per-window icon. The window icon fixture checks the host reports this for both Stages across seven updates. The Dock icon belongs to NSApplication. The
  virtual keyboard entry points report unsupported explicitly. The macOS native component tests exercise Cocoa clipboard and drag data, JNI callback lifetime and keyboard availability.
- The macOS file-dialog fixture answers the same submit/poll/cancel contract
  through a module test hook (`GODOT_JFX_DIALOG_HOOK=1`); panel appearance,
  sheet attachment and physical keyboard interaction are unverified.
  The Cocoa helper and Robot verified physical cross-process drags on both
  renderers. The separate ole-inject fixture uses a private NSPasteboard.
- Media uses AVFoundation. For the native Mac Glass and Prism Metal comparison,
  the video and churn scripts accept `--native`. The Windows process-census
  switches require the Windows APIs.
- Known toolchain limit: Temurin 25.0.5 aarch64 crashes the JVM
  (C2-related) shortly after FFM downcalls, reproducible outside Godot, so
  churn/soak probes sample process RSS via `ps` instead; pass criteria are
  unchanged.
- Windows evidence on this page describes Windows builds and vice versa;
  neither side's results extend to the other platform.

## Current validation limits

- The default 256-slot GPU timestamp pool can overflow during diagnostics.
  Direct-offscreen GPU samples can remain zero because of timestamp-map lifetime;
  zero is not zero GPU cost. Window samples come directly from the transition
  fixture's viewport. See [frame-benchmark.md](frame-benchmark.md).
- The unsupported-mode rejection test uses OpenGL. A Vulkan/separate negative
  attempt also exposed an engine shutdown-thread error after removing its host
  adaptation; clean shutdown of that unsupported configuration is not claimed.
- GPU screenshots, build success, resource-count cleanup and Robot checks each
  cover different scopes. Mixed-monitor DPI, broad physical IME behavior,
  touch-keyboard visibility, OS drag-preview appearance and physical audio/A/V
  synchronization remain incomplete. System menus are unsupported.
- 3D and WebKit are outside the requested scope. Prism-Godot rejects unsupported
  depth/perspective, MSAA and mipmap paths. Node shaders do not support extra
  sampler uniforms or geometry extending beyond input bounds.
- Memory observations are bounded workloads, not an unlimited leak-free claim.
  See [memory-validation.md](memory-validation.md) and [media-godot.md](media-godot.md).
  Occasional long-frame repairs are deferred; the user waived the white-edge issue.

## Architecture and implementation requirements

| Objective section | Current evidence | Remaining acceptance |
| --- | --- | --- |
| 3.1, 5: sole Godot host and JavaFX thread semantics | JavaFXHost, Glass-Godot scheduler, native-window transport and Prism command queue; scheduler, host-stop, pulse-stop and shutdown probes | Broader timing/performance and physical interaction |
| Stage correction | Primary uses root Window; secondary Stage/Popup use force_native JavaFXNativeWindow. Native-stage, input, modality, owner lifetime, VFX window-control and churn probes | OS-desktop screenshots and real mixed-monitor behavior |
| 3.2, 4.1: GPU 2D primitives, glyphs, textures, clipping and blending | Prism-Godot BaseShader integration, bridge/render-target/composite probes, VFX 35-page GPU captures at scale 2 | Representative cadence passes; occasional long frames, broader workloads and physical display timing remain unverified |
| Controls, CSS and FXML | Controls/CSS exercised by Stage/VFX fixtures; test-fxml.ps1 verifies FXMLLoader, fx:include, bundle/location injection, initialize, private handlers, relative CSS/GPU color, Chinese text input and a second independent Stage on GL/Vulkan/Runtime | Representative FXML coverage; arbitrary custom component/module/controller combinations are not exhaustive |
| 4.2: 2D effects | 39-case effects fixture, standard effect chains and all Blend modes, GL/Vulkan comparisons | Not every parameter/extreme combination; see prism-godot.md for supported paths |
| 4.3: per-node CanvasItem shader | GodotShaderEffect, node-shader fixture with uniforms, UVs, clip/opacity and chained effect | Additional sampler uniforms and geometry beyond input bounds are unsupported |
| 4.4: GodotView | Public Region/peer, live GPU SubViewport, resize/reload/clip/opacity and mouse/key/touch probes; combined scale/shear/translation has GL/Vulkan/Runtime evidence with D3D clip reference | Logical-resolution output on HiDPI; arbitrary transform and physical interaction stress incomplete |
| 6: Glass adapters | Application/Window/View/Screen/Timer, window-addressed input, text/HTML/RTF clipboard, cursors and synthetic/native IME probes | See validation limits above; physical IME candidate/conversion behavior unverified |
| 7: source builds | Shared engine with JNI bridge, resource editor and source OpenJFX SDK builds; Media-enabled SDK now includes all four native Media libraries | WebKit excluded by user; godot-cpp is not used |
| 8: M0–M6 flow | Architecture, build scripts, module, standard Stage, NodeShader, GodotView and original VFX implementations exist | Milestones are not blanket-accepted while explicit gaps remain |

## Section 9 acceptance items

| Item | Evidence and limit |
| --- | --- |
| 1: real VFX startup | Source-built SDK + original VFX Intro; 35-page runs complete |
| 2–3: controls, positions, dimensions, hierarchy | Paired GPU captures with stock D3D; targeted native-window, popup, menu and table tests. Not exhaustive control coverage |
| 4: Chinese/English text and layout | Reference scene, text input/IME and table edit captures; physical IME remains open |
| 5–6: images, gradients, alpha, transforms, clips | Prism/effect/GodotView fixtures and page captures; representative coverage |
| 7: effects | 39-case GL/Vulkan image comparison evidence |
| 8: node shaders | Per-node fixture verifies shader output and uniform updates |
| 9–10: embedded Godot scene and mixed content | GodotView fixture verifies scene texture, sibling order, clip, opacity and input |
| 11: mouse, keyboard, focus | Host-injected interaction probes, including original VFX table, dialog, loading/cancel and animation graph. Robot fixtures pass; broader physical-device acceptance remains incomplete |
| 12: resize and rendering | Native Stage/VFX resize, maximize/restore and render-scale fixtures; real monitor transitions missing |
| 13: no visible defects/flicker | GPU captures inspected, including full-page D3D triage; GPU motion and near-60 average cadence pass; OS-desktop visuals and occasional long frames remain open |
| 14: no sustained memory/GPU leak | 180-cycle no-forced-GC Stage tests; WinRT callback and Vulkan descriptor retention fixed; corrected 537-second real-Demo three-round soak, stable homepage native resources and final-zero cleanup |


Item 14 has subsequent six-round evidence documented in
[memory-validation.md](memory-validation.md). Exit-time resource cleanup alone
does not establish stable process or driver memory during arbitrary workloads.
The subsystem evidence above and below spans multiple dated builds; it must not
be represented as a single complete retest of the latest build.

## Delivery

Source and subsystem documentation are indexed in [README.md](../README.md).
Build outputs are `godot/bin/`, `jfx/build/sdk/` and `artifacts/vfx/`.
GPU captures are under `artifacts/reference/`; they are not OS desktop captures.
