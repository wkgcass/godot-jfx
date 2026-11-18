# JavaFX 单 JAR 与 Godot 库模式规格

## 普通应用

Windows x64 应用可以只交付一个 Shadow JAR。用户从任意工作目录用 JDK 25 执行 `java -jar app.jar`。应用类、JavaFX 类、CSS、着色器和所选平台的原生库都在这个 JAR 中。分发物不要求配套的 SDK、工程目录或 PCK。

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

宿主在内存中创建空场景树，在根窗口上挂载 JavaFXHost。初始 `res://` 为空，不搜索应用目录、当前目录或上级目录中的 Godot 工程。默认使用 `mobile` 渲染器和 safe 渲染线程模式，启动窗口保持隐藏直到首次呈现。

Windows 创建引擎实例时调用一次 `DisableProcessWindowsGhosting()`，使 Windows 停止为未响应窗口创建替代窗口。该设置对整个 JVM 进程有效，持续到进程退出。

| JavaFX 操作 | 可观察行为 |
| --- | --- |
| 设置主 Stage 的标题、位置、宽高与可缩放性 | Glass 将设置交给 Godot 根窗口；显示后仍可修改窗口尺寸 |
| 在显示前选择透明或无边框样式 | 宿主在创建窗口系统前启用逐像素透明能力，应用用 StageStyle 和 Scene 填充决定外观 |
| 创建第二个 Stage，设置 owner 并显示 | 创建独立原生窗口；关闭该窗口遵循 JavaFX 的 owner 与隐式退出规则 |
| 使用控件、CSS、Media、Node Shader 或 Effect | 使用 JavaFX 资源和现有 GPU 管线，应用无需提供 Godot 启动场景 |

## 自定义 GodotView 内容

需要 `GodotView.loadScene("res://sample.tscn")` 的应用可将作者工程的 2D 场景及其导入资源导出为一个 PCK。把它放到应用的 `src/main/resources/META-INF/godot-jfx/scenes.pck` 即可，由 Shadow 随应用资源合并。普通应用省略此条目。

Java 启动器若找到该资源，就把字节交给引擎。引擎启动空场景树后，将包挂载到 `res://`，再通知 JavaFX 就绪。包中的主场景、自动加载与窗口设置不会接管宿主。场景在 GodotView 请求时实例化到该控件自己的 SubViewport。损坏的包报告资源挂载失败。该约定支持一个应用级资源包，作者负责在导出时收齐场景依赖。

应用可以在 Toolkit 启动前通过 `GodotRuntime.init(new GodotRuntime.Options(project, renderer, startupWindow))` 选择导入好的工程目录或文件系统 PCK。显式指定工程会采用该工程的启动配置，优先于 JAR 中的场景包。省略 `project` 即使用空场景树。显示类型、窗口句柄和操作系统文件名都未进入公共接口。

## 构建与加载

源码构建向本地 Maven 仓库发布 `org.godotjfx` 的 base、graphics、controls、fxml、media、swing 六个模块，当前版本为 `28-godot.4`。应用依赖所需模块，同时选择同版本的 Windows x64 平台构件。以下 Gradle 依赖可用于普通控件应用，使用视频时再加入 Media。

```groovy
plugins {
    id 'application'
    id 'com.gradleup.shadow' version '9.3.1'
}
repositories {
    maven { url = uri(providers.gradleProperty('repository').get()) }
}
dependencies {
    implementation 'org.godotjfx:javafx-controls:28-godot.4'
    runtimeOnly 'org.godotjfx:javafx-graphics:28-godot.4:win'
    // 仅使用 Media 时添加
    implementation 'org.godotjfx:javafx-media:28-godot.4:win'
}
application { mainClass = 'example.Main' }
tasks.shadowJar {
    manifest { attributes 'Enable-Native-Access': 'ALL-UNNAMED' }
    filesMatching('META-INF/services/**') { duplicatesStrategy = DuplicatesStrategy.INCLUDE }
    mergeServiceFiles()
}
```

graphics 平台 JAR 包含 Godot、JavaFX 图形库和 Windows SDK 构建随附的微软运行库；Media 平台 JAR 包含媒体库和插件。应用使用 Shadow 合并运行类路径和服务声明，把普通启动类写入清单，并声明 `Enable-Native-Access: ALL-UNNAMED`。模块路径开发运行使用同一套平台 JAR。[可执行 Gradle 示例](../tests/library/shadow/build.gradle) · [Windows 源码构建](build-windows.md#java-launched-library)

OpenJFX 的原生库加载器根据平台文件名读取需要的 JAR 资源，将它们放入按构建标识和架构隔离的用户缓存，再按绝对路径加载。操作系统因此可以映射原生文件。应用类和场景包直接从 JAR 读取，启动过程始终在调用者的 JVM 内。首次运行需要可写的缓存位置，后续启动校验并复用缓存。平台 JAR 缺少必需库时会报告资源名并终止加载。

## 生命周期与平台边界

同一进程拥有一个引擎实例。JavaFX 自动初始化和用户显式初始化共用状态，并发等待者观察相同的就绪状态或错误。已就绪后重复使用相同配置会复用宿主，冲突配置会失败。Windows 在专用平台线程处理消息并迭代引擎；JavaFX Application Thread、Prism 渲染线程和有界命令队列维持原有职责。关闭最后一个窗口遵守 implicitExit；显式退出保留应用的退出码。

Windows x64 使用 `win` 构件，macOS arm64 使用本机 SDK 生成的 `mac-aarch64` 构件。Windows 使用专用引擎线程；macOS 将引擎创建、窗口事件、逐帧运行和销毁交给 AppKit 主线程。两平台均在原 JVM 中启动。完整 VFX Demo 的首选入口是 `java -jar artifacts/vfx/libs/vfx-demo.jar`。Windows 已验收，macOS 的共享库构建、Metal/OpenGL 运行和退出仍待实机验证。[跨平台待验证清单](../TESTS.md#跨平台待验证清单)

## 验收

1. 在独立消费目录通过 Gradle Shadow 从本次 Maven 产物构建。把生成的单 JAR 放入空目录，用 JDK 25 直接启动，确认运行 Stage 的进程 PID 与启动的 Java 进程一致。
2. 普通 JAR 不含 PCK。验证透明主 Stage、窗口调整及独立子 Stage；在带无效默认场景的外来工程目录复测，结果应相同。
3. 使用包含 Media 的 JAR，验证本地视频解码画面、暂停、跳转、停止后重播和退出。
4. 在带资源包的 JAR 中调用 GodotView，观察主窗口合成后的指定像素与独立子窗口，使用引擎合成输入触发 JavaFX 控件。资源包自带的主场景若被执行会导致测试失败。另用损坏的资源包检查初始化错误及非零退出码。
5. 在 Windows 串行运行 NonRobot 和已获授权的 Robot 组。Godot 场景夹具由同一 Java 进程从发布的 Windows 平台 JAR 加载 `godot.dll`，核对 DLL 内容和加载路径，并执行原有的窗口、输入、渲染和清理断言。NonRobot 组同时覆盖模块路径、Shadow 单 JAR 和完整 VFX Demo 的应用启动入口。命令与实测结果见[测试指南](../TESTS.md)和[验收记录](acceptance-status.md)。
