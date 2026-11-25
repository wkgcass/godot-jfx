# JavaFX 单 JAR 与 Godot 库模式规格

## 普通应用

Windows x64、macOS arm64 和 Linux x64 应用可以只交付一个 Shadow JAR。用户从任意工作目录用 JDK 25 执行 `java -jar app.jar`。应用类、JavaFX 类、CSS、着色器和所选平台的原生库都在这个 JAR 中。分发物不要求配套的 SDK、工程目录或 PCK。

清单的 `Main-Class` 指向普通 Java 类。它在当前 JVM 调用 `Application.launch(MyApplication.class, args)`。如果使用模块路径，也可以由 JDK 直接启动没有 main 的 Application 子类。两种入口与 `Platform.startup` 共用初始化协调器。

```java
package example;

import javafx.application.Application;

public final class Main {
    public static void main(String[] args) {
        Application.launch(MyApplication.class, args);
    }
}
```

宿主在内存中创建空场景树，在根窗口上挂载 JavaFXHost。初始 `res://` 为空，不搜索应用目录、当前目录或上级目录中的 Godot 工程。默认使用 `mobile` 渲染器（Windows 为 D3D12，macOS 为 Metal，Linux 为 Vulkan）和 safe 渲染线程模式，启动窗口保持隐藏直到首次呈现。

Windows 创建引擎实例时调用一次 `DisableProcessWindowsGhosting()`，使 Windows 停止为未响应窗口创建替代窗口。该设置对整个 JVM 进程有效，持续到进程退出。

普通 JavaFX 应用和 VFX Demo 均可在 `-jar` 或主类名之前传入 JVM 属性来选择驱动，无需工程文件。例如：

```powershell
java "-Djavafx.godot.driver=d3d12" -jar app.jar
java "-Djavafx.godot.driver=vulkan" -jar app.jar
java "-Djavafx.godot.driver=opengl" -jar app.jar
```

Windows 默认使用 `d3d12`，macOS 默认使用 `metal`，Linux 默认使用 `vulkan`。三个平台均可用 `opengl` 指定 OpenGL。普通应用从 JVM 属性读取驱动，省略时使用平台默认值。Demo 的 `--driver` 在 JavaFX 自动启动前设置同一属性，优先于命令行中的 `-Djavafx.godot.driver`。启动时按所选驱动设置 Godot 的渲染方法和图形 API。空字符串、未知值、跨平台驱动以及实际驱动不匹配都会导致启动失败。日志中的 `GODOT_LIBRARY_DRIVER` 记录 Godot 的实际名称，例如 `d3d12` 或 `opengl3`。

| JavaFX 操作 | 可观察行为 |
| --- | --- |
| 设置主 Stage 的标题、位置、宽高与可缩放性 | Glass 将设置交给 Godot 根窗口；显示后仍可修改窗口尺寸 |
| 在显示前选择透明或无边框样式 | 宿主在创建窗口系统前启用逐像素透明能力，应用用 StageStyle 和 Scene 填充决定外观 |
| 创建第二个 Stage，设置 owner 并显示 | 创建独立原生窗口；关闭该窗口遵循 JavaFX 的 owner 与隐式退出规则 |
| 使用控件、CSS、Media、Node Shader 或 Effect | 使用 JavaFX 资源和现有 GPU 管线，应用无需提供 Godot 启动场景 |

## 自定义 GodotView 内容

需要 `GodotView.loadScene("res://sample.tscn")` 的应用可将作者工程的 2D 场景及其导入资源导出为一个 PCK。把它放到应用的 `src/main/resources/META-INF/godot-jfx/scenes.pck` 即可，由 Shadow 随应用资源合并。普通应用省略此条目。

Java 启动器若找到该资源，就把字节交给引擎。引擎启动空场景树后，将包挂载到 `res://`，再通知 JavaFX 就绪。包中的主场景、自动加载与窗口设置不会接管宿主。场景在 GodotView 请求时实例化到该控件自己的 SubViewport。损坏的包报告资源挂载失败。该约定支持一个应用级资源包，作者负责在导出时收齐场景依赖。

自动启动的应用可通过 `-Djavafx.godot.project=<路径>` 选择导入好的工程目录或文件系统 PCK。显式指定工程会采用该工程的启动配置，优先于 JAR 中的场景包。省略 `project` 即使用空场景树。显示类型、窗口句柄和操作系统文件名都未进入公共接口。

## 构建与加载

本地 Maven 仓库发布六个 `io.vproxy:godot-jfx-<模块>` 构件，模块为 base、graphics、controls、fxml、media、swing。Java 模块名沿用 `javafx.base`、`javafx.graphics` 等。Windows x64 的 graphics 和 media 使用 `win`，macOS arm64 使用 `mac-aarch64`，Linux x64 使用 `linux`。

三个平台共用根目录的 [release.properties](../release.properties)。每次发行更新 `port.version`；同步上游基线时，更新对应的 `godot.upstream.commit` 或 `jfx.upstream.commit` 为完整上游提交哈希。打包脚本取两个哈希各自的前 8 位，按 `适配版本-Godot基线-JFX基线` 生成六个构件共用的版本，并写入发行目录的 `version.txt`。下面的 Windows 消费示例使用 `win`，在 Linux x64 上将两个 classifier 改为 `linux`，在 macOS arm64 上改为 `mac-aarch64`。示例通过 Gradle 参数 `-PjavafxVersion` 接收该文件中的版本。

```groovy
plugins {
    id 'application'
    id 'com.gradleup.shadow' version '9.3.1'
}
repositories {
    maven { url = uri(providers.gradleProperty('repository').get()) }
}
def fxVersion = providers.gradleProperty('javafxVersion').get()
dependencies {
    implementation "io.vproxy:godot-jfx-controls:${fxVersion}"
    runtimeOnly "io.vproxy:godot-jfx-graphics:${fxVersion}:win"
    // 仅使用 Media 时添加
    implementation "io.vproxy:godot-jfx-media:${fxVersion}:win"
}
application { mainClass = 'example.Main' }
tasks.shadowJar {
    manifest { attributes 'Enable-Native-Access': 'ALL-UNNAMED' }
    filesMatching('META-INF/services/**') { duplicatesStrategy = DuplicatesStrategy.INCLUDE }
    mergeServiceFiles()
}
```

graphics 平台 JAR 包含 Godot、JavaFX 图形库，Windows 构件还包含 SDK 随附的微软运行库。macOS 和 Linux 构件分别在 JAR 根目录提供 `libgodot.dylib` 和 `libgodot.so`。Media 平台 JAR 包含媒体库和插件。应用使用 Shadow 合并运行类路径和服务声明，把普通启动类写入清单，并声明 `Enable-Native-Access: ALL-UNNAMED`。模块路径开发运行使用同一套平台 JAR。[可执行 Gradle 示例](../tests/library/shadow/build.gradle) · [Windows 源码构建](build-windows.md#java-launched-library) · [Linux 源码构建与 WSL2 运行](build-linux.md)

OpenJFX 的原生库加载器根据平台文件名读取需要的 JAR 资源，将它们放入按构建标识和架构隔离的用户缓存，再按绝对路径加载。操作系统因此可以映射原生文件。应用类和场景包直接从 JAR 读取，启动过程始终在调用者的 JVM 内。首次运行需要可写的缓存位置，后续启动校验并复用缓存。平台 JAR 缺少必需库时会报告资源名并终止加载。

## 生命周期与平台边界

同一进程拥有一个引擎实例。已创建的 Toolkit 在 JVM 关闭期间仍供 FX 回调查询线程身份。只有首次创建 Toolkit 才会触发宿主初始化检查，显式调用 `GodotRuntime.init()` 仍会在宿主停止期间报错。JavaFX 自动初始化和用户显式初始化共用状态，并发等待者观察相同的就绪状态或错误。已就绪后重复使用相同配置会复用宿主，冲突配置会失败。Windows 在专用平台线程处理消息并迭代引擎；JavaFX Application Thread、Prism 渲染线程和有界命令队列维持原有职责。关闭最后一个窗口遵守 implicitExit；显式退出保留应用的退出码。

Windows 使用专用引擎线程；macOS 将引擎创建、窗口事件、逐帧运行和销毁交给 AppKit 主线程。Linux 同样在调用方 JVM 中运行引擎。完整 VFX Demo 的首选入口是 `java -jar artifacts/vfx/libs/vfx-demo.jar`。Windows x64 和 macOS arm64 均已实机运行完整 Demo。macOS 的两个渲染器分别通过 JAR 启动与关闭检查。WSL2 的 Intel Arc B390 已通过 Vulkan/mobile 和 OpenGL/gl_compatibility 两种 VFX JAR 启动与关闭检查。[测试入口与平台范围](../TESTS.md)

## 验收

1. 在独立消费目录通过 Gradle Shadow 从本次 Maven 产物构建。把生成的单 JAR 放入空目录，用 JDK 25 直接启动，确认运行 Stage 的进程 PID 与启动的 Java 进程一致。
2. 普通 JAR 不含 PCK。验证透明主 Stage、窗口调整及独立子 Stage；在带无效默认场景的外来工程目录复测，结果应相同。
3. 使用包含 Media 的 JAR，验证本地视频解码画面、暂停、跳转、停止后重播和退出。
4. 在带资源包的 JAR 中调用 GodotView，观察主窗口合成后的指定像素与独立子窗口，使用引擎合成输入触发 JavaFX 控件。资源包自带的主场景若被执行会导致测试失败。另用损坏的资源包检查初始化错误及非零退出码。
5. 在本机串行运行 NonRobot 和已获授权的 Robot 组。Godot 场景夹具由同一 Java 进程从发布的平台 JAR 加载 Windows 的 `godot.dll`、macOS 的 `libgodot.dylib` 或 Linux 的 `libgodot.so`，核对引擎库内容和加载路径，并执行原有的窗口、输入、渲染和清理断言。NonRobot 组同时覆盖模块路径、Shadow 单 JAR 和完整 VFX Demo 的应用启动入口。命令与实测结果见[测试指南](../TESTS.md)和[验收记录](acceptance-status.md)。

## 从 JavaFX 通知 Godot 场景

自定义 Godot 项目可以在当前场景根节点上实现 `on_javafx_message(topic: String, value: int)`。JavaFX 应用线程在启动或控件回调时调用 `GodotRuntime.postSceneMessage(topic, value)`。主题长度为 1–128 个 UTF-16 码元，值为有符号的 32 位整数。调用返回表示宿主队列已经接收消息。队列满或宿主已停止时抛出异常。

Godot 主线程按入队顺序取出消息，将回调排入当时场景根节点的延迟调用队列。若排队时没有场景或缺少接收方法，宿主记录错误。若该节点在回调前销毁，Godot 会丢弃对应的延迟调用。示例见[房间控制](../demo/002-3d-contains-javafx/README.md)。

On a Godot Wayland Stage with custom decorations, a title-bar press handler can call `javafx.application.GodotRuntime.startWindowMove(stage)` on the FX thread. The return value indicates whether the request was queued. A false result lets the caller select its platform fallback. The compositor uses the active pointer grab to move the window.
