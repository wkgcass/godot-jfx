# Acceptance status

Last checked on Windows x64 and macOS arm64 on 2026-11-19. This page describes the supported configuration and
validation limits. Earlier implementation rounds and removed-mode measurements
are historical evidence in [progress](progress.md) and Git history; current
commands are in [TESTS.md](../TESTS.md).

## Supported configuration

Windows x64 and macOS arm64 have source-built platform JARs. See the platform sections below for execution evidence.
JavaFX hosting uses **Viewport + safe**, with Godot `mobile` (Vulkan on the
validated Windows configuration, Metal 3.1 in the packaged macOS library on M1) or `gl_compatibility`
(OpenGL). The custom
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

### Windows x64 after the macOS adaptation (2026-11-19)

Windows x64 ran root revision `751bac7` with Godot `25d1e624eb`,
OpenJFX `c77a14c8`, VFX `4a92c505` and Temurin 25.0.3+9. The Editor,
engine DLL, Media-enabled SDK and VFX Demo JAR were rebuilt from clean source
revisions. The Windows graphics classifier and Demo JAR contained the rebuilt
DLL (SHA-256 `ad23bcbf443a3a19c5a748c63553c102138f3023e8b3d033ce4f270a223b780a`)
and the same `QuantumToolkit.class` as the SDK.

`scripts/run-windows-tests.ps1 -Group NonRobot` passed 106 of 108 entries
on the first run. Both `test-startup` and `test-blit` stopped before JavaFX
startup when Windows denied the rename that publishes the imported fixture
directory (WinError 5). The next scene fixture published the cache. Both
failed entries then passed with their original arguments, giving all 108
entries a passing result. Three additional runs of the same fixture helper,
each with a fresh project cache, also published successfully. The cause of
the initial rename denials remains undetermined.

The rebuilt Editor imported a project with empty project and Editor caches
and exported its PCK. The packaged runtime passed animation-callback exit,
logical window input and pixels at 2× scale, owned-window ordering, transparent
Stages and 36 Stage churn cycles. All 27 module-path cases, five Shadow cases
and the isolated interactive VFX JAR passed. The Vulkan VFX soak completed
three round trips through 35 pages and released all host-owned resources at
exit.

Build logs, `results.csv`, `reruns/results.csv`, cold-import logs and
`reruns/fresh-fixtures.json` are under
`artifacts/logs/macos-merge-751bac7-nonrobot-20261119-152552/`.

On the same Windows build, `scripts/run-windows-tests.ps1 -Group Robot` ran
all ten entries serially with their default renderers. All ten passed on
the first run. In eight real-pointer cycles, the Vulkan VFX hover probe
recorded eight entries and zero flickers. All 880 settled frames over the
button met the bright-pixel threshold and all 310 settled frames over the
gap met the dark-pixel threshold. The touch keyboard probe verified Java
calls, host ticks and cleanup. Windows denied the dismiss request
(`0x80070005`), so system keyboard visibility and dismissal remain unverified.
The run directory `artifacts/logs/macos-merge-751bac7-robot-20261119-162436/`
contains `results.csv`, the per-entry logs, `hover-demo-mobile-safe.log` and
`virtual-keyboard.log`.

### Packaged-library-only host on Windows x64 (2026-11-18–19)

The Windows source build produced the shared Godot library and Media-enabled
JavaFX SDK. The graphics classifier and full VFX JAR contain the same
`godot.dll`, SHA-256 `f3422d267e21b791e5736d082c1503996969c39ae9722030639f569bfdb0624c`.
The editor is built separately for asset import and export. Scene fixtures
check the DLL loaded by their Java PID against the graphics JAR. Production
JavaFX modules and the Demo JAR exclude the fixture's Java launcher.

The Windows group runs used the rebuilt modules under the previous
`28-godot.3` coordinates. All eight module JARs have byte-identical file
contents under the final `28-godot.4` coordinates. The first run passed
106/108 NonRobot entries, including all 27 module-path cases, all five
Shadow cases, the isolated VFX JAR, and three complete 35-page soak rounds.
The window-order probe exceeded its 30-second limit while waiting a fixed
number of frames per phase. With each phase acknowledged by a fresh capture
of the verified top window, all ten phases passed twice on OpenGL and once
on Vulkan/mobile. The final `28-godot.4` publication passed all 27 module-path
cases, all five Shadow cases, Media audio/video, both Demo JAR launch scripts
and the isolated VFX JAR responsiveness and shutdown check.

The clipboard test initially failed in both fixture directories. Java reported
that it could not open the Windows clipboard. The first Robot run passed
native IME, the system file dialog and touch-keyboard call/liveness checks.
Seven entries failed: Robot desktop pixels, external drag and drop, hover
demo, drag and drop, physical drag, hover flicker and VFX table scrolling.
The Windows session reported a locked desktop and an independent
`OpenClipboard` call returned access denied. After unlocking Windows, clipboard
interoperability passed in both the normal and isolated fixture directories.
All ten Robot entries then passed together on the final publication. The
touch-keyboard result covers Java calls, live host ticks and teardown. The
script does not assert OS keyboard visibility. Including the two successful
targeted reruns, all 108 NonRobot entries have a passing result.
The original results and reruns are under `artifacts/logs/packaged-host/` in
`NonRobot/`, `Robot/`, `release-4/` and `unlocked/`.

### Windows regression using the packaged engine (2026-11-18)

The Windows scene fixtures launch JDK 25 on the classpath with the published
`28-godot.3` Windows graphics and Media JARs. Each process records its PID
and checks the loaded `godot.dll` against the JAR resource. The rebuilt engine
for this run has SHA-256 `91739701b56c4e138e038eb2075195a7c88a0338adf732466bf233942786cb81`.
Scene-driven tests retain their Godot observers. The module-path, Shadow and
isolated VFX Demo cases exercise normal Java application startup.

All 108 NonRobot entries and all 10 Robot entries passed. The NonRobot
group includes 27 module-path cases, five Shadow cases and the interactive
VFX Demo JAR test. The three-round mobile soak visited 35 pages and reported
zero owned resources at shutdown (506.6 seconds). Both renderers passed
the input-cancellation and six-phase composition probes. Glass windows,
FXML, Media video and the system dialog with host shutdown also passed in
isolated fixture directories.

The results are in `artifacts/logs/dll-regression/NonRobot/results.csv` and
`artifacts/logs/dll-regression/Robot-final/results.csv`. The first Robot
run recorded a drag timeout before the first drop. The Robot driver now
focuses the source window before the gesture and waits for the source to
receive the press. Three OpenGL runs and one mobile run of that driver
completed all seven gestures and three drops; their results are in
`Robot-final/drag-repeats.csv` under the same log directory. The touch keyboard probe
passed its call and liveness assertions. Windows denied the dismiss request,
so this run provides no confirmation that the OS closed the keyboard.

### Packaged VFX Intro Demo on Windows x64 (2026-11-18)

The complete `artifacts/vfx/libs/vfx-demo.jar` built with Shadow against the
`28-godot.3` platform artifacts contains all 35 Intro page classes and the VFX
resources. Only the JAR was copied into a fresh directory. With a JDK-and-system
PATH, `java -jar vfx-demo.jar` opened the original interactive VFX Intro window.
The Java process mapped the packaged Godot DLL, handled a window close request
and exited with code 0. The directory still contained only the JAR after exit.

The PowerShell JAR launcher passed smoke on Vulkan/mobile and OpenGL, and the
shell JAR launcher passed on Windows under Git Bash. The module-path and Shadow consumer cases also passed. Interactive and
smoke logs are in `artifacts/logs/vfx-demo-jar/`.

An interactive launch exposed a gap in the original smoke check. Windows
replaced the Intro with a “Not responding” ghost window even though the real
window could answer synchronous messages and exit cleanly. The Windows library
host disables ghosting once before Godot
creates its windows. The policy lasts for the lifetime of the JVM process.
On both Vulkan/mobile and OpenGL, Windows reported the idle Intro as hung
without creating a ghost window. After 20 seconds idle, two pairs of native
clicks advanced to the VStage page and returned to the welcome page. A JavaFX
observer verified the page after each click, and both processes closed cleanly.

The Windows backend also loads predefined arrow, hand and text cursors from
the system. On this build, asking the Godot DLL for those same resources
returned null for all three. A manual retest from the original terminal
confirmed a visible pointer inside the Intro and working Next and Previous
buttons with the default PowerShell launcher.

### Java-launched single JAR on Windows x64 (2026-11-18)

JDK 25 launched the final Shadow consumer from a separate directory with `java -jar app.jar`. The controls-only artifact was 37,936,329 bytes. It contained the Windows graphics classifier and zero PCK files or Media DLLs. It showed a transparent primary Stage, resized it to 312 × 208 and showed an owned second Stage. The same artifact passed in a working directory containing an unrelated `project.godot` with an invalid main scene.

The Media artifact decoded a local MP4, paused, sought and replayed it. The GodotView artifact displayed the expected green scene pixel in the main window, kept a second native window open and handled a Godot-injected click. The resource pack's own main scene would exit with code 19 if launched. A separate invalid pack produced a resource initialization error and a nonzero process exit.

Each successful case recorded the original Java PID and verified the loaded Godot DLL against the JAR bytes. Media also checked the decoder and plugin DLLs in that process. The engine DLL SHA-256 for that run was `20e22ffc06ba1be9cf7058b2ea0d0dec3d51fa7ba22d4821b89e8d3604529ef4`. The current sample JARs can be built and exercised with `scripts/test-shadow-jar.py`. Gradle logs, per-process module lists and GPU captures are in `artifacts/logs/projectless-final-consumers/shadow/`. [Runtime and packaging specification](godot-library-spec.md).

All 27 module-path checks passed against the same engine and six Maven-resolved modules. The cases covered projectless automatic and explicit initialization, concurrent requests, failure propagation, imported directories and external packs, rendering, synthetic input, video replay and process exit. Commands, exit codes, native module paths and GPU captures are in `artifacts/logs/projectless-final-consumers/modules/`.

## macOS arm64 verification scope

On 2026-11-19 the standalone VFX Intro JAR ran from a separate directory on
macOS 26.6.2, Apple M1, Temurin 25.0.5+8. The original Java PID mapped the
embedded `libgodot.dylib`. Real clicks opened the menu, selected the VStage
page, and closed the window. The application exited with code 0 and left only
the JAR in its directory. Captures and the observed Java PID, engine path, and
JAR hash are in `artifacts/reference/vfx-portable/`.

The macOS publication is `28-godot.4:mac-aarch64`. It was built and tested
before the changes were committed. Root revision `b7a5cd4` records the tested
source and fixtures, including Godot `25d1e624eb`, OpenJFX `c77a14c8`,
and VFX `4a92c505`. The source-built engine SHA-256 is
`41f67447e40ef9a5e35e51a814e4067c2d2089eca0730ffbdedb4c541bc7fd58`.
The isolated consumer tests inspected the native cache in the Java process,
including the decoded frame's AVFoundation library. All 27 module-path cases
and nine Shadow cases passed. They cover explicit and implicit startup,
independent Stages, Unicode paths, scene packs, invalid dependencies, native
Mac Glass cold/warm/concurrent caches, and Media controls. Logs and PID/module
observations are in `artifacts/logs/macos-nonrobot-accepted/`.

With this final build, the serial NonRobot run passed 263 of 264 entries.
The remaining entry, the per-window icon test, reported its macOS platform
skip. All 16 Robot entries passed on the same build. Together the groups
exercised all 107 macOS shell test entry points. The desktop had a single
1920×1080, 60 Hz display at scale 1. The results include both renderers, the
real cross-application drag, pointer and keyboard input, native IME, hover
pixels, and table dragging. Commands, exit codes, and individual logs are
indexed in `artifacts/logs/macos-nonrobot-accepted/results.csv` and
`artifacts/logs/macos-robot-accepted/results.csv`. The distributed VFX JAR
SHA-256 is `387f19e378029017b48a928c9f9860c8ad6ceabb839ae31f6c2216d84888ef4d`.

Both renderers produced 35 GPU captures at 1280×800. The page reports are
`artifacts/reference/vfx-pages-mobile/run.json` and
`artifacts/reference/vfx-pages-gl_compatibility/run.json`. The 70 images are also collected in
`artifacts/logs/macos-nonrobot-accepted/vfx-pages-*.jpg`. Each renderer
completed three round trips through the 35 pages with a 256 MiB Java heap.
Each recorded 205 Java samples and 205 native samples and released all
host-owned resources on exit. While the application was open, the round-end
resource counts rose from 7,953 to 9,286 on Metal and from 7,770 to 10,107 on
OpenGL. Longer-running memory stability remains unverified. The per-round
observations are in `artifacts/reference/vfx-soak-*-3-heap256.analysis.json`.

Both renderers passed all ten owned-window stacking and pixel checks, all
six composition phases, and seventeen native ordering phases. Each passed
three consecutive 36-cycle Stage churn tests; see
`artifacts/logs/macos-window-order/` and `artifacts/logs/macos-stage-repeats/`.
The source editor also completed a headless import with a new, empty editor
cache (`artifacts/logs/macos-cold-import.log`).

The macOS port uses Viewport + safe hosting. The packaged `mobile` renderer
reports Metal 3.1 on this M1. The compatibility renderer uses OpenGL 4.1. Vulkan is not
built (MoltenVK is not installed). Toolchain and build commands are in
[build-macos.md](build-macos.md); test entries are the same-named
`scripts/test-*.sh` runners with the macOS differences listed in
[TESTS.md](../TESTS.md).

- Explicit platform outcomes: `test-window-icon.sh` SKIPs by design (macOS
  has no per-window icon; the Dock icon belongs to NSApplication); the
  virtual keyboard entry points report unsupported explicitly (no Windows
  touch keyboard exists). Windows-only native component tests
  (`test-clipboard-ownership.cmd`, `test-dnd-drag-image.cmd`,
  `test-dnd-helper-lifetime.cmd`, `test-tabtip-result.cmd`,
  `make-media-fixture.ps1`) are not applicable to macOS.
- The macOS file-dialog fixture answers the same submit/poll/cancel contract
  through a module test hook (`GODOT_JFX_DIALOG_HOOK=1`); panel appearance,
  sheet attachment and physical keyboard interaction are unverified.
  The Cocoa helper and Robot verified physical cross-process drags on both
  renderers. The separate ole-inject fixture uses a private NSPasteboard.
- Media runs the AVFoundation backend; the macOS runners reject the unported
  `--runtime`/`--native-d3d`/process-census modes explicitly (exit 2), which
  marks the mode as unavailable rather than failed.
- Known toolchain limit: Temurin 25.0.5 aarch64 crashes the JVM
  (C2-related) shortly after FFM downcalls, reproducible outside Godot, so
  churn/soak probes sample process RSS via `ps` instead; pass criteria are
  unchanged.
- Windows evidence on this page describes Windows builds and vice versa;
  neither side's results extend to the other platform.

## Current validation limits

- Default GPU diagnostics overflowed the 256-element timestamp pool. The
  diagnostic rerun used 8192 temporarily and restored the project configuration.
  The failure log is `artifacts/dead-code-audit/table-default-timestamp-limit.log`.
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
`./scripts/write-delivery-inventory.ps1` refreshes the generated revision/output
inventory. Source hashes connect evidence to a build but do not prove acceptance.
