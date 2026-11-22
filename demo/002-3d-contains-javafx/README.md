# 栖居 · 房间控制

在 Godot 第一人称房间中操作两块壁挂面板。左侧开关控制两盏壁灯；右侧面板控制空调电源和 16–30 °C 的设定温度。开机时，室内机的指示灯点亮、导风叶打开；待机时保留温度设置。

左侧墙上是一扇带窄侧扇的木框景观窗。从壁挂面板向左转，可以看到两棵姿态不同的松树：左侧近松斜干展枝，右侧远松低处分叉、双冠错落，以及两树之间的湖面和远山；沿窗走动时，近树和远山会呈现不同的视差。

## 操作

单击窗口进入房间。用 **W / S** 前进、后退，**A / D** 左右平移，移动鼠标环顾。走到面板前，将屏幕中央的十字对准按钮，用鼠标左键点击。**Esc** 或切换到其他窗口会释放鼠标，再单击即可继续。

如果在 Windows 精确式触摸板上按住 WASD 后滑动或轻点失效，可在「设置 → 蓝牙和设备 → 触摸板 → 点击」中检查触摸板灵敏度。Windows 会在键盘活动后短暂抑制部分触摸板输入；「最高灵敏度」会将这段等待设为零。这一设置对当前用户的其他应用也生效。[微软的触摸板防误触说明](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/touchpad-tuning-guidelines#accidental-activation-prevention)

## 构建

以下命令从**仓库根目录**执行。需要 JDK 25（`JAVA_HOME` 指向该 JDK）、本机源码构建的 Godot Editor、Godot 共享库和 JavaFX SDK。首次准备环境请按[Windows 构建指南](../../docs/build-windows.md)或[macOS 构建指南](../../docs/build-macos.md)操作，并运行对应平台的 `build-vfx` 脚本，将模块暂存到 `artifacts/godot-library/`。

Windows x64（PowerShell）

```powershell
.\jfx\gradlew.bat -g .gradle-cache -p demo/002-3d-contains-javafx :shadowJar
```

macOS arm64

```sh
./jfx/gradlew -g .gradle-cache -p demo/002-3d-contains-javafx :shadowJar
```

Gradle 会编译仓库内的 VFX、导出 Godot 场景，并生成包含本平台引擎的单个 JAR。

## 启动

在仓库根目录使用 JDK 25 启动刚构建的 JAR，Windows 和 macOS 命令相同。

```sh
java -jar demo/002-3d-contains-javafx/build/libs/002-3d-contains-javafx.jar
```

## 墙上的控件如何工作

- 两块面板由 JavaFX 排版。文字使用 VFX 的 `ThemeLabel`，四个按钮使用 `FusionButton`。窗口获得焦点后，可用按钮的边缘会按 VFX 默认节奏泛起蓝光。开关动作、按钮禁用和温度范围都在 Java 中处理。[JavaFX 面板](src/main/java/room/WallControls.java)
- Godot 将主 Stage 的画布输出送入单独的 `SubViewport`，再把视口纹理的左右两半分别贴到墙上的两个模型上。面板随视角产生透视并参与遮挡。准星向前发射 5 米射线，只有首先命中面板正面才会将交点换算为窗口像素。鼠标移动、按下和释放沿宿主窗口的 Glass 输入路径送到实际控件。[场景与输入](godot/room.gd)
- JavaFX 与 Godot 共处一个进程。JavaFX 在初始化和按钮回调里用 `GodotRuntime.postSceneMessage("room.devices", state)` 发布完整设备状态。原生宿主把消息排入有界队列，Godot 主线程调度房间根节点的 `on_javafx_message` 更新灯光、指示灯与导风叶。面板图像始终通过 GPU 纹理传递。[房间模型](godot/interior.gd)

## 验证

运行 `java -jar demo/002-3d-contains-javafx/build/libs/002-3d-contains-javafx.jar --smoke`，成功时正常关闭并输出 `ROOM_SMOKE_PASS`。用例通过 Godot 合成输入验证鼠标环顾、先按 W 再按左键及先按左键再按 W 时同时走动、转向和点击，待机禁用、面板外点击，以及 VFX 按钮悬停后的鼠标捕获、Esc 释放、再次捕获和窗口失焦释放。设置环境变量 `VFX_ROOM_PREVIEW` 为 PNG 的绝对输出路径，可在测试时保存起始画面。[交互用例](godot/smoke.gd)

Windows x64 已在 Intel Arc B390 上分别通过 D3D12、Vulkan 和 OpenGL 检查。macOS arm64 的 Retina 坐标映射和鼠标捕获仍需实机验证。
