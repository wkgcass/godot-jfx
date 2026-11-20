# acceptance-status — historical verification

Paths under `agentdir/artifacts/` locate evidence archived from the Windows workspace. Other `artifacts/` paths refer to the checkout and platform used for that run.

### Maven coordinate migration on Windows x64 (2026-11-19)

With the packaging changes on top of root revision `77d13fc`, the existing
source-built Windows SDK and engine were packaged as six `io.vproxy:godot-jfx-*`
modules at version `1.0.0-7be59b46-73d8b63b`. All six POMs and the two
`win` classifiers were checked. All 27 module-path cases and five independent
Shadow consumer cases passed. Gradle resolved the new coordinates alongside
`io.vproxy:commons` and rebuilt the VFX Demo JAR. Evidence is under
`agentdir/artifacts/logs/maven-coordinates-modules/`, `maven-coordinates-shadow/`
and `maven-coordinates-demo.log` in the same log directory. macOS arm64
verification of the new coordinates is tracked in [TESTS.md](../../TESTS.md).

The Windows Maven Local installation of this version contained six POMs and
eight JARs matching staging. The scroll-settings, screen-layout and render-command
probes passed using the six resolved local modules. The shared scene launcher
passed its four startup cases, FXML and Media video on Vulkan/mobile. In the
same checkout, the module-path release test downloaded all eight JARs from the
staging repository into a fresh cache and passed all 27 cases. All five Shadow
cases also passed using the staged repository. The install log
is `agentdir/artifacts/logs/maven-local-install.log` and the test logs are under
`agentdir/artifacts/logs/maven-local-windows-20261119-213913/`.

After pinning the development-test repository to this checkout's `.m2/repository`,
Windows reinstalled all six POMs and eight JARs there and compared their contents
with staging. The three probes and four Vulkan/mobile startup cases passed with
the new paths. Logs are in `agentdir/artifacts/logs/project-m2-20261119-220827/`.

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
`agentdir/artifacts/logs/macos-merge-751bac7-nonrobot-20261119-152552/`.

On the same Windows build, `scripts/run-windows-tests.ps1 -Group Robot` ran
all ten entries serially with their default renderers. All ten passed on
the first run. In eight real-pointer cycles, the Vulkan VFX hover probe
recorded eight entries and zero flickers. All 880 settled frames over the
button met the bright-pixel threshold and all 310 settled frames over the
gap met the dark-pixel threshold. The touch keyboard probe verified Java
calls, host ticks and cleanup. Windows denied the dismiss request
(`0x80070005`), so system keyboard visibility and dismissal remain unverified.
The run directory `agentdir/artifacts/logs/macos-merge-751bac7-robot-20261119-162436/`
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
The original results and reruns are under `agentdir/artifacts/logs/packaged-host/` in
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

The results are in `agentdir/artifacts/logs/dll-regression/NonRobot/results.csv` and
`agentdir/artifacts/logs/dll-regression/Robot-final/results.csv`. The first Robot
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
smoke logs are in `agentdir/artifacts/logs/vfx-demo-jar/`.

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

Each successful case recorded the original Java PID and verified the loaded Godot DLL against the JAR bytes. Media also checked the decoder and plugin DLLs in that process. The engine DLL SHA-256 for that run was `20e22ffc06ba1be9cf7058b2ea0d0dec3d51fa7ba22d4821b89e8d3604529ef4`. The current sample JARs can be built and exercised with `scripts/test-shadow-jar.py`. Gradle logs, per-process module lists and GPU captures are in `agentdir/artifacts/logs/projectless-final-consumers/shadow/`. [Runtime and packaging specification](../../docs/godot-library-spec.md).

All 27 module-path checks passed against the same engine and six Maven-resolved modules. The cases covered projectless automatic and explicit initialization, concurrent requests, failure propagation, imported directories and external packs, rendering, synthetic input, video replay and process exit. Commands, exit codes, native module paths and GPU captures are in `agentdir/artifacts/logs/projectless-final-consumers/modules/`.

## macOS arm64 verification scope

On 2026-11-19 the standalone VFX Intro JAR ran from a separate directory on
macOS 26.6.2, Apple M1, Temurin 25.0.5+8. The original Java PID mapped the
embedded `libgodot.dylib`. Real clicks opened the menu, selected the VStage
page, and closed the window. The application exited with code 0 and left only
the JAR in its directory. Captures and the observed Java PID, engine path, and
JAR hash are in `artifacts/reference/vfx-portable/`.

The macOS publication tested in that run was `28-godot.4:mac-aarch64`. It was built and tested
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

## GPU timestamp capacity

- Default GPU diagnostics overflowed the 256-element timestamp pool. The
  diagnostic rerun used 8192 temporarily and restored the project configuration.
  The failure log is `agentdir/artifacts/dead-code-audit/table-default-timestamp-limit.log`.
