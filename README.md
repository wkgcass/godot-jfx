# Godot-hosted JavaFX for Windows x64, macOS arm64 and Linux x64

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

Linux x64 副本已在 WSL2 原生 Wayland 上构建，VFX 和两个独立 Demo 均在 Vulkan 和 OpenGL 上运行通过。344 项回归已全部执行，同一发行包计入复测后，非 Robot 通过 312/322 项，Robot 通过 20/22 项。余下 12 项涉及全局窗口层级、绝对定位、置底或应用主动取消最小化，见 [Linux 验收记录](docs/acceptance-status.md#linux-x64-on-wsl2)。环境变量、构建顺序、两个额外 Demo 的打包命令及 WSLg 双后端启动示例见 [Linux x64 构建与运行](docs/build-linux.md)。Linux 源码构建入口为
`scripts/build-linux.sh --target godot-editor|godot-library|jfx`，可用
`--jobs N` 控制并发；共享库和 JavaFX SDK 构建需要 Linux JDK 25。
Linux 窗口验收目标为原生 Wayland，驱动目标为 `vulkan`（mobile）和 `opengl`（gl_compatibility）。
Linux 宿主通过 Wayland 创建窗口和交换拖放数据，使用 GTK 3 显示原生文件对话框。构建需要 Wayland、xkbcommon 和 GTK 3 开发文件。
Linux 发布入口为 `scripts/build-vfx.sh`，从源码 SDK 和 Godot 共享库暂存
`linux` classifier 后再打包；两个独立 Demo 各自通过 Gradle 的
`shadowJar` 任务调用 Linux Editor 导出场景。打包不等于运行验收。
WSL2 可直接运行 `scripts/run-vfx-demo.sh`（默认 Vulkan）或加 `--driver opengl`；启动脚本检测到 `/dev/dxg` 后自动选择对应的 GPU 环境。
其他命令可用 `scripts/wsl-gpu.sh vulkan|opengl COMMAND ...` 为单次运行选择 Mesa
后端。Ubuntu WSL2 的 Vulkan 驱动 Dozen 由 `python3 scripts/setup-env.py` 准备（可用 `WSL_DZN_ROOT` 指定根目录），
OpenGL 使用 Gallium D3D12；启动 Java 时仍需选择匹配的 `javafx.godot.driver`。
在 Intel Arc B390 的隔离 Wayland 桌面上，同一份 Linux VFX JAR 已分别用 Vulkan 和 OpenGL 启动、关闭，并验证主窗口和所属窗口的标题栏拖动。两个独立 Demo 也在双后端运行：三棱锥检查暂停、拖动与恢复，房间检查墙面设备和鼠标捕获。35 页画面对照、往返导航及资源计数按发布版本记录在 [VFX 验收](docs/vfx-demo.md) 和 [内存验证](docs/memory-validation.md)。

运行图形回归用 `scripts/wsl-wayland-session.sh --isolate-wslg` 隔离 Windows 桌面和输入设备。常规 xdg-shell 应用不能指定顶层窗口的绝对桌面坐标、读取全局层级或主动撤销最小化；模态窗口关闭时的焦点时序另见 [窗口验收与限制](docs/acceptance-status.md#linux-x64-on-wsl2)。
WSLg 音频需能加载 PulseAudio 客户端；本机两种渲染后端均连接到双声道
`RDPSink`。如果将发行版的 PulseAudio 客户端及其依赖解包在
`.tools/linux/pulse`，启动脚本会为子进程添加对应的库目录。
Linux JavaFX Media 的 GStreamer 音频输出使用 ALSA。本机在私有目录内提供
ALSA 的 PulseAudio 插件，并用进程级 `ALSA_CONFIG_PATH` 将默认 PCM 接入
WSLg。FFmpeg 8 的运行库及缺失依赖位于 `.tools/linux/ffmpeg-runtime`，
启动脚本将其加入当前进程的库搜索路径。
使用带桌面组件的完整 JDK 25。Wayland 剪贴板通过当前座席的 MIME 数据交换，桌面 Robot 则需要合成器提供虚拟键鼠和图像捕获协议。隔离 Linux 桌面的剪贴板测试不证明与 Windows 应用之间的互操作。

- [AGENTS.md](AGENTS.md)：构建、运行、仓库约束与文档地图。
- [TESTS.md](TESTS.md)：按用途选择测试，查看前置条件、命令和验收方式。
- [架构说明](docs/architecture.md)：从组件分工到画面、输入、线程和资源生命周期。
- [彩色三棱锥 Demo](demo/001-3d-in-javafx/README.md)：在 JavaFX 控件里嵌入 Godot 3D 场景，用按钮控制自转、用鼠标拖动视角。
- [栖居 · 房间控制 Demo](demo/002-3d-contains-javafx/README.md) 将 JavaFX 的 VFX 控件装在 Godot 房间的墙上，用准星操作灯光和空调。

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
After installing the test modules, run `python scripts/test-driver-config.py --driver all`
to verify each driver on the current platform. [Driver configuration test](TESTS.md#驱动配置验收)

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

On macOS arm64, set `JAVA_HOME` to your JDK 25 home and run the corresponding commands from the repository root. Java-based commands also accept `--jdk DIRECTORY` for a single invocation.

```sh
./scripts/setup-env.py
./scripts/build-macos.sh --target godot-editor
./scripts/build-macos.sh --target godot-library
./scripts/build-macos.sh --target jfx
./scripts/build-vfx.sh
```

To preview a project clean, run `python scripts/clean.py --dry-run` (macOS and Linux:
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
It also removes `tests/wayland/__pycache__/` when present and `artifacts/native-tests/`. The Windows and macOS test scripts
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

On macOS, the Metal all-page test writes GPU viewport captures to `artifacts/reference/vfx-pages-godot-metal`.
Run `./scripts/capture-vfx-reference.py` for the native JavaFX Metal reference, then
`.tools/pyenv/bin/python scripts/compare-vfx-pages.py --driver metal` to generate `artifacts/reference/vfx-comparison-metal.png`.

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
