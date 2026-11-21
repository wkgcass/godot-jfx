# Acceptance status

Last cross-platform review on 2026-11-19. This page describes the supported configuration and
validation limits. Earlier implementation rounds and removed-mode measurements
are historical evidence in [progress](../agentdir/docs/progress.md) and Git history; current
commands are in [TESTS.md](../TESTS.md).

Tests write logs under `agentdir/logs/` and captures under `artifacts/reference/`. The [archived run reports](../agentdir/docs/acceptance-status.md) identify the original logs and captures for each platform.

## Supported configuration

Windows x64 and macOS arm64 have source-built platform JARs. See the platform sections below for execution evidence.
Both platforms build the Godot Editor and shared library with `accesskit=no`,
which disables Godot's screen-reader integration.
JavaFX hosting uses **Viewport + safe**, with Godot `mobile` (D3D12 by default
on Windows, Vulkan when selected, Metal 3.1 in the packaged macOS library on M1) or `gl_compatibility`
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

The macOS launchers and test matrix accept `metal` (default) and `opengl`.
The shell argument forwarding and both regression plans were checked on Windows.
Rebuilding the matching SDK, engine and JARs and running each driver on Apple
silicon remain pending. [macOS verification checklist](../TESTS.md#跨平台待验证清单)

On Apple M1 the tested publication was `28-godot.4:mac-aarch64`. The packaged Demo, 27 module-path cases and nine Shadow cases passed. NonRobot recorded 263 passes and the expected window-icon skip. All 16 Robot cases passed. The three-round soak released all host-owned resources on exit, but resource counts rose between rounds. Verification of the new Maven coordinates on macOS remains tracked in [TESTS.md](../TESTS.md).

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
  `test-dnd-helper-lifetime.cmd`, `test-tabtip-result.cmd`) and the Media
  Foundation fixture generator require Windows.
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
