# 仓库工作指南

本文件适用于根目录及其子目录。目标是 Windows x64 与 macOS arm64 上的 Godot 承载 JavaFX 运行时；Media 在范围内，WebKit 和 3D 不在当前范围。每个次级 Stage 是独立原生窗口，GodotView 才是嵌入界面的场景控件。

## 先读哪里

第一次进入项目先读 [README](README.md)、[架构](docs/architecture.md)、[当前验收状态](docs/acceptance-status.md)。选择验证命令时查 [TESTS.md](TESTS.md)。[历史工作记录](agentdir/docs/progress.md) 是历史记录，不能把其中旧的“未实现”直接当成当前 TODO。

## 目录与修改边界

- `godot/`、`jfx/`、`vfx/` 是 Git 子模块。检查根仓库以及相关子模块的 `git status --short`、`git diff`；根仓库 diff 不包含子模块内部的完整补丁。
- `native/godot_modules/javafx/`：编译进 Godot 的宿主、窗口、输入、GPU 命令消费与资源管理。
- `jfx/modules/javafx.graphics/`：Glass-Godot、Prism-Godot、GodotView、Shader 扩展；`javafx.media/`：Media 与 GPU 视频帧生命周期。
- `demo/` 下的示例独立验证，用例和待验证项保存在对应示例目录。godot-jfx 的测试和 CI 不依赖、构建或运行这些示例。
- `scripts/`：构建、启动、测试和分析入口。`tests/godot/` 为宿主测试场景，`tests/reference/` 为 Java 观察器/对照，`tests/native/` 为 C++ 测试。
- `.tools/` 存放本地工具，`.gradle-cache/` 存放 Gradle 缓存。
- `artifacts/` 存放构建、运行和测试使用的输入与产物。Maven 模块暂存在 `artifacts/godot-library/`，Demo 打包到 `artifacts/vfx/`，本地生成的媒体夹具、测试截图和基准报告放在 `artifacts/reference/`。完整清理和 `--target test-projects` 会删除整个 `artifacts/reference/`；需留存的验收结果在清理前归档。Git 忽略整个目录。
- `agentdir/media/` 存放跨次测试复用的音视频。初始化脚本下载并校验 Oracle 和 Lk 样本，测试通过 `setup-env.py --sample-path oracle|lk` 获取路径。Windows 的 `scripts/make-media-fixture.ps1` 在此生成 `media-1080p60.mp4` 和同名 JSON，供 `benchmark-media-frames.ps1 -Native60` 读取。macOS 用 `./scripts/make-media-fixture.py` 生成相同规格的视频和校验清单，用 `./scripts/benchmark-media-frames.py --native60` 验收。Windows 和 macOS 音频播放及纯音频 churn 测试在此按需生成 WAV、MP3 和 AIFF，已有文件直接复用。
- `agentdir/logs/` 存放本次构建、测试和 Demo 的运行日志。脚本在这里写日志，也从这里读取日志判断是否通过。
- `agentdir/artifacts/` 归档一次性调查材料，例如临时探针、故障现场、修复前后的截图对照和旧验收日志。归档前先核对脚本的读写路径，把仍会复用的文件保留在原位。
- `agentdir/docs/` 存放从现行文档拆出的历史实施、审查和验收记录。现行命令与限制保留在原文档，按需链接到归档。Git 默认忽略 `agentdir/` 下的内容，仅 `agentdir/docs/*.md` 可提交。
- 保留用户已有修改；不要为通过测试修改 VFX 业务行为、禁用功能或放宽断言。修改协议时同时核对 Java 编码端、C++ 解码/资源校验端和实际消费者。

## 构建环境

以下 Windows 命令从仓库根目录用 PowerShell 7.4.1 或更高版本（`pwsh`）执行，推荐从 Microsoft Store 安装。当前脚本默认从 `$env:JAVA_HOME` 获取 JDK 25（可用 `-Jdk` 覆盖），Visual Studio 2022 Community/MSVC 与 Windows SDK；不要用机器默认的旧 Java 代替。Python 可通过 `python` 调用；SCons 使用 `.tools/python/Scripts/python.exe`。Media 构建使用 `MSYS2_ROOT`（默认 `D:\msys64`）中的 make/cygpath/sh 和 UCRT64 GCC；JFX/辅助测试的 Visual Studio 路径通过 `VSINSTALLDIR` 配置，默认 `%ProgramFiles%\Microsoft Visual Studio\2022\Community`。

首次环境准备、依赖下载和路径覆盖参数见 [build-windows.md](docs/build-windows.md) 和 [build-macos.md](docs/build-macos.md)。运行 `python scripts/setup-env.py`（macOS 直接运行 `./scripts/setup-env.py`）初始化缺少的 Godot、JFX、VFX 子模块，并准备仓库 `.tools` 内的 Ant、Maven 和本平台所需工具，已有安装直接复用。JFX 脚本优先读取 `ANT_HOME`。不要把下面的增量构建命令当成完整工具安装步骤。构建脚本对环境变量的修改应限于当前进程并恢复。

```powershell
.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-vfx.ps1
```

在 macOS arm64 上，从仓库根目录用 `zsh -ic '命令'` 执行 Java 相关的构建、运行和测试命令，让交互式 shell 加载用户配置的 `JAVA_HOME`。该变量应指向 arm64 JDK 25，也可用 `--jdk DIRECTORY` 为本次调用指定 JDK。SCons 在 `.tools/pyenv`，Xcode 和 Metal 工具链的安装见 [build-macos.md](docs/build-macos.md)。

```sh
./scripts/build-macos.sh --target godot-editor
zsh -ic './scripts/build-macos.sh --target godot-library'
zsh -ic './scripts/build-macos.sh --target jfx'
zsh -ic './scripts/build-vfx.sh'
```

mac 上 Media 由这一次 Gradle SDK 构建启用（AVFoundation 后端），没有单独的 Media 构建脚本；渲染器 `mobile` 使用 Metal（本机 M1 的发行库报告 Metal 3.1）、`gl_compatibility` 走 OpenGL 4.1，未构建 Vulkan（未安装 MoltenVK）。

顺序执行原生构建；构建前关闭正在使用相应产物 的测试或 Demo，避免链接/复制冲突。JavaFX 模块编入共享库，Editor 负责导入与导出资源。Windows 的 `-Target jfx` 和 macOS 的 `--target jfx`都启用 Media 并关闭 WebKit。不使用预编译 Godot/JavaFX SDK 替代本仓库源码产物；JVM 使用已安装版本，不需要自行构建。

产物：`godot/bin/godot.windows.editor.x86_64.exe`、`godot/bin/godot.windows.template_release.x86_64.library.dll`（macOS 对应 `godot.macos.editor.arm64`、`libgodot.macos.template_release.arm64.library.dylib`）、`jfx/build/sdk/`（mac 的 dylib 在 `lib/` 而非 `bin/`）、`artifacts/vfx/`。JNI 桥接在 Godot 模块内，没有独立桥接 DLL，也不依赖 godot-cpp。

## 运行与常用验证

项目清理入口为 `python scripts/clean.py`（macOS 用 `./scripts/clean.py`）。默认清理全部五项，加 `--dry-run` 可预览命令与目录。`--target godot-editor|godot-library|jfx|packages|test-projects` 可单独清理，其中 `test-projects` 清理生成的 Godot 测试项目。具体范围见 [README](README.md#build-and-run)。

```powershell
# 首选直接启动本平台完整 Demo JAR；两个 run-vfx-demo 脚本默认也启动此 JAR
java -jar artifacts/vfx/libs/vfx-demo.jar
# 记录日志，使用 Viewport + safe 和默认 D3D12/mobile 渲染器
.\scripts\run-vfx-demo.ps1
# 有界启动/关闭检查
.\scripts\run-vfx-demo.ps1 -Smoke
# 为本次启动显式选择 Godot 驱动
.\scripts\run-vfx-demo.ps1 -Driver vulkan -Smoke
# 诊断后端（不代表每个测试都接受这些参数）
.\scripts\run-vfx-demo.ps1 -Driver opengl
# 关闭 swapchain vsync 改用 CPU pacing（MaxFps 缺省 60，可填实际刷新率）
.\scripts\run-vfx-demo.ps1 -DisableVsync -MaxFps 60

python scripts/maven_local.py install           # 将场景与探针依赖安装到本项目的 .m2/repository
.\scripts\test-protocol.cmd
.\scripts\test-media-planes.ps1 -Driver d3d12
.\scripts\test-media-video.ps1
.\scripts\test-godot-view.ps1 -Driver d3d12 -Transform
.\scripts\test-vfx-intro.ps1 -Driver d3d12 -AllPages
```

macOS 等价入口为同名 `.sh` 脚本，参数为小写长选项：

```sh
./scripts/run-vfx-demo.sh                     # --smoke / --driver metal|opengl / --disable-vsync / --max-fps 60
./scripts/maven_local.py install
./scripts/test-protocol.sh
./scripts/test-media-planes.sh --driver metal
./scripts/test-media-video.sh
./scripts/test-godot-view.sh --driver metal --transform
./scripts/test-vfx-intro.sh --driver metal --all-pages
```

场景测试用 classpath 加载本机发布的平台 JAR，由同一 Java 进程加载 `godot.dll` 或 `libgodot.dylib` 并运行夹具。准备好源码 Editor、Godot 共享库和启用 Media 的 SDK 后，运行 `.\scripts\build-vfx.ps1` 一并刷新发行包。Editor 用于导入/导出资源；`-Runtime` 使用单独的夹具项目目录。Windows 非 Robot 组也包含模块路径、Shadow 和 Demo JAR 消费验收。

按改动范围选测试，详见 TESTS.md。Windows 回归分组和适用的单项测试均默认只跑 Godot D3D12。回归耗时较长，平时优先用 `-Test` 选择相关用例。NonRobot 和 Robot 两组均支持 `-Driver vulkan`、`-Driver opengl` 和三后端矩阵 `-Driver all`，用 `-List` 可预览。macOS 的分组和适用单项默认只跑 Metal，显式用 `--driver opengl` 选择 OpenGL，或用 `--driver all` 跑双后端。两组都可用 `--list` 预览、`--test` 选择脚本、`--cases default|variants` 选择基础或专项用例。GUI 和性能测试串行运行，保持测试窗口前台，不与构建或其他 GPU 重负载并行。默认 VFX/Media 基准为 Godot；显式 `-Backend d3d` 或 `-NativeD3D` 是原生 JavaFX 对照，不能当作 Godot 验收。

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
| [review-open-items.md](agentdir/docs/review-open-items.md) | 固定范围的历史审查、修复前后对照及当时的验证限制 |
| [progress.md](agentdir/docs/progress.md) | 逆序历史工作记录；旧结论可能被上方新记录取代 |

## 修改代码后的文档检查

每次添加、修改或删除 upcall 或 downcall 时，必须在同一变更中同步更新[跨语言调用清单](docs/bridge-call-inventory.md)。按实际调用点核对参数、返回值、平台、调用路径和频率；删除的接口移入历史表。清单中不写 Git 提交号。

每次修改代码后，都要检查相关文档是否需要同步更新，尤其是行为、接口、构建/运行命令、测试入口、验收结论和已知限制发生变化时。需要更新的文档应与代码一起修改，避免文档与实际实现不符。

过时的文档优先删除。只有确有保留价值时，例如仍需追溯设计决策或核查历史验收证据，才迁移到 `agentdir/docs/`。若仅部分内容过时，按同一原则删除或归档相应段落，现行说明保留在原文档。删除或迁移时同步更新文档地图和相关引用。

`docs/architecture.md` 必须使用初学者也能理解的方式书写，不能假定读者深入了解 JavaFX 或 Godot。先解释组件的用途和协作流程，再介绍实现细节；首次出现的专业术语应解释含义，必要时使用具体示例、流程图或对照表。

交付前按需要执行 `git diff --check` 并更新相关说明。
