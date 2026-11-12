# 仓库工作指南

本文件适用于根目录及其子目录。目标是 Windows x64 上的 Godot 承载 JavaFX 运行时；Media 在范围内，WebKit 和 3D 不在当前范围。每个次级 Stage 是独立原生窗口，GodotView 才是嵌入界面的场景控件。

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

以下命令从仓库根目录在 PowerShell 执行。当前脚本默认 JDK 为 `D:\jdk-25.0.3+9`，Visual Studio 2022 Community/MSVC 与 Windows SDK；不要用机器默认的旧 Java 代替。Python 可通过 `python` 调用；SCons 使用 `.tools/python/Scripts/python.exe`。Media 构建还使用现有 `D:\msys64` 中的 make/cygpath/sh 和 UCRT64 GCC。

首次环境准备、依赖下载和路径覆盖参数见 [build-windows.md](docs/build-windows.md)。不要把下面的增量构建命令当成完整工具安装步骤。构建脚本对环境变量的修改应限于当前进程并恢复。

```powershell
.\scripts\build-windows.ps1 -Target godot-editor -WithJavaFXModule
.\scripts\build-windows.ps1 -Target godot-runtime -WithJavaFXModule
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-jfx-media.ps1
.\scripts\build-vfx.ps1
```

顺序执行原生构建；构建前关闭正在使用相应 EXE/DLL 的测试或 Demo，避免链接/复制冲突。`-WithJavaFXModule` 不可遗漏，否则得到的 Godot 没有 JavaFX 宿主。默认 JFX 构建不能代替 Media 构建；Media 步骤显式启用 Media 并关闭 WebKit。不使用预编译 Godot/JavaFX SDK 替代本仓库源码产物；JVM 使用已安装版本，不需要自行构建。

产物：`godot/bin/godot.windows.editor.x86_64.exe`、`godot/bin/godot.windows.template_release.x86_64.exe`、`jfx/build/sdk/`、`artifacts/vfx/`。JNI 桥接在 Godot 模块内，没有独立桥接 DLL，也不依赖 godot-cpp。

## 运行与常用验证

```powershell
# 默认：Godot Vulkan/mobile + safe；关闭窗口后退出
.\scripts\run-vfx-demo.ps1
# 有界启动/关闭检查
.\scripts\run-vfx-demo.ps1 -Smoke
# 诊断后端（不代表每个测试都接受这些参数）
.\scripts\run-vfx-demo.ps1 -Renderer gl_compatibility
.\scripts\run-vfx-demo.ps1 -RenderThread separate

.\scripts\test-protocol.cmd
.\scripts\test-media-planes.ps1 -Renderer mobile
.\scripts\test-media-video.ps1
.\scripts\test-godot-view.ps1 -Renderer mobile -Transform
.\scripts\test-vfx-intro.ps1 -Renderer mobile -AllPages
```

按改动范围选测试，详见 TESTS.md。GUI 和性能测试串行运行，保持测试窗口前台，不与构建或其他 GPU 重负载并行。默认 VFX/Media 基准为 Godot；显式 `-Backend d3d` 或 `-NativeD3D` 是原生 JavaFX 对照，不能当作 Godot 验收。

## 不应破坏的约束

- JavaFX 负责控件、布局、CSS、字体和应用事件；Godot 负责原生窗口、宿主循环与 GPU。保留 FX Application Thread 和 Prism 渲染线程的语义。
- Java 渲染线程通过有界命令队列传递数据，不能直接修改 Godot Node。不得以每帧整窗 CPU 位图上传替代 GPU 路径；图片、字形掩码、视频平面上传和显式测试读回是不同用途。
- 资源必须覆盖创建、失败、停止、窗口关闭和销毁路径；已排队的绘制仍需使用原来的纹理版本。队列接受、渲染完成、物理显示是不同事件。
- 对不支持的能力明确报错并记录，不能静默忽略。用户已放弃白边问题；不要重新把它列为验收阻塞项。
- 剪贴板测试会操作系统共享状态，应遵守脚本的备份/恢复保护；不能为了跑通而清空用户剪贴板。Media 脚本曾被杀毒软件删除；先核对文件/执行结果，不要自动添加排除项或关闭防护。
- Robot 类测试（真实移动鼠标/合成键盘输入的物理夹具，如 robot、external、file-dialog，以及 drag-drop/physical-drag/hover-flicker 的 `-Robot` 可选档）会抢占用户输入设备：尽量不新编写此类测试，优先用 Godot 合成输入或模块内测试钩子等免前台模式；运行任何操作真实鼠标/键盘的测试前必须先征得用户同意，因为用户需要停止使用电脑。
- 构建成功、PASS 标记、GPU 截图和物理设备验收各自证明不同范围。记录后端、参数、日志、图像和限制，不把短期资源稳定宣称为所有场景无泄漏。

## 文档地图

| 文档 | 内容与用途 |
| --- | --- |
| [README.md](README.md) | 项目入口、快速构建运行、当前结果摘要 |
| [TESTS.md](TESTS.md) | 测试用途、前置条件、命令、判定方式 |
| [architecture.md](docs/architecture.md) | 面向新读者的组件分工、画面和输入流程、线程及资源生命周期 |
| [acceptance-status.md](docs/acceptance-status.md) | 初始需求逐项证据、当前缺口、验收限制和交付位置 |
| [build-windows.md](docs/build-windows.md) | Windows 工具链准备、源码构建、输出路径、Media 依赖 |
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
