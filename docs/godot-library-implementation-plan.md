# Godot 库模式和 JavaFX 初始化改造方案

日期：2026-11-17。状态：待实现，供接手实现的 agent 使用。

目标是让应用使用 JDK 25 的 Java 启动器进入 JVM，由 Java 代码加载带 JavaFX 宿主模块的 Godot 原生库。保留显式初始化接口，同时在 JavaFX 自身初始化流程内确保 Godot 已经就绪；直接启动 `extends Application` 的应用不需要另写启动类。JavaFX 控件、布局、CSS、事件线程、Prism 渲染线程和现有 GPU 命令协议继续保留。

**本轮在 Windows x86_64 上实施，完成条件是 Windows 验收矩阵全部通过。** 当前检出已包含 macOS arm64 的可执行宿主，仓库有该路径的构建与验收记录。本轮设计需要考虑其主线程、原生库定位和模块资源需求；macOS 库模式的构建、运行及验收留待有对应环境时进行。

## 已确定的使用约定

| 项目 | 约定 |
| --- | --- |
| 显式初始化 | 用户可以提前调用 `GodotRuntime.init()`，或带配置的重载，准备引擎及运行目录 |
| 自动初始化 | JavaFX 内部仍调用同一个初始化协调器；已显式初始化则复用结果 |
| 应用入口 | 覆盖直接启动 Application 子类、普通 main 调用 Application.launch，以及 Platform.startup |
| 生命周期 | 每进程一个引擎实例，只创建一次；重复调用初始化接口不等于重新创建引擎 |
| 退出 | 应用结束即退出整个进程；不要求销毁引擎后继续运行 JVM |
| 卸载和重启 | 不提供热卸载、引擎重启、多实例或多应用隔离能力 |
| 发行 | Maven 的 JFX JAR 不含 DLL、SO、dylib；原生库随 Godot 运行时发行，并与 Java 部分使用配套版本 |
| Java 资源 | JAR 保留模块描述、Godot Shader、CSS、BSS、图片、国际化和运行所需属性资源 |
| 平台 | Windows x86_64 实施与验收；macOS aarch64 做设计影响审查 |
| 渲染 | 保留 Viewport＋safe；不恢复 RD-direct、separate 或逐帧整窗 CPU 位图上传 |
| 功能边界 | Media 在范围内；WebKit、3D 不在本轮范围 |

正常退出允许由 Java 发起 `System.exit(0)`；失败退出应保留非零退出码。无需为了支持库模式增加一套复杂的可重启、可卸载关闭协议。仍需保证正常运行和退出开始前不会访问失效宿主；现有退出钩子不能因为等待已经停止的引擎循环而阻止进程退出。

## 实施基线

本次复核基线为根仓库 `4e7a23a810bd`、Godot `06d565e4c0c2`、JFX `169f4cdd5e95`。宿主模块已按目标选择 JNI 头文件目录 `win32` 或 `darwin`；macOS 分支另编译 Objective-C++ 的 `.mm` 文件并链接系统框架。`config.py` 允许 macOS arm64 和 x86_64，现有 macOS 验收记录对应 arm64。[模块构建配置](../native/godot_modules/javafx/config.py) · [源文件与 JNI 头文件选择](../native/godot_modules/javafx/SCsub)

实施前记录实际检出的根仓库及子模块修订。公共改动在这套双平台源码上进行；Windows 构建和测试只依赖 Windows 产物。

已有 macOS 启动方向是 Godot Editor／Runtime 创建 JVM。仓库已记录 `mobile` 使用 Metal、`gl_compatibility` 使用 OpenGL 的测试结果。实施后按启动方向记录验收：保留两平台既有宿主证据，为 Windows 新增 Java 加载库的结果，macOS 库模式仍列待验证。[macOS 构建说明](build-macos.md) · [验收记录](acceptance-status.md)

## 现有入口及可复用部分

| 位置 | 已有能力 | 本轮处理 |
| --- | --- | --- |
| `godot/SConstruct` 与各平台 `SCsub` | `library_type=shared_library` 构建分支 | 使用已有共享库支持，继续编入 JavaFX 自定义模块 |
| `godot/platform/windows/libgodot_windows.cpp` | 创建和销毁 GodotInstance | 接入 JNI 启动层并检查库模式路径和窗口初始化 |
| `godot/platform/macos/libgodot_macos.mm` | 创建 OS_MacOS_NSApp 和 GodotInstance | 据此审查公共调度接口是否允许使用 AppKit 主线程 |
| `godot/core/extension/godot_instance.*` | start、iteration、stop | 复用引擎启动和逐帧执行能力；注意 iteration 不会自行生成持续运行的循环 |
| `native/godot_modules/javafx/javafx_host.*` | JVM 启动、JNI 表、运行状态、队列与 GPU 消费 | 分离 JVM 所有权，复用宿主和绘制逻辑 |
| `native/godot_modules/javafx/javafx_host_windows.cpp`、`javafx_host_macos.mm`、`javafx_host_macos.h` | 平台窗口实现及供普通 C++ 调用的 Cocoa 接口 | 公共生命周期沿用现有窗口操作入口，平台类型留在对应实现 |
| `jfx/.../javafx/application/GodotRuntime.java` | 后端检测标记 | 保留已有字段，增加显式初始化入口 |
| `jfx/.../com/sun/javafx/tk/godot/` | GodotBridge 与协议编码 | 增加内部初始化协调器及连接现有 JVM 的入口 |
| `jfx/.../com/sun/javafx/tk/Toolkit.java` | Toolkit 创建公共入口 | 在 native 库和 Prism 初始化前确保 Godot 就绪 |
| `jfx/.../com/sun/javafx/application/PlatformImpl.java` | JavaFX startup 公共流程 | 按锁和平台要求安排早期初始化衔接 |
| `jfx/.../com/sun/javafx/application/LauncherImpl.java` | Application 启动 | 验证直接启动和 main 启动都经过自动初始化 |
| `jfx/.../com/sun/glass/ui/godot/` | 窗口和系统适配 | 复用现有 Glass 实现，Windows 窗口句柄留在平台层 |
| `jfx/.../com/sun/prism/godot/` | GPU 绘制后端 | 复用，确保首次 native 调用前宿主已就绪 |

表中 `jfx/...` 均相对于 `jfx/modules/javafx.graphics/src/main/java/`。不要求为了这次改造重写纹理、Shader、GodotView、Stage 或有界队列协议。

## 显式初始化接口与状态

建议在现有 `javafx.application.GodotRuntime` 上增加以下 API。配置类型名称可按合入后的风格确定，语义须保持一致：

```java
GodotRuntime.init();
GodotRuntime.init(options);
```

无参调用使用发行包默认配置。配置只需覆盖原生运行时目录、Godot 工程目录或 PCK、渲染器及已有的启动窗口选项，不扩展成任意重启或动态更换渲染器框架。优先复用已有配置类型；引擎线程调度由平台实现负责，不交给普通应用自行调用每帧 iteration。

公共配置使用 `Path` 表达运行目录和工程目录／PCK。渲染器选项沿用 Godot 渲染方法名，缺省值由平台实现解析。库文件名、窗口句柄、消息泵、线程 ID 及 JDK 原生库位置均由平台实现处理。JNI 引导层传递配置和桥接类，允许调度到平台指定的线程；公共契约不要求创建后台线程，也不要求调用方执行 iteration。目录比较遵循实际文件系统语义，保留大小写及 Unicode。

初始化函数成功返回，表示引擎、宿主、JNI 方法注册、原生库路径和必要的窗口／屏幕信息已准备好，事件循环能够继续推进。它不表示用户 Stage 已显示或应用第一帧已经呈现。

内部使用一个进程级初始化协调器，状态至少区分：

```text
NEW → STARTING → READY → STOPPING → STOPPED
              → FAILED
```

行为要求如下：

- 显式 init 与自动 ensure 使用相同状态和同一次启动，不得各自创建实例。
- READY 后无参 init 和自动 ensure 直接返回，不能用默认配置覆盖先前的显式配置。
- 相同显式配置重复调用可以返回；与首次有效配置冲突的调用明确报错，不能静默忽略。
- STARTING 期间的其他调用等待同一个完成结果；不重复加载引擎、不启动第二个循环。
- 显式选项先规范化成不可变配置（包括解析后的绝对路径）；并发等待结束后用首次生效的配置检查冲突。自动 ensure 只要求宿主就绪，不参与配置竞争。取消等待的调用方不得发起第二次启动；如果整个启动已判定失败，迟到的原生完成通知也不得重新发布 READY。
- STOPPING 开始拒绝新工作并唤醒等待者；STOPPED 和 FAILED 均为终态。Java 协调器负责对调用方发布结果，原生入口同时保证进程内实例唯一，避免把 Java 类静态字段当成跨类加载器的单例锁。
- FAILED 保留原始失败原因，所有等待者得到失败；本轮不实现自动重试或重新启动。
- 初始化期间发生递归调用时明确识别；不要让同一条调用链等待自己的初始化结果。
- 同步等待必须有可诊断的失败或超时出口，错误包含阶段、系统／架构和实际库路径。
- 保留现有 `PRISM_GODOT_ENABLED` 字段及含义。引擎 READY 不等于 Prism 已初始化，不能在 init 返回时提前置 true，避免破坏 VFX 后端检测。

首次显式初始化应在 Toolkit 启动前进行。应用的 Application.init、start 和构造函数不是可靠的提前配置位置，后续调用只能复用已确定的配置。

## JavaFX 内部确保初始化的位置

当前 `LauncherImpl.launchApplicationWithArgs()` 在调用应用 main 之前就可能执行 `startToolkit()`；其他路径也是先创建 Toolkit，之后才构造 Application 并调用其 init。应用类静态代码块同样不能作为所有启动方式的保障。

实施后必须满足以下顺序：

```text
显式 GodotRuntime.init(options) 可选
                   │
Application Launcher 或 Platform.startup 或 Toolkit 的首次请求
                   │
    选择后端并 ensureInitialized 复用同一状态
                   │
      原生库加载和 Godot 宿主 READY
                   │
         QuantumToolkit 初始化
                   │
    QuantumRenderer 和 Godot Prism 初始化
                   │
       Glass 事件线程和屏幕初始化
                   │
       用户 Application.init 和 start
```

`Toolkit.getToolkit()` 是覆盖直接 Toolkit 请求的关键位置，确保调用应位于必要原生库加载和 `TOOLKIT.init()` 之前，不能拖到 `GodotPlatformFactory.createApplication()`。当前 `QuantumToolkit.init()` 会先通过 QuantumRenderer 创建 Prism；Godot Prism 的 init 已经调用 `GodotBridge.hostInfo()`，只在 Glass 工厂初始化会太晚。

根据锁边界，可在 `PlatformImpl.startup()` 提前调用同一 ensure，并在 Toolkit 入口兜底。Toolkit 当前方法持有同步锁，不能一边持锁等待引擎就绪，一边让引擎初始化回调重新进入 Toolkit。原生初始化应保持在不依赖 JavaFX 场景图的层级；需要时调整初始化锁的范围，不以新增死锁绕过初始化顺序。

Godot 启动失败还要越过 JavaFX 自己的一次性启动标记。当前 `PlatformImpl.startup` 先执行 `initialized.getAndSet(true)`，成功回调才释放 `startupLatch`；`LauncherImpl.startToolkit` 也会先设置 `toolkitStarted`。若首次 ensure 在这些标记之后抛错，后续调用可能进入 runLater 等待尚未启动的 FX 线程。建议在发布“Toolkit 正在启动”之前完成 Godot 专属 ensure；如保留先占位的顺序，则让等待者也能观察到终态错误。保留 Platform.startup 成功后再次调用所规定的 IllegalStateException，失败时不执行用户 Runnable。[PlatformImpl 源码](../jfx/modules/javafx.graphics/src/main/java/com/sun/javafx/application/PlatformImpl.java)

后端选择与引擎初始化分开处理：

- 显式 init 表示本次使用 Godot；若已有相冲突的后端选择，应明确报告。
- 自动 ensure 仅在本次选择 Godot 时启动引擎。保留原生 JavaFX 后端作为对照测试入口。
- 在 PrismSettings、PlatformFactory 等缓存配置前完成选择；不能晚设属性后假定已初始化的静态字段随之改变。
- 建议本发行包在没有显式选择时统一取 Glass=Godot、Prism=godot，以兑现无 main、无 init 的入口。现有 EXE 传入的同一组合直接复用。显式选原生对照时整套走平台 Glass／Prism。例如现有 Windows 测试仅传 `-Dprism.order=d3d` 时，未指定的 Glass 应解析为平台默认 Win；此规则通过平台默认值实现。一侧为 Godot、另一侧显式冲突或要求跨后端回退时，在加载库前报出两侧取值。原生对照即使没有 Godot 共享库也应能启动。
- `--module-path`、模块解析、native-access 等 JVM 启动参数由命令／打包启动器提供，不能承诺 init 在 JVM 已启动后补做所有启动选项。

## JNI 和宿主生命周期拆分

当前两个平台共用 `start_jvm()` 准备宿主及 `run_jvm()` 创建 JVM、注册 JNI、启动应用并销毁 JVM。`jvm_library_path`、`jvm_load`、`jvm_create_symbol` 已分别封装 Windows 和 macOS 的 JVM 加载。保留它们和 `jvm_started` 闸门服务于 Godot 创建 JVM 的入口；Java 加载库时直接接收现有 JavaVM，复用宿主准备、JNI 注册表及回调登记。取得 Godot 实例的唯一性与是否曾创建 JVM 分别判断。[宿主源码](../native/godot_modules/javafx/javafx_host.cpp)

库模式从 `JNI_OnLoad` 或 Java 调用的 native 方法获得现有 JavaVM，Java 继续拥有 JVM。不得再次调用 JNI_CreateJavaVM，也不得在库停止路径调用 DestroyJavaVM。JNI 启动入口可以直接编进带 JavaFX 模块的 Godot 共享库，无需另加 godot-cpp 或独立桥接库。

实现须区分两种初始化来源：Java 加载库创建宿主；已有 Godot EXE 宿主连接 Java。过渡期保留现有 EXE 路径作为回归基线；已有宿主已完成桥接注册时，JavaFX 内部 ensure 应识别并复用，不能反向再创建一个 libgodot 实例。无需为此永久维护两套重复的绘制实现。

JNI 细节要求：

- JavaVM 可跨线程保存，JNIEnv 只在所属线程使用；原生线程按需 attach，退出时配对 detach。
- 从 Java 入口接收或保存正确的桥接 Class／ClassLoader，避免原生引擎线程盲目 FindClass 导致模块或类加载器找错。
- 工程路径传给 Godot 时，`Main::setup` 按标准 UTF-8 解码 argv。JNI 的 `GetStringUTFChars` 对补充平面字符采用 modified UTF-8。建议读取 UTF-16 码元并显式转为标准 UTF-8，每个参数保留独立缓冲区；Windows 宽字符 API 可直接使用 UTF-16。用含空格和一个补充平面汉字（如“𠮷”）的工程路径验收，普通中文路径无法区分这两种编码。[JNI 字符串编码](https://docs.oracle.com/en/java/javase/25/docs/specs/jni/types.html#modified-utf-8-strings)
- 跨调用保存的 Java 对象使用全局引用；局部引用不能交给长寿命回调。
- 当前 `jni_runtime` 的有效期以 DestroyJavaVM 为界，需要改成与宿主状态一致。未就绪、失败或退出后的 native 请求明确失败，不能解引用空指针或已释放状态。
- 沿用 `runtime->drag_upcall` 的发布和关闭保护。现有 worker 的桥接类全局引用由 `DestroyJavaVM` 最终回收；库模式应记录引用所有权，在关闭回调入口并等已进入者退出后显式释放。Windows OLE 与 macOS Cocoa 拖放继续走各自的平台入口。
- 在库模式中，Java 启动器负责用户入口、参数及失败退出码。保留 EXE 模式由 run_jvm 启动 Java 应用的路径。

## 从共享库接到真正的宿主

1. **建立引擎实例。** JNI 引导方法在 Java 调用线程取得 JavaVM、桥接 Class、配置并交给平台调度器。JNI_OnLoad 如有使用只做轻量登记，保持加载线程可以返回。引擎线程调用 libgodot_create_godot_instance 时提供有效的 argv[0]、明确的工程或主包参数、safe 模式和有效的 GDExtensionInitializationFunction。当前 GodotInstance::initialize 会把这个函数交给扩展管理器加载。桥接层和 JavaFXHost 可以继续编在同一个 Godot 模块中。检查 create 的空指针结果以及 start() 的布尔结果，任一步失败都保留所在阶段。
2. **接入场景树。** 发行包提供最小可启动工程／PCK（含所需导入资源）。首选在引擎线程把唯一 JavaFXHost 挂在 SceneTree 根窗口下，生命周期独立于业务场景切换；已有 EXE 测试场景仍自行创建节点并调用 start_jvm。库模式使用连接现有 JVM 的入口，避免运行这些会启动 JVM 的测试场景。自定义工程须能启动 SceneTree；发现重复宿主时报告配置错误。
3. **拆出两种入口共用的宿主准备步骤。** 当前 start_jvm 同时检查主线程、节点已入树及 safe 渲染线程，创建 Runtime，保存窗口关闭策略、光标和平台窗口信息，调用 refresh_host_info()，最后启用 set_process(true) 和 set_process_input(true)。库模式也需执行这些步骤。查找 `jvm.dll` 或 `libjvm.dylib`、检查 SDK 布局、组装 VM 参数以及启动和销毁 JVM 的 worker 均属于可执行宿主入口。
4. **发布 READY。** 在引擎线程确认宿主已经可以消费请求，桥接方法注册成功，原生 Runtime 可接受工作，循环已安排下一次迭代，再一次性通知 Java。EXE 路径在调用用户入口之前向同一协调器显式登记“已有宿主”和有效配置；登记过程不触发 Toolkit。以实际 hostInfo 调用、跨迭代请求完成和窗口输入回送分别验证注册、消费和事件派发。首个用户窗口的 show() 及呈现仍沿用现有策略。

## 两个平台的线程和事件循环

### 公共约束

Godot 的节点、窗口、资源和帧命令消费者仍由引擎所属线程操作。JavaFX Application Thread 和 Prism 渲染线程保留原有职责，通过队列与 Godot 协作。safe 的含义不变，不代表把所有 JavaFX 工作并到同一线程。

初始化 API 在宿主就绪后返回，但引擎循环必须继续运行。不能只调用一次 start 或 iteration，然后让引擎线程结束。等待 READY 也不能占住平台必须处理启动请求的线程。

### Windows x86_64

建议由一个固定引擎线程执行 create、start、逐帧 iteration 和对应清理。当前 GodotInstance::iteration() 先调用 DisplayServer::process_events()，再返回 Main::iteration() 的退出信号；收到退出信号后结束调度。沿用引擎帧节奏，避免额外的忙等或重复消息泵。用宿主已有的主线程及 safe 渲染线程检查验证身份一致。JavaFX 线程保持独立，不能把引擎循环放进 FX 事件线程。

检查 DLL 模式下的模块句柄、窗口资源、进程可执行文件路径和当前目录。进程现在可能是 java.exe 或 javaw.exe，不能把它的所在目录当作 Godot 发行目录。

### macOS aarch64 的设计约束与待验证项

已有 macOS 宿主由 Godot 持有 AppKit 事件循环，再由 worker 启动 JVM。Java 先启动时，需要重新确定首线程和事件循环归属。AppKit 的窗口与事件循环需要进程主线程配合，不能照搬 Windows 的普通工作线程方案。Apple 对 NSApplicationMain 明确要求主线程调用，UI 工作也应遵循 AppKit 主线程规则。[Apple 文档](https://developer.apple.com/documentation/appkit/nsapplicationmain)

Windows 实施时将引擎线程选择、事件泵及迭代调度留给平台层；公共 init 只约定何时就绪。后续具备 macOS 环境时，用最小 Java 加载库程序核实以下问题：

1. JVM 启动器、进程首线程与 AppKit 主线程之间的实际关系。
2. 谁创建／持有 NSApplication，谁处理 RunLoop，以及 Godot 的 iteration 如何调度。当前 OS_MacOS_NSApp 的循环可调用 _process_events(false)，而 GodotInstance::iteration() 调用的是会泵送事件的 process_events()。接入已有 RunLoop 时须选定唯一的事件泵和帧驱动，避免在 AppKit 回调中递归派发事件。GodotInstance::start() 与 OS_MacOS_NSApp 的现有运行路径各自会初始化 MainLoop；只保留一次初始化及与之配对的 finalize。
3. 从 JavaFX Launcher 线程进入自动 ensure 时，如何让主线程执行初始化，且调用方等待不会阻止 RunLoop 启动。
4. 原有 GodotApplication、delegate、菜单和自动释放池如何复用，避免同时启动 stock Glass 的 NSApplication 循环。
5. 显式 init 与自动 ensure 均能返回，随后引擎继续处理窗口事件和绘制。

已有 `libgodot_macos.mm` 会构造 OS_MacOS_NSApp，而已有 OS_MacOS_NSApp 的 run 使用 NSApp run；因此不能只调用 create 就假定事件循环已经运行，也不能在需要同步返回的 init 中直接进入永不返回的 run。

macOS 现有宿主隐藏最后一个 FX 窗口后可能停止产生 `frame_post_draw`。公共 READY、停止通知和 JNI 等待者唤醒应依赖宿主状态及可推进的事件循环；首帧绘制仅作为可见窗口的呈现条件。Windows 可用仅 init、不显示 Stage 的现有计划用例检查这一边界。[窗口生命周期测试说明](../TESTS.md)

是否需要 `-XstartOnFirstThread` 或平台打包启动器，由后续 macOS 实测确定。公共 API 应允许平台在调用方之外安排启动，应用的 Application 子类无需加入平台专用初始化代码。

## 原生库和工程资源定位

Java 运行时目录与 Godot 工程资源目录分别确定。原生运行时目录用于找到引擎共享库、JavaFX 字体／图片／Media 库及依赖；工程目录或 PCK 用于解析 GodotView 的 `res://` 场景。默认布局应由发行包提供，不能依赖源码仓库或 `tests/godot`。

| 项目 | Windows x86_64（本轮交付） | macOS aarch64（设计时预留） |
| --- | --- | --- |
| 引擎共享库 | 从 SCons 实际产物确定 DLL 名称和路径 | 从 SCons 实际产物确定 dylib 名称和路径 |
| JFX 原生依赖 | 本仓库源码构建的字体、图片、Media 等 DLL | 现有 SDK 在 `lib/` 提供 dylib，启用 Media 的同一次 Gradle 构建包含 AVFoundation |
| 间接依赖 | 配置受控 DLL 查找位置，避免误用系统 PATH 中其他版本 | 核对 install name、@loader_path／@rpath 和实际依赖架构 |
| 运行目录 | 不依赖 java.exe 目录或当前工作目录 | 同时处理普通目录和已有应用包布局 |
| 库加载 | 优先明确的绝对路径，并记录选中的运行目录 | 同样明确路径，检查 JVM 与库均为 aarch64 |

`java.library.path` 只解决 Java 层直接查找的一部分，间接依赖还需平台加载器正确定位。不要依靠运行时修改该属性就断言所有加载缓存和间接依赖都已经更新；当前 NativeLibLoader 依次尝试 SDK 相邻位置、JAR 资源、java.library.path 和系统加载。建议把经配置的发行目录作为 Godot 模式下配套库的权威来源；缺件直接报告缺失路径，避免回退时混入旧 SDK。至少覆盖 Toolkit 前先用字体、图片或 Media 的实际加载入口；这类入口只需确定库目录，不应为了查找库而启动窗口。

Windows 加载分两层落实。由 javafx.graphics 内的类通过 `System.load` 将引擎 DLL 关联到该类加载器。对随包交付的间接依赖，先核对导入表及运行时动态加载项，确定哪些需要从受控目录提前加载；引擎 DLL 自身的静态依赖在进入 JNI_OnLoad 前就必须可解析。仅给顶层 DLL 绝对路径不能保证这些依赖来自同一目录。用全新 Java 子进程在移除一个随包间接依赖后重跑实际使用它的路径，要求报错并保留底层加载原因；成功样本在启动及首次播放后分别核对模块来源。[Windows DLL 搜索顺序](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-search-order) · [JNI 库与类加载器](https://docs.oracle.com/en/java/javase/25/docs/specs/jni/invocation.html#library-and-version-management)

**默认目录的来源。** 建议发行启动脚本从自身位置解析运行时根目录，将绝对路径作为私有启动属性传给 JVM。这样纯 Maven JAR 可位于任意缓存目录，无 main 的 Application 也有确定的默认配置。显式 options 中的目录优先；首次加载配套原生库时固定其来源，后续要求改用其他目录时明确报错。直接使用 java 命令的示例应给出相同属性和所需模块参数。工程缺省使用该根目录下的发行 PCK。

原生发行包内按系统／架构选择对应文件，Java JAR 与原生包采用统一版本。无需引入动态下载最新兼容库、跨版本 ABI 协商或多版本热切换能力。

## 纯 Java Maven 包的衔接

这一部分是库模式的发行配套，不要求把六个模块合并成一个大 JAR。保留原有 JavaFX 模块名，普通 Maven JAR 实际携带 Java 类及资源，取消自依赖 `${javafx.platform}` classifier 的 POM 结构，不把无 classifier 的空 JAR 当成最终 Java 包。

发布目标仍是共用 Java 模块。当前 buildModuleClasses 和 Shader 生成有平台筛选，例如 Windows 构建会排除 OSX Media 类。组装任务应区分通用资源与平台生成项，保留已有 macOS 类和资源的接入位置；同路径有不同内容时明确来源，每模块保留单一 module-info.class。在 Windows 用隔离 Maven 仓库和最小消费工程验证普通坐标、传递依赖及实际运行。记录 Windows 构建中缺少、需后续在 macOS 补齐或核验的项。

原生库继续按平台构建并放在 Godot 运行时一侧。JFX 纯 Java 发布任务不能夹带 DLL、SO、dylib，也不能重新引入预编译 SDK 替代本仓库修改后的 Media 等原生组件。需要字体、图片、Media 原生功能，不代表它们必须内嵌进 JAR。

Maven 消费示例需把解析出的 JFX JAR 放到模块路径，并让 `javafx.graphics` 进入 JVM 启动模块层。普通 classpath 应用可用 `--add-modules javafx.controls` 引入其依赖，使用 Media 时再解析 `javafx.media`；模块化应用通过 module-info 声明依赖，并将 Application 所在包导出或开放给 javafx.graphics。用真实的无 main 子类作为 java 启动目标。JDK 25 启动器会先在启动模块层查找 javafx.graphics，只验证 Maven 下载成功或把所有 JAR 拼到 classpath 会漏掉此条件。[OpenJDK 25 LauncherHelper](https://github.com/openjdk/jdk25u/blob/master/src/java.base/share/classes/sun/launcher/LauncherHelper.java) · [JavaFX 25 启动示例](https://docs.oracle.com/en/java/java-components/javafx/25/javafx-users-guide/compiling-running-javafx-application.html)

现有 `GodotRobot` 在 macOS 直接调用 `System.loadLibrary("glass")` 并反射创建 `com.sun.glass.ui.mac.MacRobot`。组装 Java 模块时将该类列入平台内容清单，原生资源定位也要覆盖这种绕过 NativeLibLoader 的按需加载路径。可在 Windows 静态核对源码和 JAR 条目，将 macOS 运行结果留待实测。[GodotRobot 源码](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotRobot.java)

Windows 原生包保留 fxplugins 的 DirectShow 引用释放修复。公共 Prism 路径还须保留 AVFoundation 打包像素格式（例如 `BYTE_APPLE_422`）需要时转换为 `INT_ARGB_PRE` 的现有分支。记录本轮 Java 模块哈希和内容清单，供后续 macOS 核对共用 JAR 及其平台 Media 依赖。

## 退出边界

本轮交付按进程生命周期设计。引擎共享库保持加载直到进程结束，停止应用后不提供重新初始化；不新增强制要求调用的 destroy API。

允许应用发起正常进程退出，无需等到所有资源计数归零才允许退出。要检查 JavaFX 现有 shutdown hook、原生回调、Media 线程和引擎线程不会让正常关闭挂起。不得在通用库内部任意调用 exit(0) 吞掉初始化失败或应用异常；退出码由应用或启动协调层决定。

最后窗口关闭遵循 JavaFX 的 implicitExit 设置；关闭隐式退出时，隐藏最后窗口后仍应能重新显示 Stage，直到 Platform.exit() 或进程退出。仅调用显式 init 而 main 随后返回的夹具也要能自然结束，核对原生线程 attach 的 daemon 属性。关闭时先禁止新回调、停止队列及窗口传输并唤醒等待者；让已进入的 JNI 调用持有有效 Runtime 直至返回，再释放引用。shutdown hook 不能在引擎线程已停后同步等待它处理窗口或帧。正常关闭和调用 System.exit(指定码) 分别验证，外层超时强杀计为失败。

初始化失败须完成必要的入口关闭并传播错误；即使决定随后退出，也不能在错误返回到 Java 之前留下可被并发调用的半初始化桥接。无需为成功退出新增一套比现有实现更复杂的完整资源排空协议。

## Windows 构建与实施顺序

1. 固定 Windows 实施基线，记录现有 EXE 启动与测试入口，核对公共接口涉及的平台类型和线程假设。
2. 扩展 [Windows 构建脚本](../scripts/build-windows.ps1)，增加专门的共享库目标。现有 `godot-runtime` 生成 EXE，继续用于回归。新目标沿用 JDK 25、MSVC、SCons 及 `custom_modules` 参数，指定 `platform=windows arch=x86_64 target=template_release library_type=shared_library`。本方案通过 `--main-pack` 传发行 PCK，所以该库目标显式设 `disable_path_overrides=no`。默认模板除拒绝该参数外，`Main::setup` 还会在无路径覆盖的构建中尝试将进程工作目录切到可执行文件所在目录。[Main::setup 源码](../godot/main/main.cpp) 在该目标中加入最小 JNI 引导入口，记录实际 DLL 路径并核对入口导出（按名绑定的 native 方法或用于注册的 JNI_OnLoad）。用 x64 Java 进程验证库加载及 JNI 调用。
3. 顺序执行现有 Editor（`-WithJavaFXModule`）、JFX SDK 及 `build-jfx-media.ps1` 构建，使用 Editor 导入所需场景及资源，准备可独立启动的工程目录和 PCK。从 run_jvm 拆出宿主／JNI 初始化，接入显式 init。在 Windows 的 Java 子进程验证宿主入树、窗口及连续迭代。工程目录模式需将绝对根目录传入工程设置；当前 `Main::setup` 处理 `--path` 会调用 `set_cwd`，不可直接用它在共享 JVM 中切换目录。
4. 接入 JavaFX 内部 ensure，验证直接 Application 子类、普通 main、Platform.startup 和显式配置保留。
5. 验证进程退出、初始化失败和旧 EXE 路径的过渡兼容。
6. 在 Windows 组装纯 Java 模块和源码构建的原生运行目录，从仓库外按 Maven 消费方式运行。
7. 更新实际命令、接口、平台状态和交付清单；文档不得把阶段性构建成功写成全部功能已验收。

Windows 交付时记录公共 API、JNI、构建及资源布局对 macOS 的影响，列明后续须在 macOS 确认的假设。

## Windows x86_64 验收矩阵

每个启动、退出或失败场景使用新的 JDK 25 子进程；同一进程内完成相应的重复或并发调用。库模式测试入口负责启动 java、传入模块路径和 `--enable-native-access=javafx.graphics,javafx.media`，为夹具设置超时并收集退出码、阶段标记及引擎实例／循环创建次数。使用 `mobile`＋`safe` 作为 Windows 库模式验收配置。现有由 Godot EXE 启动 JVM 的夹具只作回归；将其 Java 观察器及必要的宿主断言接到新入口后，才能计入库模式结果。

下列项目仅在 Windows x86_64 执行。每个运行夹具记录 JVM、实际渲染器、宿主模式、原生目录和 JAR 哈希；绘制夹具另存 GPU 读回结果。全部通过即可完成本轮验收。

| 项目 | 判定要求 |
| --- | --- |
| 公共接口审查 | 在 Windows 用 JDK 25 的 javap 检查新增公开签名，编译仅使用公开 JavaFX API 的消费示例。源码审查确认公共配置与 JNI 引导不拼接 DLL 名、不传 Win32 句柄，不指定固定线程模型；平台专用处理可定位到 Windows 实现 |
| 直接 Application 子类 | 从隔离 Maven 消费工程使用 JDK 25 直接启动无 main、无显式 init 的子类；记录 javafx.graphics 的模块来源，确认 init／start 及窗口输入回送 |
| Application 类自带 main | 覆盖 JavaFX launcher 的特殊启动路径，不依赖 main 比 Toolkit 更早 |
| 普通 Java main | 分别验证直接调用 Application.launch，以及显式 init 后再 launch；两条路径各只创建一个引擎 |
| Platform.startup | 不继承 Application 的启动方式同样自动初始化 |
| 显式配置保留 | 指定运行目录、工程资源或渲染器后，自动 ensure 不用默认值覆盖 |
| 初始化重复与并发 | READY 后重复调用无副作用，STARTING 期间只有一个引擎和一个循环；冲突配置明确失败 |
| 初始化失败 | 分别覆盖缺库、错误架构（可用 Windows x86 测试 DLL）、非法工程和宿主接入失败。并发等待者均能在时限内得到对应阶段及失败原因，随后再次 init 仍失败；另从 Platform.startup 注入同一失败并再次调用：两次均在时限内结束、回调计数为零，未执行的 FX 任务不会卡住退出。负例子进程按约定的非零码结束 |
| 基础画面 | 显式 init 后、Prism 启动前标记为 false，Prism-Godot 成功后为 true。用现有控件／字体、图片、渐变及 Effect 夹具的 GPU 断言和参考图判定渲染结果 |
| Stage 与 GodotView | 独立次级窗口与嵌入控件语义保持，GodotView 场景资源从发行目录加载 |
| Shader | Windows `mobile`＋`safe` 下从 JAR 加载 gdshader，复用节点 Shader 观察器的 uniform、裁剪及输出像素断言 |
| Media | 使用 Windows 源码构建的原生库完成本地视频启动、暂停、seek、stop/replay 和播放器 dispose |
| 退出 | 分进程验证仅 init 后 main 返回、默认关闭最后窗口、implicitExit=false 后重新显示并 Platform.exit()、显式 System.exit(非零码)。记录自然退出耗时、退出码和 hook 异常 |
| 发行隔离 | 在仓库外含空格和中文的发行路径下，分别指定路径中含“𠮷”的已导入工程目录和 PCK；从另一工作目录启动。确认两次都能加载已知场景，原生进程工作目录在 init 前后相同。记录引擎、JFX 及随包 Media 依赖的实际加载路径，均来自本次发行目录；另验证缺失间接依赖时的失败结果；子进程 PATH 排除开发 SDK 与旧运行时 |
| Java 产物 | Windows 消费工程能解析并运行发布的模块；记录各 JAR 的哈希，检查模块描述、类、资源及包内无 DLL、SO、dylib |
| 过渡回归 | 原 EXE 宿主用已有注册运行 Stage 夹具，记录库模式创建次数为零。保留 Windows 原生 JavaFX 依赖、移开测试发行副本中的 Godot DLL，仅指定 `-Dprism.order=d3d` 运行对照夹具，确认使用 Win Glass／D3D |

优先复用现有协议、调度、窗口、GodotView、Shader 和 Media 测试的 Java 观察器，增加库模式启动入口。用真实 JNI／窗口结果检验初始化顺序，不只测试一个返回 READY 的模拟状态机。GUI 与 GPU 测试串行运行；真实鼠标／键盘 Robot 测试依旧需要用户授权，不为这次改造新增此类前置条件。

## 交付清单

- 公共 init 接口、内部 ensure 和明确的配置／失败语义。
- Windows x86_64 共享库构建、Java 启动和事件循环实现。
- 配套 JavaFX 原生库及工程资源目录，独立于源码检出位置。
- 同一套不含动态库的 JavaFX 模块 JAR 及对应 Maven POM。
- Windows 可复现的共享库构建、工程导入／打包、模块发布／解析、Java 启动及各验收组命令（区分已有脚本与本轮新增入口）及上述验收日志；macOS 库模式单列设计影响和待验证项。
- 同步 README、architecture、native-module、bridge-protocol、构建／测试入口及 acceptance-status；macOS 可执行宿主的既有说明按当前检出保留。
- 检查根仓库及相关子模块的完整 diff，执行 git diff --check；需要刷新完整产物清单时使用已有 write-delivery-inventory 脚本。

本方案的库模式验收项均待实施。现有 macOS 可执行宿主的结果按其原测试配置引用。

## 参考入口

- [项目架构](architecture.md)
- [原生宿主模块](native-module.md)
- [桥接协议](bridge-protocol.md)
- [测试指南](../TESTS.md)
- [Toolkit 启动入口](../jfx/modules/javafx.graphics/src/main/java/com/sun/javafx/tk/Toolkit.java)
- [Application 启动器](../jfx/modules/javafx.graphics/src/main/java/com/sun/javafx/application/LauncherImpl.java)
- [GodotInstance](../godot/core/extension/godot_instance.cpp)
- [Windows 库入口](../godot/platform/windows/libgodot_windows.cpp)
- [macOS 库入口](../godot/platform/macos/libgodot_macos.mm)
- [JNI 调用与线程规则](https://docs.oracle.com/en/java/javase/25/docs/specs/jni/invocation.html)
