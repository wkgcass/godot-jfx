# Godot 与 JavaFX 示例

| 示例 | 内容 |
| --- | --- |
| [001 · 彩色三棱锥](001-3d-in-javafx/README.md) | 在 JavaFX 界面中嵌入 Godot 3D 场景，用 VFX 按钮控制旋转。 |
| [002 · 栖居](002-3d-contains-javafx/README.md) | 在 Godot 房间里用准星操作墙上的 JavaFX 灯控和空调面板。 |

## 构建

从仓库根目录执行。使用 JDK 25，并按本机的 [Windows](../docs/build-windows.md)、[macOS](../docs/build-macos.md) 或 [Linux](../docs/build-linux.md) 指南准备本平台的 Godot Editor、共享库、JavaFX SDK 和 `artifacts/godot-library/` 模块。

Windows x64（PowerShell）

```powershell
.\jfx\gradlew.bat -g .gradle-cache -p demo/001-3d-in-javafx :shadowJar
.\jfx\gradlew.bat -g .gradle-cache -p demo/002-3d-contains-javafx :shadowJar
```

macOS arm64 与 Linux x64 使用相同的 Gradle 命令。Linux 需要 Linux x64 的源码 Editor 和发布到本地的 `linux` 平台模块。

```sh
./jfx/gradlew -g .gradle-cache -p demo/001-3d-in-javafx :shadowJar
./jfx/gradlew -g .gradle-cache -p demo/002-3d-contains-javafx :shadowJar
```

## 启动

在仓库根目录运行对应命令。WSL2 使用项目准备的 dzn 时，在 `java` 前加 `scripts/wsl-gpu.sh vulkan`。[WSLg 驱动选择](../docs/build-linux.md#在-wslg-上选择-intel-gpu)要同时打开两个示例，可在两个终端分别执行。

```sh
java -jar demo/001-3d-in-javafx/build/libs/001-3d-in-javafx.jar
java -jar demo/002-3d-contains-javafx/build/libs/002-3d-contains-javafx.jar
```
