# 彩色三棱锥

一个可运行的 JavaFX + Godot 3D 示例。彩色三棱锥启动时绕 Y 轴自转，暖瓷白背景上的浅石灰色网格向外逐渐淡出。工具栏左侧的绿点表示旋转。“暂停”保留当前姿态，指示点变黄；“开始”从当前位置继续。按住场景中的鼠标左键拖动可环绕观察，左下角的 XYZ 坐标轴随视角更新。视图获得焦点时也可以按 **P** 暂停、按 **R** 开始。

## 构建

以下命令从**仓库根目录**执行。需要 JDK 25（`JAVA_HOME` 指向该 JDK）、本机源码构建的 Godot Editor、Godot 共享库和 JavaFX SDK。按本机平台准备环境，运行对应的 `build-vfx` 脚本，将模块暂存到 `artifacts/godot-library/`。[Windows 构建指南](../../docs/build-windows.md) · [macOS 构建指南](../../docs/build-macos.md) · [Linux 构建指南](../../docs/build-linux.md)

Windows x64（PowerShell）

```powershell
.\jfx\gradlew.bat -g .gradle-cache -p demo/001-3d-in-javafx :shadowJar
```

macOS arm64 或 Linux x64

```sh
./jfx/gradlew -g .gradle-cache -p demo/001-3d-in-javafx :shadowJar
```

Gradle 会编译仓库内的 VFX、导出 Godot 场景，并生成包含本平台引擎的单个 JAR。

## 启动

在仓库根目录使用 JDK 25 启动刚构建的 JAR。在本机 WSL2 使用 B390 时，为 Java 命令加上对应的 GPU 启动包装。[WSL2 驱动选择](../../docs/build-linux.md#在-wslg-上选择-intel-gpu)

```sh
java -jar demo/001-3d-in-javafx/build/libs/001-3d-in-javafx.jar
```

## 实现

- VFX 的 `VStage` 提供窗口和标题栏，主 `VScene` 随窗口调整布局。“开始”和“暂停”使用 `FusionButton`。按钮的首选尺寸为 88 × 40，字体和边缘发光使用 VFX 默认值。拖动提示使用 `ThemeLabel`。指示点提供悬停提示和辅助功能文字。按钮将 R/P 按下及释放事件送到 `GodotView`。也可以用 Tab 将焦点移到按钮，再按空格或回车操作。
- [场景脚本](godot/tetrahedron.gd) 为本控件的 SubViewport 创建独立的 3D 世界并开启 3D 绘制。Godot 生成四个三角面，自转只更新模型，拖动只更新相机。[坐标轴](godot/axes.gd) 把世界坐标的三个正方向投影到相机平面上。
- JavaFX 采样 GodotView 的视口纹理。示例使用仓库默认的渲染器，Windows 为 D3D12/mobile，macOS 为 Metal/mobile，Linux 为 Vulkan/mobile。

Windows x64 已在 Intel Arc B390 上用 D3D12、Vulkan、OpenGL 运行最终 JAR，触发 JavaFX 按钮和合成拖动事件，并比较场景截图。三个驱动都观察到暂停时模型像素稳定、拖动时模型与坐标轴一起改变视角、恢复自转后坐标轴保持稳定。

macOS arm64 已在 Apple M1 上构建独立 JAR，用默认 Metal 后端启动并确认「彩色三棱锥」窗口可见。暂停、恢复和拖动视角仍待手动验证。


在隔离的原生 Wayland 桌面上，B390 的 Vulkan/mobile 和 OpenGL/gl_compatibility 都通过了交互检查。测试点击“暂停”后，连续两张截图的模型区域都没有变化。拖动后模型和坐标轴都改变，点击“开始”后模型继续自转，坐标轴保持稳定。通过合成器关闭窗口后，两次 JVM 都正常退出。截图和逐区域像素计数位于 `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/demos/`。
