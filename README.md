# Godot-hosted JavaFX for Windows x64

This source workspace implements Prism-Godot and Glass-Godot in OpenJFX, backed
by a Godot custom module. Godot owns the event loop, native windows and GPU work;
JavaFX retains its Application Thread, render jobs, scene graph, controls, CSS
and FXML. The primary Stage uses the Godot root window; additional Stages use
independent Godot-owned native windows. GodotView embeds a Godot 2D scene inside
JavaFX, and GodotShaderEffect applies CanvasItem shaders to individual nodes.

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

Use PowerShell at this directory. The scripts use JDK 25 from `JAVA_HOME`
(or an explicit `-Jdk` override), Visual Studio 2022/MSVC, Windows SDK and
SCons 4.10.1.
For initial dependency setup and alternate JDK paths, follow
[Windows source builds](docs/build-windows.md). Run native builds sequentially.

```powershell
.\scripts\build-windows.ps1 -Target godot-editor -WithJavaFXModule
.\scripts\build-windows.ps1 -Target godot-runtime -WithJavaFXModule
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-jfx-media.ps1
.\scripts\build-vfx.ps1
.\scripts\run-vfx-demo.ps1
```

The launcher defaults to Vulkan (`mobile`) with the `safe` render-thread mode.
The Media step uses existing MSYS make/cygpath and UCRT64 GCC, builds its pinned
makedepend helper inside `.tools`, and stages source-built Media libraries into
the SDK. See build-windows.md for prerequisites and current validation status.
Use `-Renderer gl_compatibility` for OpenGL or `-RenderThread separate` for the
separate rendering thread. `-Smoke` runs a bounded startup/close check.
The normal launcher remains interactive until the Demo is closed.

For a Viewport-only host build, add `-JavaFXRDDirect no` to the Editor or
Runtime build command together with `-WithJavaFXModule`. This excludes the
JavaFX RD-direct implementation at compile time without disabling Godot's
RenderingDevice. The default is `yes`; both builds use the same JFX SDK.
See [build options](docs/build-windows.md) and [RD build tests](TESTS.md).

## Implementation and delivery map

| Area | Source / documentation |
| --- | --- |
| Runtime, native windows, JNI and GPU protocol | `native/godot_modules/javafx`; [architecture](docs/architecture.md), [module](docs/native-module.md), [protocol](docs/bridge-protocol.md) |
| Prism pipeline, textures, graphics and effects | `jfx/modules/javafx.graphics/src/main/java/com/sun/prism/godot`; [Prism-Godot](docs/prism-godot.md) |
| Glass windows, input, timer, clipboard and cursor | `jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot`; [Glass-Godot](docs/glass-godot.md), [IME](docs/ime-godot.md) |
| Embedded Godot scene | [GodotView](docs/godot-view.md) |
| Per-node CanvasItem shader | [GodotShaderEffect](docs/node-shaders.md) |
| Audio/video build and playback coverage | [Media](docs/media-godot.md) |
| Original Demo and visual comparisons | [VFX Demo](docs/vfx-demo.md) |
| Performance and lifetime observations | [frame timing](docs/frame-benchmark.md), [memory validation](docs/memory-validation.md) |
| Current evidence, unsupported paths and remaining acceptance | [acceptance status](docs/acceptance-status.md) |
| Historical implementation notes | [progress](docs/progress.md) |

Build products are in `godot/bin`, `jfx/build/sdk` and `artifacts/vfx`. The JNI
bridge is compiled into Godot; no separate bridge DLL or godot-cpp dependency is
used. `scripts/write-delivery-inventory.ps1` generates
`artifacts/change-inventory.json` with repository revisions, modified/untracked
paths and selected output hashes. Build and test logs are in `artifacts/logs`.

Actual Demo GPU captures are in `artifacts/reference/vfx-pages-mobile`, with a
paired D3D contact sheet at `artifacts/reference/vfx-comparison-mobile.png`.
These are rendered viewport captures, not OS desktop screenshots.

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
  A/V synchronization and broader codec/workload coverage remain unverified. System menus, virtual keyboard,
  image/file/custom system clipboard formats remain unsupported.
  Windows native file/directory choosers are implemented; see docs/glass-godot.md
  for validation and the current single-active-chooser limit.
  Application-local drag/drop is implemented; cross-application OLE transfer and
  drag preview/cursor feedback remain incomplete.
  Robot keyboard/mouse and desktop pixel capture pass Vulkan/OpenGL and packaged
  Vulkan Runtime at 2× DPI. OS-synthesized input also passes the seven application-local
  drag/drop cases; this does not prove cross-application OLE transfer.
  Unicode URL clipboard support is implemented; integration validation is pending
  because Windows currently denies clipboard access (error 5).
  HTML/RTF clipboard application assertions passed, but full clipboard test
  acceptance with exact restoration remains pending.
- Physical IME/device input, mixed-monitor transitions and OS-desktop visual
  acceptance remain incomplete. 3D is outside the requested 2D scope.

Subsystem documents provide reproducible test commands and explain their limits.
Compilation or a single passing fixture does not establish overall completion.
