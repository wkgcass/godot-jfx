# 仓库工作指南

本文件适用于根目录及其子目录。目标是 Windows x64 与 macOS arm64 上的 Godot 承载 JavaFX 运行时；Media 在范围内，WebKit 和 3D 不在当前范围。每个次级 Stage 是独立原生窗口，GodotView 才是嵌入界面的场景控件。

## 先读哪里

第一次进入项目先读 [README](README.md)、[架构](docs/architecture.md)、[当前验收状态](docs/acceptance-status.md)。选择验证命令时查 [TESTS.md](TESTS.md)。`docs/progress.md` 是历史记录，不能把其中旧的“未实现”直接当成当前 TODO。

## 目录与修改边界

- `godot/`、`jfx/`、`vfx/` 是 Git 子模块。检查根仓库以及相关子模块的 `git status --short`、`git diff`；根仓库 diff 不包含子模块内部的完整补丁。
- `native/godot_modules/javafx/`：编译进 Godot 的宿主、窗口、输入、GPU 命令消费与资源管理。
- `jfx/modules/javafx.graphics/`：Glass-Godot、Prism-Godot、GodotView、Shader 扩展；`javafx.media/`：Media 与 GPU 视频帧生命周期。
- `scripts/`：构建、启动、测试和分析入口。`tests/godot/` 为宿主测试场景，`tests/reference/` 为 Java 观察器/对照，`tests/native/` 为 C++ 测试。
- `.tools/`、`.gradle-cache/`、`artifacts/` 为本地工具、缓存和生成物。实际日志在 `artifacts/logs/`，截图与报告主要在 `artifacts/reference/`。
- 保留用户已有修改；不要为通过测试修改 VFX 业务行为、禁用功能或放宽断言。修改协议时同时核对 Java 编码端、C++ 解码/资源校验端和实际消费者。

## 构建环境

以下命令从仓库根目录在 PowerShell 执行。当前脚本默认从 `$env:JAVA_HOME` 获取 JDK 25（可用 `-Jdk` 覆盖），Visual Studio 2022 Community/MSVC 与 Windows SDK；不要用机器默认的旧 Java 代替。Python 可通过 `python` 调用；SCons 使用 `.tools/python/Scripts/python.exe`。Media 构建使用 `MSYS2_ROOT`（默认 `D:\msys64`）中的 make/cygpath/sh 和 UCRT64 GCC；JFX/辅助测试的 Visual Studio 路径通过 `VSINSTALLDIR` 配置，默认 `%ProgramFiles%\Microsoft Visual Studio\2022\Community`。

首次环境准备、依赖下载和路径覆盖参数见 [build-windows.md](docs/build-windows.md)。不要把下面的增量构建命令当成完整工具安装步骤。构建脚本对环境变量的修改应限于当前进程并恢复。

```powershell
.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-jfx-media.ps1
.\scripts\build-vfx.ps1
```

macOS arm64 在仓库根目录用 shell 执行（工具链准备详见 [build-macos.md](docs/build-macos.md)；JDK 25 在 `.tools/jdk-25`，SCons 在 `.tools/pyenv`，需要 Xcode 与 `xcodebuild -downloadComponent MetalToolchain` 安装的 Metal 工具链）：

```sh
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
.tools/pyenv/bin/scons -C godot platform=macos arch=arm64 target=editor vulkan=no accesskit=no angle=no -j8
(cd jfx && JAVA_HOME=$PWD/../.tools/jdk-25/Contents/Home GRADLE_USER_HOME=$PWD/../.gradle-cache ./gradlew sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false --no-daemon)
.tools/pyenv/bin/scons -C godot platform=macos arch=arm64 target=template_release library_type=shared_library extra_suffix=library disable_path_overrides=no vulkan=no accesskit=no angle=no custom_modules="$PWD/native/godot_modules" -j8
sh scripts/build-vfx.sh
```

mac 上 Media 由这一次 Gradle SDK 构建启用（AVFoundation 后端），没有单独的 Media 构建脚本；渲染器 `mobile` 使用 Metal（本机 M1 的发行库报告 Metal 3.1）、`gl_compatibility` 走 OpenGL 4.1，未构建 Vulkan（未安装 MoltenVK）。

顺序执行原生构建；构建前关闭正在使用相应产物 的测试或 Demo，避免链接/复制冲突。JavaFX 模块编入共享库，Editor 负责导入与导出资源。默认 JFX 构建不能代替 Media 构建；Media 步骤显式启用 Media 并关闭 WebKit。不使用预编译 Godot/JavaFX SDK 替代本仓库源码产物；JVM 使用已安装版本，不需要自行构建。

产物：`godot/bin/godot.windows.editor.x86_64.exe`、`godot/bin/godot.windows.template_release.x86_64.library.dll`（macOS 对应 `godot.macos.editor.arm64`、`libgodot.macos.template_release.arm64.library.dylib`）、`jfx/build/sdk/`（mac 的 dylib 在 `lib/` 而非 `bin/`）、`artifacts/vfx/`。JNI 桥接在 Godot 模块内，没有独立桥接 DLL，也不依赖 godot-cpp。

## 运行与常用验证

```powershell
# 首选直接启动本平台完整 Demo JAR；两个 run-vfx-demo 脚本默认也启动此 JAR
java -jar artifacts/vfx/libs/vfx-demo.jar
# 记录日志，使用 Viewport + safe 和默认 Vulkan/mobile 渲染器
.\scripts\run-vfx-demo.ps1
# 有界启动/关闭检查
.\scripts\run-vfx-demo.ps1 -Smoke
# 诊断后端（不代表每个测试都接受这些参数）
.\scripts\run-vfx-demo.ps1 -Renderer gl_compatibility
# 关闭 swapchain vsync 改用 CPU pacing（MaxFps 缺省 60，可填实际刷新率）
.\scripts\run-vfx-demo.ps1 -DisableVsync -MaxFps 60

.\scripts\test-protocol.cmd
.\scripts\test-media-planes.ps1 -Renderer mobile
.\scripts\test-media-video.ps1
.\scripts\test-godot-view.ps1 -Renderer mobile -Transform
.\scripts\test-vfx-intro.ps1 -Renderer mobile -AllPages
```

macOS 等价入口为同名 `.sh` 脚本，参数为小写长选项：

```sh
./scripts/run-vfx-demo.sh                     # --smoke / --renderer mobile|gl_compatibility / --disable-vsync / --max-fps 60
./scripts/test-protocol.sh
./scripts/test-media-planes.sh --renderer mobile
./scripts/test-media-video.sh
./scripts/test-godot-view.sh --renderer mobile --transform
./scripts/test-vfx-intro.sh --renderer mobile --all-pages
```

场景测试用 classpath 加载本机发布的平台 JAR，由同一 Java 进程加载 `godot.dll` 或 `libgodot.dylib` 并运行夹具。准备好源码 Editor、Godot 共享库和启用 Media 的 SDK 后，运行 `.\scripts\build-vfx.ps1` 一并刷新发行包。Editor 用于导入/导出资源；`-Runtime` 使用单独的夹具项目目录。Windows 非 Robot 组也包含模块路径、Shadow 和 Demo JAR 消费验收。

按改动范围选测试，详见 TESTS.md。GUI 和性能测试串行运行，保持测试窗口前台，不与构建或其他 GPU 重负载并行。默认 VFX/Media 基准为 Godot；显式 `-Backend d3d` 或 `-NativeD3D` 是原生 JavaFX 对照，不能当作 Godot 验收。

## 不应破坏的约束

- JavaFX 负责控件、布局、CSS、字体和应用事件；Godot 负责原生窗口、宿主循环与 GPU。保留 FX Application Thread 和 Prism 渲染线程的语义。
- Java 渲染线程通过有界命令队列传递数据，不能直接修改 Godot Node。不得以每帧整窗 CPU 位图上传替代 GPU 路径；图片、字形掩码、视频平面上传和显式测试读回是不同用途。
- 资源必须覆盖创建、失败、停止、窗口关闭和销毁路径；已排队的绘制仍需使用原来的纹理版本。队列接受、渲染完成、物理显示是不同事件。
- 对不支持的能力明确报错并记录，不能静默忽略。用户已放弃白边问题；不要重新把它列为验收阻塞项。
- 剪贴板互操作测试直接读写系统剪贴板，覆盖已有内容，结束后保留测试写入的内容。直接运行，无需备份、恢复或预先复制纯文本。Media 脚本曾被杀毒软件删除；先核对文件/执行结果，不要自动添加排除项或关闭防护。
- Robot 组包含真实鼠标/键盘输入、系统对话框、原生 IME 移动光标，以及会弹出 Windows 系统触摸键盘的 `test-virtual-keyboard.ps1 -Robot`。执行前须有用户授权；同一会话已明确授权时直接串行执行。非 Robot 组用 `scripts/run-windows-tests.ps1 -Group NonRobot` 选择，虚拟键盘只有 `-CompileOnly` 可以单独做免干扰编译检查。优先使用 Godot 合成输入或模块测试钩子。
- 构建成功、PASS 标记、GPU 截图和物理设备验收各自证明不同范围。记录后端、参数、日志、图像和限制，不把短期资源稳定宣称为所有场景无泄漏。

## 文档地图

| 文档 | 内容与用途 |
| --- | --- |
| [README.md](README.md) | 项目入口、快速构建运行、当前结果摘要 |
| [TESTS.md](TESTS.md) | 测试用途、前置条件、命令、判定方式 |
| [architecture.md](docs/architecture.md) | 面向新读者的组件分工、画面和输入流程、线程及资源生命周期 |
| [godot-library-spec.md](docs/godot-library-spec.md) | Windows 与 macOS 单 JAR 启动、Stage 窗口、GodotView 场景资源及跨平台边界 |
| [acceptance-status.md](docs/acceptance-status.md) | 初始需求逐项证据、当前缺口、验收限制和交付位置 |
| [build-windows.md](docs/build-windows.md) | Windows 工具链准备、源码构建、输出路径、Media 依赖 |
| [build-macos.md](docs/build-macos.md) | macOS arm64 工具链准备、源码构建、输出路径、已知平台限制 |
| [native-module.md](docs/native-module.md) | Godot 自定义模块、宿主节点和原生渲染集成 |
| [bridge-protocol.md](docs/bridge-protocol.md) | Java/C++ 通信格式、命令、资源校验、队列与完成通知 |
| [glass-godot.md](docs/glass-godot.md) | 窗口、屏幕、调度、输入、剪贴板、光标及系统接口 |
| [ime-godot.md](docs/ime-godot.md) | 中文等输入法的组合文本、提交、取消和候选位置 |
| [logical-windows.md](docs/logical-windows.md) | 已被独立原生 Stage 替代的历史嵌入窗口方案与诊断；不是当前窗口模型 |
| [prism-godot.md](docs/prism-godot.md) | 纹理、绘制、着色器、离屏目标、合成、读回和 Effect |
| [node-shaders.md](docs/node-shaders.md) | 给单个 Node/子树应用 Godot Shader 的 API、语义和限制 |
| [godot-view.md](docs/godot-view.md) | JavaFX 中嵌入 Godot 场景的布局、纹理共享和输入转发 |
| [media-godot.md](docs/media-godot.md) | 音视频构建、控制、YUV/R8 上传、帧率、资源释放及历史修复 |
| [vfx-demo.md](docs/vfx-demo.md) | 原始 VFX Demo 的构建、导航、控件交互和截图验证 |
| [frame-benchmark.md](docs/frame-benchmark.md) | 帧率、长帧、原生对照和性能诊断；计数器解释 |
| [memory-validation.md](docs/memory-validation.md) | 长时间导航、进程/GPU/Java 内存采样及趋势解释 |
| [review-open-items.md](docs/review-open-items.md) | 当前实现审查未闭环项、下一步及验证限制；不是新功能需求或完成证明 |
| [progress.md](docs/progress.md) | 逆序历史工作记录；旧结论可能被上方新记录取代 |

## 修改代码后的文档检查

每次修改代码后，都要检查相关文档是否需要同步更新，尤其是行为、接口、构建/运行命令、测试入口、验收结论和已知限制发生变化时。需要更新的文档应与代码一起修改，避免文档与实际实现不符。

`docs/architecture.md` 必须使用初学者也能理解的方式书写，不能假定读者深入了解 JavaFX 或 Godot。先解释组件的用途和协作流程，再介绍实现细节；首次出现的专业术语应解释含义，必要时使用具体示例、流程图或对照表。

交付前按需要执行 `git diff --check` 并更新相关说明。需要刷新完整变更/产物清单时执行 `.\scripts\write-delivery-inventory.ps1`，结果为 `artifacts/change-inventory.json`；清单不是测试通过证明。
