# Godot 与 JavaFX 的跨语言调用清单

本清单以引入自定义 JavaFX 宿主之前的源码为基线，列出此后新增的 Java ↔ Godot 桥接方法。正文记录当前接口，历史表保留已移除的入口。

**Downcall** 指 Java 调原生代码，**upcall** 指原生代码调 Java。产品有 **47 个 JNI downcall**（4 个引擎入口、43 个动态注册方法）和 **3 种 JNI upcall**。场景测试夹具额外声明 2 个 downcall、增加 1 种 upcall，并复用产品的 Java 驱动解析逻辑和 macOS 主线程回调。下表按 Java 声明写出参数类型、名称、顺序和返回类型，省略 JVM 自动传入的 `JNIEnv*` 和类引用。计数单位是方法或回调用途；一次 `submit` 可以包含多条绘制命令，一次输入读取也可以返回多条事件。

频率按源码中的调用点定性分级。**高**表示随帧、连续输入或注明的活动密集调用；**中**表示随复制、窗口变更、截图等按需操作或定期采样调用；**低**表示仅在启动、退出、异常处理或少数专用场景调用。测试表按运行探针时的频率评估，历史表按移除前的实现评估。单次耗时和每秒调用次数需另行测量。

下文的帧回调指 Glass 实际执行的 `onFrame()`。帧调度器会合并积压的通知，输入线程也会合并待读取任务，因此一次 JNI 读取可以取回多条鼠标移动记录。[帧调度循环](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotPulseScheduler.java) · [帧回调与输入处理](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotApplication.java)

平台列按当前 Java 调用路径标注，测试和历史条目分别按对应探针和当时的实现标注。共用入口的频率等级适用于使用该入口的平台；同一入口在某个平台改走其他方法或缺少系统能力时，单元格单独说明。[Windows 宿主](../native/godot_modules/javafx/javafx_host_windows.cpp) · [macOS 宿主](../native/godot_modules/javafx/javafx_host_macos.mm) · [Linux 宿主](../native/godot_modules/javafx/javafx_host_linux.cpp) · [共用 JNI 注册表](../native/godot_modules/javafx/javafx_host.cpp)

## macOS arm64 适配

上面的 47 个产品 downcall 和 3 种产品 upcall 已包含 macOS。两端共用同一 Java 签名时只计一次。macOS 使用 `libgodot.dylib`，`mobile` 经 Metal 绘制；跨语言提交仍走下表的 `submit`。Media 的 AVFoundation 解码属于 OpenJFX 的媒体后端。[macOS 构建与后端](build-macos.md) · [Media 接入](media-godot.md)

| 功能 | macOS 调用路径与频率 |
| --- | --- |
| 主线程启动 | 产品和夹具各有一个仅限 macOS 的 `runOnAppKitThread(Runnable)` downcall，共用一次 `Runnable.run()` upcall 进入 AppKit 主线程。两者均为低频；随后引擎在该线程持续运行。引擎就绪时的 `ready.run()` 是另一次独立回调。[AppKit 实现](../native/godot_modules/javafx/javafx_library_macos.mm) |
| 次级窗口、输入与输入法 | 窗口命令在 macOS 侧处理 NSWindow 的从属关系、前后顺序和输入法状态。触控板滚动进入共用输入队列，由高频的 `awaitInputTick` 和 `pollWindowInputV2` 等待、读取；每次 Glass 帧回调仍读取屏幕和窗口快照。macOS 没有单窗口图标，触摸键盘命令报告不支持。[窗口适配](../native/godot_modules/javafx/javafx_host_macos.mm) · [输入与快照](../native/godot_modules/javafx/javafx_host.cpp) · [平台限制](acceptance-status.md) |
| 剪贴板与文件选择器 | 剪贴板方法按需读写 NSPasteboard。选择器的 `dialogSubmit/Poll/Cancel` 对接 NSOpenPanel 或 NSSavePanel。打开一次只提交一次，面板打开期间可高频轮询。macOS 夹具通过测试钩子验证此契约，系统面板外观与实际键盘操作另待验证。[剪贴板](../native/godot_modules/javafx/macos_clipboard.mm) · [文件面板](../native/godot_modules/javafx/macos_dialogs.mm) · [验收范围](acceptance-status.md) |
| 跨应用拖放 | 外拖经 `dragStartExternal` 进入 Cocoa；拖入目标时，Cocoa 经 `dragTargetCallback` 同步向 Java 查询允许的动作。目标更新可连续触发，属于高频 upcall。[Cocoa 拖放](../native/godot_modules/javafx/macos_dnd.mm) · [JNI 回调](../native/godot_modules/javafx/macos_dnd.h) |
| Robot | `robotPosition` 和 `robotCapture` 按需调用 CoreGraphics。macOS 虽注册了 `GodotBridge.robotMove`，Java 侧实际把 Robot 移动交给上游 MacRobot 发送系统事件；Windows 和 Linux 的移动路径及频率见主表。[Java 平台分支](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotRobot.java) · [CoreGraphics 实现](../native/godot_modules/javafx/macos_robot.h) |

Linux 使用 Wayland 专用的剪贴板和 Robot 入口，文件选择器经 GTK 3 返回结果。下表中带 `Native` 后缀的剪贴板方法对应 Windows 和 macOS，Linux 的 MIME 格式枚举与数据交换见 `waylandClipboardTypes/Read/Write`。

末尾的 16 个 FFM 目标仅用于 Windows 诊断。Linux 从 `/proc/self/smaps_rollup` 读取内存用量，通过 JDK 的 `UnixOperatingSystemMXBean` 读取打开的描述符数。macOS 进程采样通过 `ps` 读取 RSS、枚举 `/dev/fd` 统计描述符。[采样实现](../tests/reference/CurrentProcessMemory.java)

## Downcall · Java → Godot

### 引擎启动与退出（LibraryGodotEngine，4 个）

| 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- |
| `run(Class<?> bridge, Runnable ready, String library, String project, boolean pack, String driver, String startup, boolean disableVsync, int maxFps, boolean verbose)` | `void`。创建并驱动引擎，退出主循环、清理后返回。桥接注册成功后先调用 `ready.run()`。 | 各平台共用。Windows 在 Java 创建的宿主线程驱动引擎；macOS 切到 AppKit 主线程。 | **低** · 每次启动引擎一次，调用持续到引擎退出。 |
| `requestStop()` | `void`。设置停止标志；引擎线程随后退出主循环。 | 各平台共用 | **低** · 关闭已加载的引擎时请求停止。 |
| `mountScenePack(byte[] contents)` | `void`。挂载内存中的 PCK 场景包，失败抛异常。 | 各平台共用 | **低** · 无外部项目且 JAR 含场景包时，在启动阶段挂载一次。 |
| `runOnAppKitThread(Runnable callback)` | `void`。仅 macOS，在 AppKit 主线程执行回调，完成后返回，异常传回调用方。 | macOS 专用。Windows 直接执行 Java 的 loop.run()。 | **低** · macOS 启动引擎循环时调用一次。 |

`library` 是已加载的引擎库路径。`project` 为 null 时以无项目模式启动；有值时，`pack` 区分 PCK 和项目目录。`driver`、`startup` 指定驱动和启动窗口策略，`maxFps > 0` 时传入帧率上限。[Java 声明与实参](../jfx/modules/javafx.graphics/src/main/java/com/sun/javafx/tk/godot/LibraryGodotEngine.java) · [原生引擎入口](../native/godot_modules/javafx/javafx_library.cpp) · [AppKit 入口](../native/godot_modules/javafx/javafx_library_macos.mm)

普通应用的 `LibraryGodotEngine.run` 和场景夹具的 `GodotSceneFixture.run` 共用驱动选择逻辑。Java 在进入 JNI 前解析选项、JVM 属性和平台默认值，将选定的驱动传入原生代码。原生端据此选择 Godot 渲染方法。启动后核对实际驱动并输出 `GODOT_LIBRARY_DRIVER`，回退导致启动失败。

### 绘制、调度与输入（GodotBridge，8 个）

| 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- |
| `submit(ByteBuffer frame, int byteLength)` | `boolean`。从直接缓冲区复制并校验命令批次。`true` 表示已入队，`false` 表示队列已满，可用同一序号重试。非法批次或宿主停止会抛异常。 | 各平台共用批次和队列。Linux 文字渲染实验路径在同一批次中提交操作码 31，携带目标像素矩形，在下一个 LCD 文字绘制前复制背景。mobile 在 Windows 可使用 Vulkan 或 D3D12，在 macOS 使用 Metal。 | **高** · 每个非空绘制批次提交一次，一帧可有多个批次；队列满时重试。 |
| `readPixels(long handle, long sequence, int x, int y, int width, int height)` | `int[]`。在指定渲染序号完成后读回目标矩形，逐行紧排 ARGB_PRE 像素。读回等待遇宿主停止可返回 null。 | 各平台共用 | **中** · 应用请求快照或显式读回像素时调用；连续截图时可升高。 |
| `awaitTick(long after, int timeoutMillis)` | `long`。宿主通用唤醒计数。 | 各平台共用 | **中** · 默认在遇到背压、等待窗口创建或输入法确认时调用。设置 `GODOT_JFX_FRAME_PULSE=0` 后为高，调度线程循环调用。 |
| `awaitFrameTick(long after, int timeoutMillis)` | `long`。宿主帧计数。 | 各平台共用。Windows 外拖时 OLE 模态循环可暂停宿主帧通知；macOS 外拖会话异步运行。 | **高** · Glass 帧接收线程持续等待。收到帧或超时后再次调用，返回 -1 时在线程队列中安排 JavaFX 退出。场景夹具共用此退出路径。Windows 合成悬停探针在首次注入移动前读取帧号，再等待两次宿主帧推进。 |
| `awaitInputTick(long after, int timeoutMillis)` | `long`。输入到达计数。 | 各平台共用 | **高** · 输入接收线程持续等待，点击、移动等事件可将其唤醒；空闲时最长等一秒再调用。 |
| `pollInput()` | `double[]`。取走队列内全部事件，每条 9 项，空队列返回空数组。 | 各平台共用 | **低** · 窗口测试探针直接调用，探针等待事件时可重复读取。 |
| `pollWindowInputV2()` | `double[]`。取走同一队列内全部事件，每条 12 项。Wayland 按键按下（kind 5）的索引 3 记录入队时源原生窗口是否有焦点，Glass 在向该窗口派发按键前同步已确认的焦点。指针事件携带源窗口 ID、窗口内坐标和屏幕坐标。Glass 向源窗口派发时使用原始窗口内坐标，向其他捕获窗口派发时根据屏幕坐标换算。 | 三个平台共用。Windows 滚轮使用种类 4，Windows 读取系统滚动行数和字符数。macOS 滚轮以及 macOS、Linux 的 Godot 平移手势使用种类 17。Linux 离散滚轮沿用 GTK 的每刻度 40 像素，文本单位为零。 | **高** · 每次 Glass 帧回调以及输入到达后的派发任务均可读取，一次取走一批点击、移动等事件。 |
| `isShutdownDrained()` | `boolean`。渲染完成序号、独立窗口确认序号和宿主命令确认序号均追上已提交工作时为 true。 | 各平台共用 | **低** · 场景夹具异常退出时循环检查，直到已提交工作排空。 |

三种等待均要求 `after >= 0`、超时 1–1000 毫秒。计数超过 `after` 或超时即返回当前值，超时可能与上次相同；宿主停止返回 −1。两个输入读取方法会清空同一队列，只能有一个消费者。输入记录前 9 项为事件种类、按钮或事件数据、窗口内 x/y、屏幕 x/y、修饰键、滚动 x/y；具体字段随事件种类复用。[Java 声明](../jfx/modules/javafx.graphics/src/main/java/com/sun/javafx/tk/godot/GodotBridge.java) · [JNI 注册与实现](../native/godot_modules/javafx/javafx_host.cpp) · [等待与命令队列](../native/godot_modules/javafx/frame_protocol.h) · [协议说明](bridge-protocol.md)

### 窗口、屏幕与光标（GodotBridge，8 个）

| 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- |
| `hostInfo()` | `int[]`。16 项依次为窗口宽/高、DPI、窗口 x/y、屏幕宽/高、屏幕 x/y、焦点、窗口模式、已应用宿主命令序号、屏幕可用区 x/y/宽/高。 | Windows 取有效 DPI，macOS 与 Wayland 以 Godot 的屏幕 UI 缩放倍率 × 96 填充 DPI。 | **高** · 每次 Glass 帧回调读取一次主窗口快照。Stage 输入夹具在焦点断言失败时额外读取一次主窗口快照。 |
| `screenInfo()` | `int[]`。主屏排首，每屏 10 项，依次为 Godot 屏幕索引加一、屏幕 x/y/宽/高、可用区 x/y/宽/高、DPI。 | Windows 取有效 DPI，macOS 与 Wayland 以 Godot 的屏幕 UI 缩放倍率 × 96 填充 DPI。 | **高** · 每次 Glass 帧回调读取一次屏幕快照，即使显示器配置未变。 |
| `hostCommand(int operation, int a, int b, String text)` | `int`。宿主命令的提交序号；整数和文本参数由操作码解释，可与 `hostInfo()[11]` 比对确认。 | 各平台共用。Linux Wayland 上操作码 23 向合成器请求前置，操作码 22 显式报告不支持降低窗口层级。输入法和可见性由各平台处理；触摸键盘命令 26/27 在 Windows 请求打开或关闭，在 macOS 报告不支持。操作码 28 由 GodotRuntime.postSceneMessage(topic, value) 从 FX 应用线程提交，a 为有符号整数值、b 为 0、text 为 1–128 个 UTF-16 码元的主题。Godot 主线程排空有界 FIFO 时选取当前场景根节点，延迟调用其 on_javafx_message(topic, value)。序号确认到宿主调度为止。 | **中** · 应用发布场景消息或主窗口属性、可见性、光标或输入法候选位置变化时提交；连续变化时可密集调用。 Linux 原生 Wayland 的主 Stage 标题栏按下时发送一次操作 29，两个整数为零、文本为空，Godot 主线程调用 Window.start_drag。 |
| `nativeWindowCommand(long id, long owner, int operation, int x, int y, int width, int height, int flags, boolean visible, String title)` | `long`。独立窗口命令的提交序号。操作码 1/2/3/4 分别创建、更新几何与可见性、销毁窗口树、设置属性。 | 各平台共用。Windows 管理 HWND，macOS 用 NSWindow 处理窗口从属、排序和焦点。Windows 和 macOS 创建窗口时只接受原有的低三位标志。Wayland 上普通 Stage 通过 xdg_toplevel 设置父子关系。创建标志位 8 要求有效所有者，为 Glass 弹出窗口设置 POPUP_WM_HINT，使用 xdg_popup 和 xdg_positioner。标志位 16 表示有所有者的模态顶层窗口；拒绝与弹出窗口标志一起使用。Wayland 上，每次显示此 Stage，宿主都向支持 xdg-dialog-v1 的合成器声明模态关系。属性 23 请求由合成器将窗口移到前面。 | **中** · 次级窗口创建、属性或几何变化、关闭时提交；连续调整窗口位置或大小时可密集调用。 次级 Stage 的同一手势发送操作 4、属性 29 和窗口 ID，坐标为零。由对应的 Godot Window 请求合成器拖动。 |
| `nativeWindowInfo(long id)` | `long[]`。未建或已销毁时为空；有快照时依次为窗口 ID、所有者 ID、Godot 原生窗口 ID、x/y、宽/高、可见、焦点、模式、确认序号。 | 各平台共用 | **高** · 每次 Glass 帧回调对每个尚未关闭的次级窗口各查一次。 Wayland 桥夹具收到命令确认后按宿主帧读取父子状态，直到合成器确认恢复或超时。Stage 输入夹具在焦点断言失败时额外读取一次次级窗口快照。 |
| `nativeWindowAck()` | `long`。独立窗口队列最近已应用的命令序号。 | 各平台共用 | **中** · 创建次级窗口或等待其输入法组合结束时，按需重复确认。 |
| `customCursor(int width, int height, int x, int y, byte[] bgra)` | `int`。提交 BGRA_PRE 光标图和热点 x/y，返回宿主命令序号。 | 各平台共用。Windows 保留预乘颜色值；macOS 先还原颜色，再由原生后端预乘并创建 NSCursor。 | **中** · 设置或切换自定义光标时调用，在同一光标区域内移动通常无需重设。 |
| `windowIcon(long id, int width, int height, byte[] bgra)` | `long`。提交图标后返回相应窗口队列的序号。ID 0 走主窗口队列，宽高均为 0 且数据为空数组表示清除。macOS 没有单窗口图标。 | 各平台共用。Java 可提交窗口图标。Windows 设置单窗口图标；macOS 的显示后端不执行该操作，单窗口图标测试跳过。 | **低** · 设置或清除窗口图标时调用，通常集中在窗口初始化阶段。 |

这些序号用于区分请求已提交、宿主已应用两个时刻。窗口可见、GPU 绘制完成另有各自的判定。[窗口传输实现](../native/godot_modules/javafx/native_window_transport.h) · [宿主命令与快照布局](../native/godot_modules/javafx/javafx_host.cpp) · [Glass 窗口语义](glass-godot.md)

### 对话框与 Robot（GodotBridge，11 个）

| 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- |
| `dialogSubmit(long owner, int mode, String folder, String filename, String title, String[] filters, int selected)` | `void`。提交选择器。owner 为 −1 表示无所有者，0 为主窗口；mode 0/1/2/3 分别为打开单文件、打开多文件、保存、选目录。filters 每两项为说明和扩展名模式串，selected 为初始过滤器索引。 | 各平台共用。Windows 在独立线程打开 IFileDialog；macOS 在 AppKit 主线程打开 NSOpenPanel 或 NSSavePanel。 | **中** · 每次打开文件或目录选择器提交一次。 |
| `dialogPoll()` | `String[]`。待完成时为 null。完成后首项是十进制过滤器索引，后续为所选路径；取消时没有路径。 | 各平台共用。同一 Java 循环读取结果：Windows 对话框线程交付，macOS 面板完成回调交付。 | **高** · 选择器打开期间，嵌套循环每处理一个任务便再次检查结果，可随帧更新反复调用。 |
| `dialogCancel()` | `void`。请求取消当前选择器。 | 各平台共用。Windows 由对话框线程处理取消，macOS 在主线程取消面板。 | **低** · 选择器所属窗口隐藏、关闭或异常清理时请求取消，等待结束前可能重复。 |
| `waylandRobotOpen()` | `void`。在 Glass 事件线程打开或复用独立连接，检查输入和屏幕捕获协议。 | Linux Wayland，Glass 事件线程。 | 创建 Robot 时。 |
| `waylandRobotClose()` | `void`。关闭该事件线程的连接，释放虚拟输入设备和输出对象。 | Linux Wayland，Glass 事件线程。 | Wayland Glass 退出时一次。 |
| `waylandRobotButton(int button, boolean pressed)` | `void`。向虚拟指针提交按下或释放，1–5 依次代表主键、中键、次键、后退、前进。 | Linux Wayland，Glass 事件线程。 | 每个指定的按钮一次。 |
| `waylandRobotWheel(int amount)` | `void`。提交有符号的离散垂直滚动步数，正数向下。 | Linux Wayland，Glass 事件线程。 | 每次主动滚轮操作。 |
| `waylandRobotKey(int code, boolean pressed)` | `void`。把 Godot 键码映射到 evdev，经虚拟键盘提交按下或释放及 XKB 修饰状态。 | Linux Wayland，Glass 事件线程。 | 每次主动按键或释放。 |
| `robotMove(int x, int y)` | `void`。把指针移到桌面物理像素坐标。 | Windows 用 SetCursorPos，Linux Wayland 使用虚拟指针协议的绝对移动请求；macOS 移动走 MacRobot，不经此方法。 | **中** · Windows/Linux 每次主动移动调用一次。 |
| `robotPosition()` | `int[]`。指针的桌面物理坐标 `[x, y]`。 | Windows 用 GetCursorPos，macOS 用 CoreGraphics，Linux Wayland 从合成器的图像复制光标会话读取热点坐标。 | **中** · Robot 每次查询鼠标 X 或 Y 坐标时调用，读取两轴会调两次。 |
| `robotCapture(int x, int y, int width, int height)` | `int[]`。返回指定桌面物理像素矩形的 ARGB 像素，按行排列。 | Windows 用 GDI，macOS 用 CoreGraphics，Linux Wayland 从输出捕获会话读取共享内存中的像素。 | **中** · Robot 主动取色或截屏时调用，跨屏截图可分块读取。 |

[选择器实参和结果解析](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotApplication.java) · [Robot 坐标和像素处理](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotRobot.java)

### 剪贴板与跨应用拖放（GodotBridge，16 个）

| 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- |
| `prefersSmallLcdCopies()` | `boolean`，宿主启动时从当前显示服务、渲染方法和显卡名称判定是否为 Wayland 上的 Mesa D3D12 OpenGL。 | Linux Prism 选择未裁剪小块文字的背景复制策略。 | 每次 GodotContext 初始化时读取一次。显式指定 LCD 复制模式时无需查询。 |
| `waylandClipboardTypes()` | `String[]`，当前 seat 的自有或外部 selection 提供的 MIME 名称。 | Linux Wayland，Glass 查询可用格式或构建一次读取。 | 枚举或粘贴时调用。 |
| `waylandClipboardRead(String name)` | `byte[]`，对应 MIME 的原始字节；缺少时返回 null。 | Linux Wayland，读取自有数据或通过接收管道取得外部数据。 | 每个需要的 MIME 一次。 |
| `waylandClipboardWrite(String[] names, byte[][] values)` | `void`，名称与字节数组逐项对应，空数组清空 selection。 | Linux Wayland，经 Godot 窗口所属 seat 发布。 | 同一轮 Glass 调度内合并写入后调用一次；隐藏窗口前立即提交待发布的数据。 |
| `clipboardWriteFormatsNative(String text, byte[] html, byte[] rtf)` | `void`。发布给定文本、HTML、RTF 格式。 | Windows 和 macOS。两端校验探针都直接调用；实际系统写入分别走 Win32 剪贴板和 NSPasteboard。 | **低** · 当前直接调用见剪贴板参数校验探针，常规复制走 clipboardWriteFull。 |
| `clipboardWriteUrlFormatsNative(String text, byte[] html, byte[] rtf, String url)` | `void`。发布给定格式，含独立 URL。 | Windows 和 macOS。两端校验探针都直接调用；Windows 使用注册的 URL 格式，macOS 使用 NSPasteboardTypeURL。 | **低** · 当前直接调用见 URL 参数校验探针，常规复制走 clipboardWriteFull。 |
| `clipboardWriteFullNative(String text, byte[] html, byte[] rtf, String url, String[] files, int[] image, int imageWidth, int imageHeight, String[] customNames, byte[][] customData)` | `void`。发布给定格式，含文件路径、ARGB 图像和按索引配对的自定义名称与字节数据。 | Windows 和 macOS。Windows 发布 Win32 剪贴板格式，macOS 发布到 NSPasteboard。 | **中** · Glass 每次向系统剪贴板发布一组数据时调用。 |
| `clipboardReadTextNative()` | `String`。纯文本，格式缺失时为 null。 | Windows 和 macOS。Windows 读 CF_UNICODETEXT；macOS 读 NSPasteboardTypeString。 | **中** · 粘贴或应用主动索取纯文本时调用。 |
| `clipboardReadUrlNative()` | `String`。URL，格式缺失时为 null。 | Windows 和 macOS。Windows 查询注册的 URL 格式；macOS 读 NSPasteboardTypeURL。 | **中** · 应用索取剪贴板 URL 时调用。 |
| `clipboardReadRichNative(int kind)` | `byte[]`。0 取 HTML，1 取 RTF，含结尾 NUL；格式缺失时为 null。 | Windows 和 macOS。Windows 读注册的 HTML/RTF 格式；macOS 读 public.html 或 public.rtf。 | **中** · 粘贴或应用主动索取 HTML、RTF 时，按所需格式读取。 |
| `clipboardReadFilesNative()` | `String[]`。文件路径列表，格式缺失时为 null。 | Windows 和 macOS。Windows 读 CF_HDROP；macOS 读路径列表或文件 URL。 | **中** · 应用索取剪贴板文件列表时调用。 |
| `clipboardReadImageNative()` | `int[]`。前两项为宽、高，后接 ARGB 像素；格式缺失时为 null。 | Windows 和 macOS。Windows 解码 CF_DIB；macOS 解码粘贴板里的 TIFF、PNG 等图像。 | **中** · 粘贴或应用主动读取剪贴板图像时调用。 |
| `clipboardReadCustomNative(String name)` | `byte[]`。指定自定义格式的数据，含结尾 NUL；格式缺失时为 null。 | Windows 和 macOS。Windows 按注册格式名称读取，macOS 按对应的 pasteboard 类型读取。 | **中** · 应用索取指定自定义格式时调用。 |
| `clipboardCustomFormatsNative()` | `String[]`。当前可枚举的自定义格式名，使用 `application/x-godot-custom-*` 约定。 | Windows 和 macOS。Windows 枚举剪贴板格式，macOS 枚举 pasteboard 类型。 | **中** · Glass 枚举系统剪贴板格式时调用，即使没有自定义格式也会查询。 |
| `clipboardFormatsNative()` | `int`。标准格式位掩码，1 文本、2 HTML、4 RTF、8 URL、16 文件、32 图像。 | Windows 和 macOS。Windows 查询可用格式，macOS 查询 pasteboard 类型；两端返回同一套位掩码。 | **中** · Glass 枚举系统剪贴板格式时读取标准格式位掩码。 |
| `dragStartExternal(String text, byte[] html, byte[] rtf, String url, String[] files, String[] customNames, byte[][] customData, byte[] dragImage, byte[] dragImageOffset, int effects, int buttons, long sourceId)` | `void`。提交外拖请求。effects 为允许动作，buttons 为按键位掩码，sourceId 为源 Glass 窗口 ID。最终动作通过种类 20 的输入记录异步返回。 | Windows 经模态 DoDragDrop 返回动作。macOS 使用异步 Cocoa 会话。Linux/Wayland 使用原始按下事件的座席序列号发起 wl_data_device.start_drag，以 wl_data_source 的最终动作或取消事件结束。 | **中** · 一次拖动交给系统进行跨应用传输时提交一次。 |

Linux Wayland 原生拖放支持应用私有的 `application/x-<suffix>`。后缀由小写 ASCII 字母、数字、点、短横线或下划线组成，整个名称最多 128 个字符。`application/x-java-*` 由 Glass 保留。出站 `customData[i]` 和入站回调的同名参数都附加一个 JNI 结尾字节。在 Wayland 管道中，新支持的私有 MIME 按原始长度传输，可含嵌入和末尾零字节。已有 `application/x-godot-custom-*` 继续使用旧的零结尾格式。每次传输至多 32 种自定义格式，每项含 JNI 结尾字节最多 16 MiB。同 JVM 的目标读取源 Dragboard 中的原始值。外部进程交付的私有载荷以 `byte[]` 交给应用。

拖动预览图可省略；传入时，`dragImage` 是大端宽高加 BGRA 数据，`dragImageOffset` 是大端 x/y 偏移。剪贴板和拖放分别持有载荷。[Java 桥接声明](../jfx/modules/javafx.graphics/src/main/java/com/sun/javafx/tk/godot/GodotBridge.java) · [剪贴板格式解释](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotSystemClipboard.java)

## Upcall · Godot → Java

| 原生触发点 | Java 回调及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- | --- |
| 引擎已连接宿主并注册 GodotBridge | `ready.run()`，接收者为传给引擎的 `Runnable ready`，无参数 | `void`。在引擎线程同步发布就绪，返回后进入主循环。 | 各平台共用。Windows 在宿主线程回调，macOS 在 AppKit 主线程回调。 | **低** · 每次引擎成功连接后通知一次。 |
| macOS 把引擎循环交给 AppKit 主线程 | `callback.run()`，接收者为传给 `runOnAppKitThread` 的 Runnable，无参数 | `void`。在 AppKit 主线程运行整个回调。产品和场景夹具共用同一原生实现。 | macOS 专用。Windows 直接在 Java 中运行引擎循环。 | **低** · macOS 启动时执行一次，回调内驱动整个引擎循环。 |
| 原生拖放目标需要立即答复 | `GodotBridge.dragTargetCallback(int kind, long windowId, int sx, int sy, int effects, int keyState, String mimes, String text, byte[] html, byte[] rtf, String url, String files, String[] customNames, byte[][] customData)` | `int`。同步返回选中的 Glass 拖放动作，0 表示拒绝或没有动作。 | Windows 经 OLE，macOS 经 Cocoa。Wayland 从 wl_data_device 接收进入、移动、离开和放下，将事件转交 Godot 主线程；按 wl_data_offer 提供的 MIME 类型通过管道读入数据，接受动作限于协议支持的复制和移动。HTML、RTF 与自定义数据以 NUL 结尾的字节数组传入。 | **高** · 跨应用拖动悬停期间，系统每次更新目标都可同步回调；进入、离开和放下也会调用。 |

拖放的 kind 1/2/3/4 分别为进入、移动、离开、放下。sx/sy 为屏幕坐标，effects 和 keyState 携带允许动作及按键状态，mimes 和后续字段携带格式与载荷。注意入站的 `files` 是按换行分隔的一个字符串，出站的 `dragStartExternal` 接收路径数组。普通窗口输入由 Java 调用 `pollWindowInputV2()` 取走。[启动就绪回调](../native/godot_modules/javafx/javafx_library.cpp) · [AppKit 回调](../native/godot_modules/javafx/javafx_library_macos.mm) · [Windows 拖放调用点](../native/godot_modules/javafx/windows_dnd.h) · [macOS 拖放调用点](../native/godot_modules/javafx/macos_dnd.h)

## 场景测试夹具

| 方向 | GodotSceneFixture 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- | --- |
| Downcall | `run(String library, String driver, String[] arguments)` | `int`。以共享库路径、驱动和引擎参数运行夹具，正常返回 Godot 退出码；原生创建或启动失败可返回 1。 | 各平台共用。Windows 从夹具 main 直接进入，macOS 由 AppKit 主线程进入。 | **低** · 每次场景夹具启动一次。 |
| Downcall，仅 macOS | `runOnAppKitThread(Runnable loop)` | `void`。复用上述 AppKit 主线程回调；夹具在 Java 闭包内保存 `run` 的退出码。 | macOS 专用。Windows 夹具直接调用 run。 | **低** · macOS 夹具启动时切到主线程一次。 |
| Upcall | `runProbe(String mainClass)` | `void`。宿主的夹具工作线程传入探针主类名；Java 调用其 main 并等待渲染线程退出，失败可抛 Throwable。 | 各平台共用 | **低** · 宿主启动指定 Java 探针时调用一次。 |

[夹具 Java 源码](../tests/reference/GodotSceneFixture.java) · [原生夹具启动](../native/godot_modules/javafx/javafx_library.cpp) · [runProbe 调用点](../native/godot_modules/javafx/javafx_host.cpp)

## 历史 · 基线之后引入又移除的 JNI 入口

原 11 个无 `Native` 后缀的 `clipboard*` JNI 注册名已移除，其 Java 方法成为同签名的平台分派入口。
Windows/macOS 使用主表列出的私有 `*Native` 方法，参数、返回值与调用频率不变。
Linux 通过 Wayland MIME offers 交换相同负载，以上 11 个 Godot downcall 的 Linux 频率均为零。


| 方向 | 当时的 GodotBridge 方法及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- | --- |
| Upcall | `System.getProperty("javafx.godot.driver")` | `String`。曾从原生端查询 JVM 驱动属性。 | 两平台的库和场景启动现由 Java 传入解析好的驱动。 | **低** · 原为每次引擎启动一次。 |
| Downcall | `usesWaylandDisplay()` | `boolean`。曾查询当前显示服务。 | Linux 宿主固定使用 Wayland。 | 已移除。 |
| Downcall | `usesWaylandClipboard()` | `boolean`。返回当前显示服务是否为 Wayland。 | Linux，已改名为 `usesWaylandDisplay()`，供剪贴板与弹出窗口共用。 | 每次 Glass 初始化一次。 |
| Downcall | `clipboardWriteText(String text)` | `void`。将 Unicode 纯文本写入 Windows 剪贴板。 | Windows 专用。macOS 移植前已删除。 | **低** · 移除前的 Glass 常规写入已走多格式入口，未见产品调用点。 |
| Downcall | `clipboardHasText()` | `boolean`。Windows 剪贴板提供 Unicode 文本格式时返回 true。 | Windows 专用。macOS 移植前已删除。 | **低** · 移除前的 Glass 枚举已走格式位掩码，未见产品调用点。 |
| Downcall | `isRDDirectCompiled()` | `boolean`。宿主在编译时启用旧 RD-direct 后端时返回 true。 | Windows 专用。macOS 移植前已删除。 | **低** · 旧管线启动诊断或构建能力探针查询时调用。 |
| Upcall | `launch(String mainClass)` | `void`。旧宿主传入 Java 主类名并等待应用，Java 异常可传回原生调用方。现行场景测试改由 `GodotSceneFixture.runProbe` 接收主类名。 | 两边共用。最初用于 Windows；macOS 移植后也经该入口启动，随后两端一起移除。 | **低** · 旧宿主启动 Java 主类时调用一次。 |

旧宿主还曾通过 JNI Invocation API 创建和销毁 JVM，这些是 JDK 提供的虚拟机管理函数。

清单以跨语言方法签名为单位。沿已有入口新增的绘制操作码、宿主命令号及输入事件种类，可从协议表继续查到。上游已有的 JNI 方法也可能被本后端复用，例如 GodotRobot 的按键、鼠标按下/释放和滚轮委托给 WinRobot 或 MacRobot；上面的三个 Robot downcall 是本项目另外为位置、移动和截图添加的入口。[命令与事件协议](bridge-protocol.md) · [Robot 委托实现](../jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot/GodotRobot.java)

## 附录 · Windows 测试直接使用的 Panama FFM downcall

三个测试探针通过 FFM 读取本进程数据或验证 Media Foundation 生命周期，共绑定 16 个不同目标；`GetCurrentProcess` 在两个探针中复用。它们调用 Windows 系统库，此处没有 FFM upcall。表中 `ptr` 对应绑定的 `ValueLayout.ADDRESS`，在 Java 侧用 `MemorySegment` 传递；`int` 对应 `JAVA_INT`，保留原生 32 位值的位模式。标为 out 的参数由原生函数写入。

| FFM 调用及参数 | 返回类型与含义 | 平台与实际路径 | 频率与触发条件 |
| --- | --- | --- | --- |
| `GetCurrentProcess()` | `ptr`，当前进程伪句柄。 | Windows 专用 | **中** · 每次进程指标采样、每次句柄普查各取一次。 |
| `K32GetProcessMemoryInfo(ptr process, ptr countersOut, int bytes)` | `int`，非零成功；内存计数写入 countersOut。 | Windows 专用 | **中** · 每次 Windows 进程内存采样一次。 |
| `GetProcessHandleCount(ptr process, ptr countOut)` | `int`，非零成功；句柄数写入 countOut。 | Windows 专用 | **中** · 每次 Windows 进程指标采样一次。 |
| `PssCaptureSnapshot(ptr process, int flags, int contextFlags, ptr snapshotOut)` | `int`，Windows 错误码，0 成功；输出快照句柄。 | Windows 专用 | **中** · 每次启用的句柄普查创建一份快照。 |
| `PssFreeSnapshot(ptr process, ptr snapshot)` | `int`，Windows 错误码，0 成功。 | Windows 专用 | **中** · 每次句柄普查结束释放一次。 |
| `PssWalkMarkerCreate(ptr allocator, ptr markerOut)` | `int`，Windows 错误码，0 成功；输出遍历标记。 | Windows 专用 | **中** · 每次句柄普查为遍历创建一个标记。 |
| `PssWalkMarkerFree(ptr marker)` | `int`，Windows 错误码，0 成功。 | Windows 专用 | **中** · 每次句柄普查结束释放一个标记。 |
| `PssWalkSnapshot(ptr snapshot, int infoClass, ptr marker, ptr entryOut, int bytes)` | `int`，0 表示读到条目，259 表示枚举完毕。 | Windows 专用 | **高** · 普查期间逐条遍历句柄，直至枚举结束。 |
| `NtQueryObject(ptr handle, int infoClass, ptr infoOut, int capacity, ptr bytesOut)` | `int`，NTSTATUS，探针在返回 0 时读取对象类型。 | Windows 专用 | **高** · 普查期间对缺少类型名称的句柄逐个查询；名称齐全时为零次。 |
| `EnumerateTraceGuidsEx(int queryClass, ptr input, int inputBytes, ptr output, int capacity, ptr bytesOut)` | `int`，Windows 错误码；0 成功，122 表示需要更大缓冲区。 | Windows 专用 | **高** · 启用 ETW 普查后，先枚举列表，再逐个查询提供程序；缓冲区不足时重试。 |
| `CoInitializeEx(ptr reserved, int flags)` | `int`，HRESULT，负值表示失败。 | Windows 专用 | **低** · 探针启动时初始化当前线程一次。 |
| `CoUninitialize()` | `void`，结束当前线程的 COM 初始化。 | Windows 专用 | **低** · 探针退出时清理当前线程一次。 |
| `MFStartup(int version, int flags)` | `int`，HRESULT。 | Windows 专用 | **中** · 生命周期探针每轮初始化一次，共 24 轮。 |
| `MFShutdown()` | `int`，HRESULT。 | Windows 专用 | **中** · 生命周期探针每轮关闭一次，共 24 轮。 |
| `MFCreateSourceReaderFromURL(ptr utf16Url, ptr attributes, ptr readerOut)` | `int`，HRESULT；成功时写入读取器接口指针。 | Windows 专用 | **中** · 提供媒体路径时，每轮创建一个读取器。 |
| `IUnknown::Release(ptr reader)` | `int`，按无符号 32 位读取剩余引用数；目标来自读取器虚表槽 2。 | Windows 专用 | **中** · 每轮成功创建读取器后释放一次。 |

[进程内存探针](../tests/reference/CurrentProcessMemory.java) · [句柄与 ETW 探针](../tests/reference/CurrentProcessHandles.java) · [Media Foundation 探针](../tests/reference/MediaFoundationLifecycleProbe.java)
Linux x64 移植说明：现有 `dialogSubmit`、`dialogPoll`、`dialogCancel`
在 Linux 实现中使用同一份 Unix 请求队列，由 Godot 主线程驱动 GTK 3
文件选择器。Wayland 通过 xdg-foreign
关联所属窗口。参数、返回值和调用频率沿用主表。见 [Linux 选择器](../native/godot_modules/javafx/linux_dialogs.cpp)。

Wayland 的 `dragTargetCallback` 接收相对于目标表面的设备像素坐标。
Glass 根据目标窗口 ID 查找窗口，保留该局部坐标并以 Glass 窗口原点换算
JavaFX 事件的屏幕坐标。Wayland 后端选择在 Glass 应用初始化时查询。
