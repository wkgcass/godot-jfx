# Godot-hosted JavaFX for Windows x64 and macOS arm64

JavaFX loads the Godot engine from its platform JAR in the application JVM.
The Prism-Godot and Glass-Godot backends use the engine for the event loop, native windows and GPU work.
JavaFX retains its Application Thread, render jobs, scene graph, controls, CSS
and FXML. The primary Stage uses the Godot root window; additional Stages use
independent Godot-owned native windows. GodotView embeds a Godot 2D scene inside
JavaFX, and GodotShaderEffect applies CanvasItem shaders to individual nodes.
Windows x64 is the reference platform. The macOS arm64 library targets Metal and OpenGL. Build steps are in
[macOS source builds](docs/build-macos.md) and platform-specific limits in the
macOS sections of [acceptance status](docs/acceptance-status.md) and
[TESTS.md](TESTS.md).

The VFX Demo builds against the local JavaFX SDK. Its Intro menu now includes an
optional Blackhole Effect on the Demo content VSceneGroup and a Ripple Effect
on the entire main window, both using Godot shaders;
VFX also provides a cached Godot backend detection helper. This is an active
implementation, not a declaration of complete JavaFX
compatibility. See [acceptance status](docs/acceptance-status.md) for evidence and
remaining work. The user's remaining white-edge issue is explicitly waived.

## 阅读入口

- [AGENTS.md](AGENTS.md)：构建、运行、仓库约束与文档地图。
- [TESTS.md](TESTS.md)：按用途选择测试，查看前置条件、命令和验收方式。
- [架构说明](docs/architecture.md)：从组件分工到画面、输入、线程和资源生命周期。

## Build and run

The preferred way to open the full VFX Intro Demo is to run its platform-specific
Shadow JAR with JDK 25. You can copy the JAR to another directory or machine
of the same OS and architecture.

```sh
java -jar artifacts/vfx/libs/vfx-demo.jar
```

**Supported graphics drivers**

| Platform | Default driver | Other supported drivers |
| --- | --- | --- |
| Windows x64 | `d3d12` (Direct3D 12) | `vulkan`, `opengl` |
| macOS arm64 | `metal` | `opengl` |

JavaFX applications and the VFX Demo start Godot automatically with the platform default.
To select a driver, pass `-Djavafx.godot.driver=<driver>` before `-jar` or the main class.
For example, `java "-Djavafx.godot.driver=vulkan" -jar artifacts/vfx/libs/vfx-demo.jar`
selects Vulkan on Windows. The Demo also accepts `--driver` after the JAR name, such as
`java -jar artifacts/vfx/libs/vfx-demo.jar --driver opengl` on either platform.
Neither form requires a Godot project file.

To confirm the active driver, read the graphics API at the start of the engine’s
`Using Device` line. For example, `OpenGL API … - Using Device: …` identifies
OpenGL and the GPU. The corresponding engine marker is `GODOT_LIBRARY_DRIVER opengl3`.

Both `scripts/run-vfx-demo.ps1` and `scripts/run-vfx-demo.sh` launch this JAR
by default. Add `-Smoke` on Windows or `--smoke` on macOS for a bounded run.
Build the Windows x64 JAR on Windows and the macOS arm64 JAR on macOS.
The standalone Intro JAR has been launched on both platforms. See [acceptance status](docs/acceptance-status.md).

Use PowerShell 7.4.1 or later (`pwsh`) at this directory (macOS uses the shell equivalents in
[macOS source builds](docs/build-macos.md)). The scripts use JDK 25 from `JAVA_HOME`
(or an explicit `-Jdk` override), Visual Studio 2022/MSVC, Windows SDK and
SCons 4.10.1.
For initial dependency setup and alternate JDK paths, follow
[Windows source builds](docs/build-windows.md). Run native builds sequentially.

```powershell
python scripts/setup-env.py
.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-vfx.ps1
```

On macOS arm64, run the corresponding commands from the repository root.

```sh
./scripts/setup-env.py
./scripts/build-macos.sh --target godot-editor
./scripts/build-macos.sh --target godot-library
./scripts/build-macos.sh --target jfx
./scripts/build-vfx.sh
```

To preview a project clean, run `python scripts/clean.py --dry-run` (macOS:
`./scripts/clean.py --dry-run`). Omit `--dry-run` to clean the current
platform's Godot editor and shared library with SCons, run OpenJFX's Gradle
`cleanAll --no-problems-report`, and remove local package outputs and generated Godot test projects.
Use `--target godot-editor`, `godot-library`, `jfx`, `packages` or `test-projects`
to clean one part. A full clean removes the entire shared `godot/bin` directory
after both SCons targets finish. It also removes `.scons_env.json`,
`.scons_node_count`, `.sconsign5.dblite`, and `platform/windows/msvc_capture.log`
under `godot/`. After all targets finish, the full clean removes Python
`__pycache__` directories under `godot/`, `scripts/` and `native/`.
Cleaning an individual Godot target keeps the shared build
state and the other target's outputs. The packages target
removes `artifacts/vfx`, the entire default staging directory
`artifacts/godot-library` (all staged versions), and `tests/library/shadow/build`.
The `test-projects` target removes directories matching `artifacts/runtime-*`
and `artifacts/scene-fixtures-*`, including their Godot import caches. It also removes
`artifacts/vfx-gpu-profile/` and `tests/godot/.godot/`, including local editor
state. Tests recreate the projects they need from `tests/godot`. The same target
cleans `artifacts/pulse-stop-patch/` and `artifacts/texture-cancellation-patch/`.
Both probes recompile their module patches from the JFX sources on every run.
It also removes `artifacts/native-tests/`. The Windows and macOS test scripts
rebuild their native tests and helpers from repository sources when needed.
It removes the entire `artifacts/reference/` directory, including compiled
probes, generated fixtures, screenshots and reports. Archive any results you
want to keep before cleaning.
Audio tests create missing WAV, MP3 and AIFF fixtures in `agentdir/media/`
and reuse them across runs and project cleans.
Installed Maven artifacts, tool and dependency caches, and test logs in
`agentdir/logs` are retained. Close running tests or
demos before cleaning their outputs.

Before cleaning JFX, the script runs the JFX wrapper with `--stop` using this
checkout's `.gradle-cache` as its Gradle User Home. After
`cleanAll --no-problems-report --no-daemon` exits successfully, the script
removes `jfx/.gradle` and `jfx/buildSrc/.gradle`. The packages target removes
`scripts/vfx-build/.gradle` and `tests/library/shadow/.gradle`, stopping the
same daemons first when run on its own with either directory present.
The OpenJFX clean also removes `jfx/buildSrc/build` and suppresses the HTML
report in `jfx/build/reports`. It invokes Apache Ant for the sample applications.
The JFX scripts use `ANT_HOME` when set and otherwise use
`.tools/apache-ant-1.10.15` in the checkout. Run `python scripts/setup-env.py`
on Windows or `./scripts/setup-env.py` on macOS to initialize missing Godot,
JFX and VFX submodules and prepare the build dependencies under `.tools/`.
The submodule URLs in `.gitmodules` use GitHub SSH. Setup prepares the Oracle
sample and `Lk.mp4` in `agentdir/media/` and reuses each after checking its
SHA-256. See the [Windows](docs/build-windows.md#tool-installation-paths) and
[macOS](docs/build-macos.md#toolchain) guides for system prerequisites.

On Windows, the launcher, regression runner and individual rendering tests default to Godot D3D12 (`mobile`)
with `safe` threading. Use `scripts/run-windows-tests.ps1 -Group NonRobot -Test test-godot-view`
for a focused run. Add `-Driver vulkan` or `-Driver opengl` for another backend,
`-Driver all` for all three, or `-List` to preview the selected cases.
The Windows JFX build uses existing MSYS make/cygpath and UCRT64 GCC, builds its pinned
makedepend helper inside `.tools`, and stages source-built Media libraries into
the SDK. See build-windows.md for prerequisites and current validation status.
Use `-Driver opengl` for OpenGL. JavaFX hosting supports only
Viewport rendering with `safe` threading; the custom RD-direct backend and
separate-thread host support have been removed. Godot's own RenderingDevice
remains available to the engine. `-Smoke` runs a bounded startup/close check;
the normal launcher remains interactive until the Demo is closed.

## Implementation and delivery map

On Windows x64 and macOS arm64, a JavaFX application can ship as a single Shadow JAR and start with `java -jar app.jar` on JDK 25. The application's Stage controls the window. A regular application needs no Godot project. An application that embeds a custom GodotView scene can include its resource pack in the same JAR. Build the source SDK and publish its platform artifacts for the application build. [Single-JAR specification](docs/godot-library-spec.md) · [Windows build instructions](docs/build-windows.md#java-launched-library).

| Area | Source / documentation |
| --- | --- |
| Maven distribution | `io.vproxy:godot-jfx-<module>`; [release version and upstream commits](release.properties), [consumer dependencies](docs/godot-library-spec.md#构建与加载) |
| Runtime, native windows, JNI and GPU protocol | `native/godot_modules/javafx`; [architecture](docs/architecture.md), [module](docs/native-module.md), [protocol](docs/bridge-protocol.md) |
| Prism pipeline, textures, graphics and effects | `jfx/modules/javafx.graphics/src/main/java/com/sun/prism/godot`; [Prism-Godot](docs/prism-godot.md) |
| Glass windows, input, timer, clipboard and cursor | `jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot`; [Glass-Godot](docs/glass-godot.md), [IME](docs/ime-godot.md) |
| Embedded Godot scene | [GodotView](docs/godot-view.md) |
| Per-node CanvasItem shader | [GodotShaderEffect](docs/node-shaders.md) |
| Audio/video build and playback coverage | [Media](docs/media-godot.md) |
| Original Demo and visual comparisons | [VFX Demo](docs/vfx-demo.md) |
| Performance and lifetime observations | [frame timing](docs/frame-benchmark.md), [memory validation](docs/memory-validation.md) |
| Current evidence, unsupported paths and remaining acceptance | [acceptance status](docs/acceptance-status.md) |
| Historical implementation notes | [progress](agentdir/docs/progress.md) |

Build products are in `godot/bin`, `jfx/build/sdk` and `artifacts/vfx`. The JNI
bridge is compiled into Godot; no separate bridge DLL or godot-cpp dependency is
used. Build and test logs are in `agentdir/logs`.

The all-page Demo test writes GPU viewport captures to `artifacts/reference/vfx-pages-mobile`.
After capturing the matching D3D reference, run `python scripts/compare-vfx-pages.py --driver metal`
to generate the paired contact sheet at `artifacts/reference/vfx-comparison-mobile.png`.

## Current measured results and limits

- The representative VFX animation measures 59.954 completed compositions/s in
  the 2026-11-04 Vulkan/safe review run (59.985 Java pulses/s, p95 18.654 ms,
  maximum 54.074 ms; `vfx-frame-benchmark-safe.log`). This is near-60 average
  cadence for that fixture, not a guarantee of 60 FPS for every workload.
  Historical native D3D comparisons and their different counters are in frame-benchmark.md.
- All 35 Demo pages have GPU captures. Dedicated tests cover standard effects,
  FXML, native Stage ownership/modality, shaders, GodotView transforms/input,
  transparent empty areas, icons, cursors and selected real Demo interactions.
- A 537-second, three-round Demo navigation test has stable homepage native
  resources and final-zero cleanup. Actual process observations show no clear
  sustained accumulation at that duration; small leaks and longer workloads
  are not excluded.
- WebKit support is excluded by the user. Media native SDK build, silent PCM
  and local MP4 MediaView playback pass. Encoded 1080p60 and the documented
  120-player churn pass their bounded acceptance checks; physical audio output,
  A/V synchronization and broader codec/workload coverage remain unverified. System menus and
  the virtual keyboard remain unsupported.
  Windows native file/directory choosers are implemented; see docs/glass-godot.md
  for validation and the current single-active-chooser limit.
  Application-local drag/drop is implemented; cross-application OLE transfer and
  drag preview/cursor feedback remain incomplete.
  Robot keyboard/mouse and desktop pixel capture pass Vulkan/OpenGL and packaged
  Vulkan Runtime at 2× DPI. OS-synthesized input also passes the seven application-local
  drag/drop cases; this does not prove cross-application OLE transfer.
  Windows Editor and Runtime pass direct clipboard exchange with an external peer
  for text, HTML, RTF, URLs, file lists, bitmap pixels and a custom format.
  The test overwrites the system clipboard and leaves its final contents in place.
- Physical IME/device input, mixed-monitor transitions and OS-desktop visual
  acceptance remain incomplete. 3D is outside the requested 2D scope.

Subsystem documents provide reproducible test commands and explain their limits.
Compilation or a single passing fixture does not establish overall completion.

## License

The original code in this repository (the Godot host module under
`native/godot_modules/`, scripts, test scenes and documentation) is released
under the [MIT License](LICENSE).

The Git submodules keep their own licenses:

- `godot/` — MIT License (Godot Engine); the JavaFX host integration in this
  fork remains MIT-compatible.
- `jfx/` — GNU General Public License v2 with the Classpath Exception
  (OpenJFX); modifications to `javafx.graphics` / `javafx.media` inherit it.
- `vfx/` — MIT License.

Building or distributing the combined runtime must satisfy all of the above,
in particular the OpenJFX GPLv2 + Classpath Exception terms.
