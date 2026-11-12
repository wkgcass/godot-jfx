# 实现审查状态与验证限制

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


本文顶部记录当前审查状态，其余章节保留各轮修复证据。历史章节中的“当前”“剩余”“未完成”仅指当时阶段；原始范围和累计修复收尾以顶部状态为准。测试与源码索引只是证据导航，不单独构成完成证明。

## 当前收尾状态与已有结果

本次固定实现审查已完成：原始 156/156、累计补充 52/52。所有当前修改都登记到源码审查或关联修复中；交付清单与完整完成核对位于 artifacts/review-completion-audit.json。

共享缓存修复后六轮导航、清理及生命周期测试通过；目标数第 3–6 轮保持 232，最后两轮首页纹理内存相同，静态内存约 240.6→241.2 MiB。材质等有界缓存仍少量填充，进程内存也不是严格常数；这是有限工作负载的预热趋缓证据，不是无限时长无泄漏保证。详见 memory-validation.md。

本次收尾另修复 LCD 截图写入失败未检查及 IME/InputCancel 探针中断退出路径。
LCD 正常对照与隔离写入失败、两个探针宿主回归及隔离中断退出检查均通过；
累计入口复核和新运行证据见 `artifacts/review-cumulative-closeout.json`。

2026-11-11 共享缓存构建 mobile/safe 的 68 次切页：RD1/LCD1 为
59.662 Pulse FPS / 56.786 宿主合成 FPS；RD0/LCD1 为 58.604 / 55.741。
两者失焦 0、资源清理通过；独立复算/哈希见 `artifacts/review-shared-mesh-performance.json`，
日志为 `review-shared-mesh-transition-rd0.log` / `-rd1.log`。不是所有页面稳定 60 或物理扫描帧率。
此前 58.742/56.543、59.386/56.668 等保留为历史测量。

| 项目 | 当前证据与下一步 |
| --- | --- |
| 最新 soak 运行中增长（本轮修复及有界验证完成） | 三轮首页 owned 4869→6166→6840，static 404→578→670 MiB；自然 GC 22 次，末半段进程 private OLS 约 +160 MiB/min。最终 owned=0 仅证明退出释放，不能证明运行中稳定。报告 review-final-soak-growth.analysis.json；分类复验发现 220 个目标共缓存 57435 个网格；现共享 4096 项/48MiB 目标缓存，旧二进制回归失败、新版 GL/Vulkan 像素/生命周期通过，修改后三轮/六轮 soak、生命周期及双路径帧率均通过；剩余有界缓存填充与验证范围见顶部 |
| 默认 separate 的一次像素失败 | 已确定旧完成通知可使第 275 轮读到上一轮颜色，并修复等待边界；新增显式通知积压回归档。原始偶发失败无截图，不能断言与确定性复现完全同因；保留原记录，后续失败须分析当次截图 |
| 剪贴板互操作 | 较早 mobile Editor/Runtime 格式交换及原始字节恢复通过；后续快照/JNI 修复后的完整复验因 Chromium 未知私有格式在写入前被拒绝，无待恢复内容。相关失败路径已有独立覆盖，最新构建完整互通仍未复验；不得绕过保护 |
| 虚拟键盘实际显示/关闭 | Java 调用及 tick 检查通过，系统关闭请求返回拒绝访问。保留系统能力限制，不把 PASS 当作可见性证明 |
| OLE 回调与 JVM 退出（已修复） | UpcallState 用同一互斥锁保护入口发布、完整回调和关闭；关闭完成后才 DestroyJavaVM。附加线程前暂停的回归通过，移除锁会明确失败；真实 JVM 的 OLE 入站超时取消通过。不是所有系统退出时序的穷举证明 |
| 全范围完成核对 | 原始 156/156、累计补充 52/52；源码核对、缺陷回归、双路径性能和六轮资源观察完成。哈希/清单用于对应证据，不替代实跑 |

已完成的近期修复包括失效材质滞留、材质碰撞串色和同步备用回调生命周期；
它们各有修复前复现与修复后回归，见下文。已通过的 Robot、Media、GPU、
构建和性能记录按各自配置有效，不再把旧的撤回授权或命令拒绝当作当前阻塞。
更广的项目验收限制（如混合 DPI、真实音频/A-V 同步）仍在 acceptance-status.md，
与固定代码质量审查分别追踪，不扩展成本轮未经要求的新功能。

**当前输入测试授权：2026-11-10 用户重新明确允许 Robot 及其他测试。本轮真实输入测试串行运行；下文较早的停止记录保留为历史，不代表本轮仍被禁止。后续若用户再次要求停止，应立即停止。**

历史修复及运行记录见
[progress.md](progress.md)，验证范围见 [acceptance-status.md](acceptance-status.md)。

早期系统接口补测：剪贴板快照曾因 Chromium 私有格式拒绝测试写入；此后的完整
互操作及恢复曾通过；后续完整复验再次被私有格式保护拒绝，最新范围以上表为准，未绕过保护。虚拟键盘调用、tick 推进和探针清理通过，但系统
关闭请求返回拒绝访问（HRESULT -2147024891），不算显示/关闭验收通过。
包装脚本现在会直接显示原生警告并标明 PASS 范围。日志为
`artifacts/logs/review-final-clipboard.log`、`review-final-virtual-keyboard.log`
及 `virtual-keyboard.log`。原来的仅编译记录是历史状态。

## 已验证：真实 Demo 悬停测试（2026-11-10）

### 旧通知导致像素误判的确定性对照（2026-11-11）

基于当前 shader-cache 创建两个独立项目，在第 274 轮结束前排队八次旧画面
绘制并同步读回，阻止主线程在此期间消费完成通知。旧等待版本第 275 轮失败：
左侧仍为红色 (1,0,0,1)，期望蓝色 (0,0,1,1)，右侧绿色保持正确。修正后的
pre-draw/post-draw 顺序在相同注入下完成全部 305 轮。日志为
`review-shader-queued-notice-old.log`、`review-shader-queued-notice-fresh.log`，
失败图为 `artifacts/reference/shader-cache-failure-3460-cycle-275.png`。
对照源码保存在 `artifacts/native-tests/shader-notification-repro/`。

这将此前“通知计数不保证新绘制”的证据推进到真实像素误判；仍不具备原始偶发
失败的像素证据，不能断言两个事件完全同因。新增 `-QueuedNotifications` 显式
回归档保留相同注入，不改正常运行配置、不放宽断言，也不作为性能测量。

### separate 像素异常的有界复现（2026-11-11）

新增六次串行 mobile/separate shader-cache 运行全部通过，日志为
`artifacts/logs/review-pixel-repro-1-full.log` 至 `review-pixel-repro-6-full.log`。
保留相同像素断言、等待方式及失败截图逻辑，没有新增重试或放宽阈值。
源码检查确认 separate 模式的 `frame_post_draw` 经延迟调用送回主线程，
因此通知送达与当前测试命令完成不是同一概念。

随后独立探针实际制造了积压通知：等待三次 post-draw 前后提交计数均为 9，
证明原等待方式不能保证新的绘制。改为每轮先等 pre-draw 再等 post-draw 后，
计数从 9 增至 13，见 `artifacts/logs/review-post-draw-notification-probe.log`；
探针源码保存在 `artifacts/native-tests/post-draw-notification-probe/probe.gd`。
压力夹具据此修正等待边界，仍为三轮、相同像素阈值，不加入失败重试。
这证明并修复测试同步缺口，但尚不能证明第 275 轮历史异常由它引起，
也不意味着生产渲染路径已排除问题。
修正后的 mobile/safe 与 mobile/separate 全部检查通过，日志为
`review-shader-fresh-draw-safe.log`、`review-shader-fresh-draw-separate.log`。

同类检查发现 Surface、生成 Shader、RenderTarget 和网格变换的固定轮数等待
也缺少新绘制边界，现采用相同修正。四个场景在 mobile/safe、mobile/separate
共八次运行通过，证据为 `review-fresh-draw-<场景>-<线程模式>.log`，场景分别为
`main`、`shaders`、`render_targets`、`mesh_transform_probe`。此轮没有启用网格
CachePressure，不能把普通变换测试替代已有的 4097 项缓存压力证据。
RD corpus/LCD/translate 在提交参照画面后也按完成通知计数，现同步修正。
三者 mobile/safe 与 mobile/separate 的六次运行通过；日志同上命名，场景为
`rd_corpus_spike`、`rd_lcd_spike`、`rd_translate_spike`，两次 corpus 均为
exact=262、edge=0、deferred=0、failed=0。
随后核对直接 RD 诊断场景，同样补齐桥接预览读回前的 pre-draw 边界。
mobile/safe 与 mobile/separate 均通过，日志为
`review-direct-fresh-draw-safe.log`、`review-direct-fresh-draw-separate.log`。
此处只验证诊断设备路径及桥接像素，不替代生产 RD 回归。
宿主状态轮询（例如 external drag）由终态和期限决定通过条件，不作机械替换；
Media 的信号连接用于诊断计数，也不是本次像素等待修正的对象。

### 后续修复：separate 同步备用路径的对象回调生命周期

后续同类回调检查（当前源码）：

| 路径 | 回调数据与完成边界 |
| --- | --- |
| RenderTarget proxy 初始化、默认离屏派发 | 静态回调按值绑定 RID；后续释放使用同一 RenderingServer 队列 |
| RenderSurface 区域上传 | 绑定 RID、Image 引用与区域值；私有 shadow 修改前分离，不捕获 surface/map 地址 |
| OffscreenPass 批次、uniform 构建、读回、释放 | 使用共享暂存区或借用参数地址的任务均在复用/返回前 sync；读回把 COW 所有权移出暂存区 |
| RD 顶点上传、pipeline 析构/创建失败释放 | 上传绑定字节所有权，释放绑定 RID 值，不保存被销毁对象地址 |
| RD direct 诊断渲染/转换与释放 | 渲染任务后 sync 再读取全局结果；释放任务按值绑定 RID |
| Host/WindowSurface 帧信号 | 退出树时断开连接，清理 pending 状态；合成完成的 separate 路径绘制并 sync 后才释放引用 |

当前未发现另一处与备用路径相同的迟到对象回调问题。最终 Runtime 的
`test-rd-regressions.ps1 -Runtime -RenderThread separate` 通过：读回/输入所有权、
uniform 退休、屏幕采样、pipeline 淘汰与待绘制源复制等门禁，完整日志
`review-render-callback-runtime-full.log`。该证据不覆盖所有调度或设备销毁故障。

在 `GODOT_JFX_ASYNC_PASS_FENCE=0`、`GODOT_JFX_PASS_SYNC_INTERVAL=0` 下，
原 `draw_offscreen_pass` 会将绑定 this 的方法排入渲染队列，却提前读取成员耗时
并返回。新增 128 次提交后立即释放目标的检查复现了 Invalid Object id 回调错误；
原 100 轮像素检查仍输出 PASS，包装脚本正确因 ERROR 拒绝整项通过。

现 separate 备用路径在返回前等待回调完成，保证对象及耗时访问的生命周期；
默认按 RID 值排队的异步路径保持原来的批次等待。Editor/Runtime 构建成功，
mobile/separate 的开关 0、1 都通过；GL/separate 的开关 0 也通过，均含原有
100 轮复制/透明度/资源门禁。日志 `review-sync-fallback-before-full.log`、
`review-sync-fallback-after-{0,1}-full.log`、`review-sync-fallback-gl-full.log`。
该非默认配置错误有独立复现，不能用于解释此前默认 separate 的一次像素失败。

### 后续修复：材质哈希碰撞改变已排队绘制

当前夹具进一步覆盖删除后的复用：销毁第一组独占的真实纹理，验证对象已释放，
再连续两轮绘制第二组，颜色正确且缓存降至一项。mobile/safe 完整通过，日志
`review-material-collision-retire-full.log`。不可变材质版本的最终 Runtime 也已
在 RID 缓存显式开启时完成 24 轮 Media `-Providers` 回归：owned 全部 31，
退出归零，AAC 检查通过；日志 `review-immutable-material-churn-full.log` 与
`review-immutable-material-churn-aac.log`。此为有界资源与 provider 验证，
不宣称所有进程内存或所有播放时长均无增长。

新增真实 sampler RID 字典碰撞像素夹具，修复前复现 `(3,68,22)` 与 `(19,55,21)`
共用 hash 后，左侧被第二组颜色覆盖。原来的 sampler patch 优化会就地修改
已发布材质；现移除该路径，保留不可变参数，按完整内容匹配碰撞条目，并在删除
留下空位后仍搜索已有条目，避免重复创建。旧 MATERIAL_PATCH 环境开关不再生效。

Editor 的 mobile/safe 完整 shader-cache 通过；mobile/separate 首次碰撞专项通过，
但后续旧压力段第 275 轮像素失败。增加实际像素诊断后重跑完整通过，故保留此
一次失败为待定位的间歇现象，不能以第二次通过宣称根因已修复，也不放宽断言。
日志位于 `artifacts/logs/review-material-collision-before-full.log`、
`review-material-collision-safe-full.log`、`review-material-collision-separate-failure.log`
和 `review-material-collision-separate-diagnostic-full.log`。

后续针对该未定位失败，mobile/separate 连续三个独立进程完整运行均通过，
日志 `review-separate-cache-1-full.log` 至 `review-separate-cache-3-full.log`。
这不能否定首次失败，也没有证据将其归因于偶发长帧。夹具现在保存失败当次
读回图像（不重读、不重试、不改变阈值），GDScript 检查通过；尚无新失败可供
截图分析。源码只确认测试通过自动 Viewport 更新并等三个 frame_post_draw，
不能由此直接证明第一次失败的原因。

进一步创建独立临时项目（只复制 project.godot、shader_cache.gd/tscn，不复制
原项目 `.godot`），mobile/separate 完整通过；日志 `review-cold-cache.log`，
项目路径记录在 `review-cold-cache-project.txt`。这覆盖新的项目缓存，未清理
驱动级缓存，不能宣称完全冷启动。复核源码名缓存：查询返回 COW Vector 值，
调用者不持有会被淘汰的条目引用；相关调用在主线程宿主/目标路径，未发现该
缓存淘汰能直接解释此失败的证据。当前不据此修改生产同步或延长测试等待。

GL/safe 完整检查也通过；Editor/Runtime 构建成功。修复后 Viewport mobile/safe
切页 68 次为 58.700 Pulse FPS / 56.133 宿主呈现 FPS，未失焦、资源清零，
证据 `review-material-collision-gl-full.log`、`review-material-collision-transition-full.log`。

### 后续发现并修复：Viewport 材质缓存滞留

最终 Runtime 的默认 Viewport Media churn 实际在第 11 轮失败：owned 从首轮
31 增至 51，纹理内存维持 4644864 字节。仅关闭 RID 材质缓存的诊断对照完成
24 轮、owned=29，定位到缓存一直保留已失效采样纹理的材质，直到 256 项压力
才清理。该诊断不作为交付配置；断言没有放宽。

`JavaFXRenderTarget::acquire_material` 现在在缓存未命中时回收失效条目，
一并移除顺序索引；材质仍交给原有 pass 资源列表延迟释放，保留已排队绘制的
生命周期。命中路径不增加全表扫描。另修复同一函数删除 map 条目后再次读取
旧指针的风险，使用互斥分支处理相同内容与哈希碰撞。

Editor/Runtime 重新构建成功；开启 RID 缓存的 mobile/safe Runtime 24 轮
`-Providers` 回归通过，owned 全程 31，退出为 0；纹理内存稳定。mobile 的
shader 与 mesh-transform -CachePressure 像素回归通过。未将此宣称为无限期
无泄漏或删除后访问的 ASan 动态覆盖。

证据均在 `artifacts/logs/`：`review-final-media-churn-runtime-full.log`（修复前）、
`review-media-churn-cache-diagnostic-full.log`（关闭缓存对照）、
`review-material-retirement-churn-full.log`（正常缓存修复后），以及同前缀构建、
shader、mesh 日志。视频控制和 WAV/MP3/AIFF 的最终 SDK/Runtime 组合也已通过；
实际听音和音画同步仍未验收。

本轮重新授权后，最终产物的补充回归通过：mobile/separate Editor 的 Robot、外部
OLE 拖放、hover-flicker -Robot、physical-drag -Robot、六用例文件对话框；
mobile/safe Runtime 的 Robot 与外部 OLE 拖放。当前表格水平 Robot 回归也通过，
96 Pulse、60.004 FPS、867px 位移且未失焦，补上此前受用户操作干扰的这一次验证。
日志见 `artifacts/logs/review-final-*.log` 及对应脚本的标准日志。

最终 RD 切页测量不再受旧拒绝记录阻塞：显式 RD_DIRECT=1、LCD_SCREEN=1，
mobile/safe，68 次切页，59.006 Pulse FPS、55.946 宿主呈现 FPS，未失焦，
资源清理通过。`review-final-transition-full.log` 与独立复算
`review-final-transition-rates.json` 保存证据；此结果不保证每页稳定 60 FPS，
也不等同物理显示帧率。未扩展为混合 DPI 或所有系统功能的完成声明。

`HoverDemoProbe.java` 的线程、无限等待、异常传播和清理问题已修正；所有节点访问
和监听器安装在 FX 线程，每次 FX 调用有 10 秒期限，渐进移动间隔在工作线程等待。
保留 LoadingStage 页面、八轮靠近/保持/移出，要求找到正确且启用的目标按钮，
不再静默换成其他按钮。退出恢复原鼠标位置并回收线程/全局服务。

`hover_demo.gd` 已使用当前缩放并要求八轮均有稳定样本；沿用原诊断阈值 0.30，
跳过每轮前 31 帧，稳定期亮/暗错误比例不得超过 5%。当前 mobile/safe 真实运行通过：
八轮 enters=8、flickers=0，稳定期 hold=861、gap=511，亮暗检查全部符合。
日志 artifacts/logs/hover-demo-mobile-safe.log；此为指定页面/配置的有界验证。

- `test-hover-demo.ps1 -CompileOnly`、GDScript 和 PowerShell 解析检查通过。
- 用户已于 2026-11-10 授权后续真实键鼠 Robot 测试；`test-hover-demo.ps1 -Robot` 已通过。
- 旧 HOVER_DEMO_PASS 无像素门禁，不能替代新版验收。已有 hover-flicker 测试
  也不能替代这个真实 Demo/LoadingStage 场景。

## 快速拖动与缩放的当前验证（2026-11-10）

PhysicalDragProbe 补齐退出时光标恢复，各清理操作独立尝试并记录错误；合成驱动
移除固定 ×2 坐标，按初始窗口实际尺寸换算。mobile/separate 合成和真实 Robot、
GL/safe 合成通过。真实输入得到 Y=-14、740×576，连续手势检查和资源归零通过；
日志 physical_drag-mobile-separate-robot.log。当前实际 2 倍 DPI，其他缩放与清理
故障注入仍未覆盖；此结果不替代所有物理测试。

## SceneView 原始改动及相邻生命周期复核（2026-11-11）

本次重新读取 `javafx_scene_view.cpp/.h` 的完整实现，并检查相邻调用方，
未发现需要更改生产代码的问题。逐项依据如下：

- 原始改动中的 sampler 移除位于删除仍存活的 SubViewport 之前；Surface 的
  `dispose_texture` 和 `release` 也移除其登记的 sampler，不能只依赖包装对象析构。
- `add_scene_view` 在 Canvas 命令存在时通过 `sampled_scenes` 持有包装对象；
  纹理句柄释放后，已引用的场景由 `retired_scenes` 延迟持有，清理绘制后才释放。
- `viewport_id`、`scene_id` 经 ObjectDB 查询，不缓存可悬空的节点指针；父树先
  销毁时，包装对象查询返回空，不再次删除已销毁的节点。
- `sceneInput` Java 编码及 `SCENE_INPUT` C++ 解码都检查输入类型、Unicode、
  有限坐标及鼠标按钮 1..9，消费者的按钮位移依赖此校验；资源表另外验证场景
  类型、存活与 generation。`dispatch_input` 不是公开 GDScript 绑定入口。
- resize 的资源表拒绝仍被当前 pass 引用的旧句柄，消费者保留同一 SceneView
  引用并更新尺寸后迁移句柄；没有复制整个场景或按帧创建新场景。

当前 Editor 的 mobile/safe、mobile/separate `scene_views.tscn` 均通过：
各 100 轮加载、缩放、直接输入、纹理持有与释放，并验证嵌入弹窗、最终像素和
父节点先销毁的兜底释放。日志 `review-scene-lifetime-safe.log`、
`review-scene-lifetime-separate.log`。该夹具的 `push_input` 是直接合成输入，
不能用来宣称本轮重新执行了 Java 编码输入或焦点丢失的取消路径；后两者的
协议与 GodotView 既有证据仍按各自范围使用。本次没有修改其等待逻辑。

## 整体审查的完成条件

近期调度路径复核：GodotEventLoop 的入队/停止共享 lifecycle 锁，同步任务被
取消时完成其 future；应用终止顺序先关闭 scheduler，再停止 event loop。
GodotPulseScheduler 合并排队 pulse 并在派发时复核 running。未改生产实现。
发现并修复 `GlassSchedulerProbe` 独立队列测试的失败清理：闩锁释放、stop 和
线程 join 现在位于 finally。正常双侧测试通过，日志 `review-scheduler-cleanup.log`；
在 held/queued 两处注入断言的独立探针也确认无新增非守护线程残留，见
`review-scheduler-failure-cleanup-0.log`、`review-scheduler-failure-cleanup-1.log`。
这两次故障注入证明夹具的断言失败清理，不是 JVM 线程创建失败或任意资源耗尽的验证。

- 将原始根仓库及 Godot/JFX 子模块变更逐项对应到源码审查和适用验证；目前不能仅凭
  历史 PASS 或变更清单宣布全部完成。基准范围为根仓库 9ae5a635 之后的原始变更，
  JFX 从 4f673a0544a23b4c56c4899278254b15e4fbdd6f、Godot 从
  420dfdc1c302dff13a357f178cfb53f6fe97e6ad 起，并包含本轮修复。
- 修复后的 ExternalDragProbe 已通过 mobile/separate 真实运行；NativeTableDrag 原生对照的水平/垂直各 96 间隔及正常退出已通过，其他物理路径按各自记录继续验证；
  合成输入、编译成功及故障注入各自证明的范围须分开记录。
- Windows 拖放注册失败、GPU 分配失败等未动态注入路径，保留其验证限制，不能写成
  已实际覆盖所有失败/设备场景。
- FPS 按用户更新后的目标保持接近 60；最新切页 59.006 pulse FPS / 55.946 宿主合成 FPS
  为工作负载平均值，偶发长帧暂不修复。白线、WebKit、3D 不重新纳入修复阻塞项。

## 最终构建与范围一致性核对（2026-11-10）

重新用原始首尾 Git 提交生成路径集合，与固定索引比较：根仓库 127、Godot 10、
JFX 19 均逐路径一致。当前交付清单中的 13 个范围内产物重新计算 SHA-256，均与
清单匹配；唯一缺失项 jfxwebkit.dll 属用户明确排除的 WebKit，不是构建失败。
核对最终 Editor/Runtime 与 Media SDK 的构建成功日志，VFX 子模块无未提交修改；
三个相关仓库的 diff --check 通过。路径/哈希一致仍不等于功能验收。

历史记录（已由上方重新授权后的实际运行补齐）：当时计划在最后一轮原生拖放修复后的构建上补跑 RD1/LCD1、mobile/safe 的 68 次切页，
但启动命令被自动审批以“blocked by policy”拒绝，未提供更具体理由。命令没有
启动；未改写重试来绕过拒绝，也没有新的最终构建 FPS 数据。此前 RD 的
57.553 pulse FPS / 54.325 宿主合成 FPS、随后 Viewport 的 58.464 / 55.786
仍是各自版本和配置的历史证据。此处不宣布整体完成，也不把先前结果伪装为新运行。

## 场景与协议夹具的证据对应（2026-11-10）

2026-11-11 场景主体最终复核：完整读取 clipboard_test、drag_drop、
drag_drop_external、menu_click、ole_inject_test、physical_drag、scroll_wheel、
resize_cursor、virtual_keyboard_test、window_drag 十个原始 GDScript，逐项检查
就绪条件、覆盖要求、超时、终态及清理。未发现新增修改项，结论和当前哈希已
合并到 `review-root-final-audit.json`，累计 52/127 项、剩余 75 项。其 Java 探针
和系统行为不因 GDScript 源码复核自动通过；已有动态证据仍按各测试范围使用。
本轮没有重跑物理输入或剪贴板交换。

原始 19 个 `.tscn` 本次逐一核对：均为单节点、单 Script 引用，ExtResource ID
实际绑定且目标文件存在。完整路径对应见 `artifacts/review-original-scenes.json`。
这是场景绑定检查，不执行脚本主体。下表把先前使用功能名记录的夹具补齐到路径：

| 原始夹具（相对 `tests/`） | 对应源码检查/已有证据 |
| --- | --- |
| `godot/hover_flicker.gd`、`hover_flicker.tscn` | “HoverFlickerProbe 清理复核”及包装器记录；普通/Fusion 像素和退出资源门禁，逐帧读回不算性能测试 |
| `godot/mesh_transform_probe.gd`、`mesh_transform_probe.tscn` | “离屏网格缓存淘汰的生命周期修复”；Surface/Target 4097 项压力与最早排队网格的像素持有验证 |
| `godot/ole_inject_test.gd`、`ole_inject.tscn` | “OLE 合成注入测试”及最新生产读取修复；正常模式已有新构建的双侧 PASS，Timeout 有独立历史记录 |
| `godot/rd_corpus_spike.gd`、`rd_corpus_spike.tscn` | 本次读取完整脚本及包装器：要求 RD 设备、212+50 文件、262 个像素比较全部在 2/255 内，无 edge/deferred 豁免。复读 rd-corpus.log 确认 exact=262/failed=0 |
| `godot/rd_lcd_spike.gd`、`rd_lcd_spike.tscn` | 本次读取完整脚本及包装器：检查三个重写锚点、RD 设备、转换成功及像素差异；复读 rd-lcd-separate.log 与 rd-lcd-safe-runtime.log，均 max_diff=0 |
| `godot/rd_regressions.gd`、`rd_regressions.tscn` | 明确拒绝 Viewport fallback；既有 uniform/pipeline 淘汰、屏幕采样、坐标及输入所有权像素门禁。复读 rd-regressions-separate.log 标记齐全，不是本轮新 GPU 运行 |
| `godot/vfx_table_scroll.gd`、`vfx_table_scroll.tscn` | “表格水平模式覆盖修复”和“持续表格负载与状态参数分流”；共享 Sweeps、轴向位移、移动/闲置统计，物理模式仍禁止未经授权运行 |
| `godot/virtual_keyboard_test.gd`、`virtual_keyboard.tscn` | “虚拟键盘探针的超时与活跃判定”；本次再次核对 30 秒宿主期限及退出资源归零。近期只编译 Java/运行模拟 COM，未重新验收系统键盘可见性 |
| `native/frame_protocol_test.cpp` | “根仓库原始协议变更：几何事务”和“GodotBridge 原始接口与 JNI 对应”；最近组件构建通过原子拒绝、队列背压、停止和 10000 并发帧，不替代 GPU 渲染验证 |

另生成 `artifacts/review-evidence-locator.json`，覆盖固定原始 156 条路径，帮助定位
相关文档章节。其自动匹配及本表人工路径对应都不是整体完成证明；不能以文件名
被提到就认定实现已验证。根仓库及两个相关子模块的 diff --check 本次均通过。

## 完成核对中的夹具与范围说明（2026-11-10）

逐项核对原始 `clipboard_test.gd`、`drag_drop.gd`、`drag_drop_external.gd`：
剪贴板原始变化是有限的 2 秒读重试，并不允许忽略内容不符；现修正注释，读取不符
也可能来自外部改写，不能一概归因占用。拖放合成路径按窗口 ID 投递，原始移除
前台焦点条件不降低其七阶段覆盖断言；外部拖放场景仅管理宿主和 60 秒期限，
真实动作在 Java Robot 探针，不能仅因 GDScript 内没有键鼠调用就运行它。

`ClipboardProbe.java` 的格式、像素与外部同步断言、`MenuClickProbe.java` 的原始
菜单动作调用和 `menu_click.gd` 的宿主渲染进度检查也已核对。菜单成功标记在全局
清理之后，剪贴板原始数据的恢复由 PowerShell 快照器负责。两个 Java 探针在当前
SDK 重新编译通过，本次没有启动或操作系统剪贴板，也没有新物理验收。

`acceptance-status.md` 末尾旧的“当前活动目标”表述已改为历史项目验收要求与当前
代码质量审查的区分。物理输入、跨 DPI、真实音频等缺口继续保留，不借此删去
需求，也不能把项目待办当作撤回后仍可运行 Robot 的许可。整体完成仍需核对
原始范围与累计修复的证据，不由上述文档措辞更改自动成立。

## 原生 OLE 读取异常释放修复（2026-11-10）

原始 `native/godot_modules/javafx/windows_dnd.h` 全部为新增代码。复核读取侧发现
`read_hglobal` 在 vector 复制失败时跳过 GlobalUnlock/ReleaseStgMedium，
`extract_custom` 在字符串或集合分配失败时跳过枚举器 Release。之前针对
`tests/native/dnd_helper.cpp` 的异常释放修复不覆盖这个生产实现。

新增组件测试在修复前复现“Extraction allocation failure leaked lock or medium”，
日志 `artifacts/logs/review-dnd-extraction-before.log`；现以作用域守卫保证先解锁、
后释放介质，并在任意退出路径释放枚举器。TargetHandler 的外层同时捕获 bad_alloc/
length_error，清空旧载荷、返回 NONE 并消费失败拖放，不将异常带过 COM 边界或
继续尝试另一条 Godot 拖放路径。正常格式、动作掩码和 Java 回调顺序不变。

`test-dnd-drag-image.cmd` 的读取复制失败、格式名分配失败、DragEnter/Drop 拒绝
与既有数据对象契约/拖放图像检查均通过（`review-dnd-extraction-after.log`）。
本次异常测试为普通组件构建，未声称 ASan 验证；length_error 由同一边界捕获但未
单独注入。Editor/Runtime 最终源码构建通过，日志
`review-dnd-extraction-editor-build.log`、`review-dnd-extraction-runtime-build.log`。
mobile/separate 模块内 OLE 注入正常路径通过，完整日志
`review-dnd-extraction-inject-full.log`；没有执行真实拖动或改写系统剪贴板。

## Surface 原始缓存路径对应（2026-11-10）

`javafx_render_surface.cpp`、`javafx_render_surface.h` 的原始改动引入局部顶点、
变换/调制命令及网格缓存。当前源码对缓存命中比较完整顶点/颜色，绘制另外持有
retained_meshes 的 Ref，缓存淘汰不会使排队绘制丢失网格。变换命令绘制后复位，
保证后续共享命令项不继承变换；release 清空缓存与持有集合，并移除借用 sampler
标识。原始 GPU timing getter 只聚合已有测量，不在默认路径打开读回。
对应已有 4097 项压力测试及本轮此前的 Surface/Shader 退出缓存归零门禁；此次
只追踪实现和原始差异，没有再改动 Surface 或重复运行 GPU 基础测试。

## 原始测试包装器对应（2026-11-10）

2026-11-11 最终复核：完整读取原始 18 个入口（17 个 PowerShell、1 个 CMD），
逐一检查编译/运行失败门禁、后端、标记和环境恢复；未发现新增修改项。
17 个 PowerShell 当前解析全部通过。原始 19 个 tscn 当前均只有一个 Script
资源引用，目标存在且 ExtResource ID 实际绑定；这只验证资源绑定，不代表脚本
主体通过。逐路径结论和当前哈希合并到 `review-root-final-audit.json`，根仓库
累计最终核对 42/127 项，剩余 85 项仍在 pending 列表；没有重新启动 GUI 或
改写剪贴板。历史动态验证仍按下方各自范围使用。

2026-11-11 补充失败路径证据：对 window-drag、scroll-wheel、resize-cursor、
render-command-validation、virtual-keyboard、image-pool-reuse 六个入口，分别在
相关环境变量原本不存在和已有值的两种状态下传入不存在的 JDK。12 次均拒绝
编译器启动，环境变量与工作目录恢复；没有进入 GUI/键鼠或旧产物运行路径。
记录 `artifacts/logs/review-wrapper-compiler-failure.json`。这只覆盖编译器不可用
这一失败点，不证明编译后或 GUI 失败的所有清理路径。

固定原始范围中的全部 17 个 PowerShell 入口当前解析通过，文件哈希与结果见
`review-current-original-wrapper-syntax.json`；另一个 CMD 入口仍按其源码和组件
执行记录核对。解析与故障注入没有把原生 JavaFX 对照当作 Godot 功能验收。

下列入口已逐一读取当前脚本，核对编译/进程退出码、验证标记和环境恢复；此轮
只做源码与解析检查，不重新执行 GUI、Robot 或系统剪贴板交换。

| 原始脚本（相对 `scripts/`） | 检查结果及适用限制 |
| --- | --- |
| `test-dnd-drag-image.cmd` | setlocal 隔离 MSVC 环境；编译失败不运行旧 EXE，返回测试进程退出码。测试主体使用 COM 数据对象和拖放图像辅助器，不执行 DoDragDrop 或真实鼠标手势；不是外部拖放验收 |
| `test-image-pool-reuse.ps1` | 当前 SDK 编译，分别强制 FIFO/LIFO 并要求 IMAGE_POOL_REUSE_PASS，finally 恢复原开关；对应失效候选解锁用例 |
| `test-drag-drop-ole-inject.ps1` | Godot/Java 双侧 PASS 和成功 Drop 均必需；Timeout 档还要求取消标记。强制选择超时模式并恢复环境，不把普通模式成功当成超时覆盖 |
| `test-physical-drag.ps1` | 显式设置 Robot 开关，默认合成输入；双侧 PASS 与错误日志门禁。真实 Robot 档仍须新授权，本轮未运行 |
| `test-hover-flicker.ps1` | 强制 RD_DIRECT，并要求普通/Fusion 像素、交互及资源清理标记；原环境恢复。可选 Robot 档本轮未运行，逐帧读回诊断不作为性能测量 |
| `test-mesh-transform.ps1` | CachePressure 强制开启缓存，日志区分模式；像素用例 PASS 和退出码必需，恢复压力及缓存开关。对应已记录的 4097 条目排队资源持有验证 |
| `test-render-command-validation.ps1` | 独立 Java 编码器验证，固定缓存开关/1024 条目再恢复；要求编码器 PASS，不启动宿主或证明 GPU 行为 |
| `test-vfx-table-scroll.ps1` | Sweeps 限制 3–30、写入共享驱动参数；明确 Glass-Godot/Prism-Godot 后端、移动/闲置统计和双侧 PASS，恢复自身设置。输入模式由环境选择，运行前仍须排除 Robot 模式；不能只看脚本没有 -Robot 参数就认为免键鼠 |
| `test-clipboard.ps1` | 先备份且拒绝未知私有格式，再启动交换；原始快照在恢复成功前留盘，恢复时检查序列号，失败保留备份。只有交换验证及恢复均成功才输出最终成功。此轮只读源码，没有 Capture/写入/恢复调用，原互操作限制保留 |

上述八个 PowerShell 文件解析通过，记录为
`artifacts/logs/review-original-wrapper-syntax.json`；CMD 按命令和测试入口源码核对。
解析通过不证明所有参数组合或异常分支已运行；本轮未发现需要新增修改的问题。

## GodotBridge 原始接口与 JNI 对应（2026-11-10）

原始 `GodotBridge.java` 新增独立输入唤醒、完整剪贴板格式及外部拖放的接口声明。
本次从新构建的 `javafx.graphics.jar` 用 javap 读取 native 方法描述符，与当前
`javafx_host.cpp` 注册表逐项比较：36 个方法全部同名同签名，无遗漏或多余注册；
结果保存到 `artifacts/review-jni-signatures.json`。另逐项核对反向调用的
dragTargetCallback 与 launch 两个描述符，也与新 SDK 一致。这项检查不执行任何
方法，包括 robot/clipboard 方法，不证明 C++ 函数内部的 ABI 类型或系统行为。

输入调用链已检查：await_input_tick 在 JNI 入口拒绝负序号和不在 1–1000 ms 的
等待值；FrameQueue 在锁内更新独立 input_tick，用条件变量谓词等待，不因帧更新
误认为新输入；finish/stop 唤醒等待者并返回 -1。当前 `test-protocol.cmd` 重新
编译运行通过，覆盖输入计数合并、超时不造 tick、关闭及 10000 帧并发提交；日志
`artifacts/logs/review-bridge-input-protocol.log`。没有新增实现改动或物理输入验收。

## 剪贴板图片复制前的内存预算（2026-11-10）

核对原始 `GodotSystemClipboard.java` 图片扩展与 `windows_clipboard.h::encode_dib`
时发现：原先先在 Java 分配整个 ARGB 数组，之后 JNI 才检查 64 MiB 原生预算。
Glass Pixels 构造器已防止尺寸乘法溢出，但允许的缓冲大于原生发布上限，不能
替代这个较小的预算。现将单边 16384、像素字节加 40 字节 DIB 头不超过 64 MiB
的检查放到 Java `argbPixels` 分配前。没有改变支持的图片尺寸或系统发布流程；
调用方已有的 Pixels 缓冲不由此回收，只避免额外的无效 staging 分配。

离线探针新增小图、单边上限、预算内图片、零/负数、超单边、4096² 加头超预算
及 Integer.MAX_VALUE 尺寸检查，直接调用预检而不分配大图片。Media SDK 源码构建
通过（`review-clipboard-image-budget-build-full.log`），新 SDK 在 32 MiB Java 堆下
通过 `CLIPBOARD_IMAGE_BUDGET_PASS` 和既有 `CLIPBOARD_ENCODING_PASS`；日志
`artifacts/logs/clipboard-encoding.log`。未操作系统剪贴板，未执行实际图片互操作或
原生发布失败注入。原生限制保持不变，不需要重建 Godot。

## Prism 原始状态改动对应（2026-11-10）

2026-11-11 最终源码复核已固定到 `artifacts/review-jfx-final-audit.json`：
BaseContext、GlyphCache、BaseShaderContext、BaseShaderGraphics、GodotContext、
GodotGraphics、GodotShader、GodotTexturePool、ImagePool 共九个原始路径。
逐一对照基线差异、当前调用关系与图像池测试断言，未发现新增修改项；记录各自
源码哈希和结论，并核对既有 FIFO/LIFO、LCD 重叠、源码加载和跨批次像素日志。
内容不变时不重复审查这一组。随后完成其余十个 Glass/Bridge/编码器原始路径
的当前差异与相邻调用复核，同一快照现覆盖完整 19 项，pending 列表为空。
重点核对 IME 筛选先于回调、拖放超时取消、剪贴板转换预算、JNI 声明和编码器
提交失败状态；关联既有正常/超时拖放、IME 顺序、剪贴板精确恢复与批次边界证据。
这只关闭 JFX 原始路径的源码审查，根仓库和累计新增修复仍分别核对；没有由
历史文件名匹配自动宣布全目标完成。此轮没有重跑测试，也不把
这些用例扩大解释为全部字体、DPI、驱动或分配失败场景的验证。

本次对照 JFX 原始提交差异并追踪当前实现，补齐以下路径（相对
`jfx/modules/javafx.graphics/src/main/java/com/sun/prism/godot/`）：

| 原始路径 | 当前检查 |
| --- | --- |
| `GodotContext.java` | 原始变更涉及 LCD pass、透明度调制和局部坐标批次。调制变化先 flush；变换和 clip 使用副本；纹理绑定时保存句柄，配合 GodotTexture.Data.dispose 在编码释放前 flush，避免解锁后再查询失效资源。绘制状态跨编码器批次保留，关闭宿主时取消旧顶点，不重放已取消批次 |
| `GodotGraphics.java` | clear/clearQuad 先 flush；clearQuad 保存二维变换，清屏使用单位变换；非法非有限坐标或 3D 明确拒绝。当前删去原始硬编码剩余字节判断，由编码器按真实命令尺寸处理边界。LCD 每个文本节点先选择目标再建立采样边界 |
| `GodotShader.java` | 常量数组在构造及读取时复制，Snapshot 保存不可变 map；缓存只保存转换后的源码，不冻结后续常量。LCD 重写无法匹配时明确报错，不在禁用 LCDBuffer 后继续使用 dstColor。YV12 保持 R8 平面读取和无 alpha 平面时的有效绑定 |

本组未发现需新增修改的问题。当前 SDK 重新执行三个免窗口测试：源码缓存命中/
容量/动态常量、LCD 原始与改动格式在两种开关下的接受/拒绝、编码器非法几何与
缓存边界，均通过。日志分别为 `artifacts/logs/review-prism-source-cache.log`、
`artifacts/logs/review-prism-lcd-load.log`、`artifacts/logs/review-prism-encoder.log`。
这三项不证明 GPU 绘制顺序或视频像素；相关跨批次、纹理版本、LCD 重叠和 Media
像素验证仍以各自已记录的 GPU 用例为依据。本次没有重跑 GUI 或真实键鼠测试。

## 基础绘制夹具与缓存退出门禁（2026-11-10）

对照原始差异核对四个路径：

| 原始路径 | 检查结果 |
| --- | --- |
| `tests/godot/surface_test.gd` | 原始改动将缓存网格从 owned-resource 计数中分离；现补齐 clear 后保留 1 项缓存、退出树后缓存为 0，以及 100 次创建/销毁每轮缓存为 0 的断言。修正“clear 释放 mesh”的旧错误描述 |
| `tests/godot/shader_test.gd` | 原始改动增加每轮缓存不增长的检查；补齐退出时缓存为 0。包装器还核对生成的 Godot/D3D 变体名称集合及 SDK 内源码，不能仅看此脚本的 count 输出判断生成完整性 |
| `tests/godot/render_target_test.gd` | 原始计数调整保留 source 的 1 项缓存断言；100 轮通过实例 ID 检查引用链在排队期间存活、清空后释放，末轮像素检查复制、裁剪及预乘 alpha。此文件本次未修改或重跑 |
| `tests/godot/vfx_demo.gd` | 原始 hover 采样仅由 HOVER_SAMPLE 开关启用，每两帧读回；默认路径没有该读回成本。它是鼠标附近亮度诊断，不是自动悬停像素门禁，也不代表物理屏幕扫描结果。现有退出检查覆盖窗口排空及宿主资源归零 |

源码 `JavaFXRenderSurface::release()` 已清空 mesh_cache，但旧退出断言仅检查不含
该缓存的 owned-resource 计数，因而不足以证明此项释放；本次只强化测试，没有改动渲染实现。
mobile 下 `test-m1.ps1`、`test-shaders.ps1` 重新通过，后者解析 262 份生成源码，
已有颜色、UV、alpha 和材质版本像素门禁保持不变。完整日志
`artifacts/logs/review-cache-exit-surface-full.log`、
`artifacts/logs/review-cache-exit-shaders-full.log`。这些有界用例不证明全部场景无泄漏。

## 切页基准清理与统计复核（2026-11-10）

2026-11-11 最终复核另发现切页仍对 `max_draw_sync_us` 相减，现与表格统一输出
`lifetime_max_*`；两者的 GPU 瞬时值输出为 `last_*`。普通切页 59.184/56.353
FPS、无失焦且清理通过，日志 `review-transition-max-counter-full.log`。额外诊断
运行验证切页和表格空闲/拖动三份报告字段语义，见 `review-transition-gauges-full.log`
和 `review-table-gauges-full.log`。FPS 公式、动画负载、生产路径均未改变。

原始路径 `tests/reference/VfxTransitionProbe.java`、`tests/godot/vfx_transition.gd`、
`tests/godot/vfx_transition.tscn`、`scripts/benchmark-vfx-transitions.ps1`：
逐页 FPS 使用样本数除以间隔总时长；总体 FPS 合并全部间隔计算，不取逐页 FPS
的算术平均。宿主 START/END 的计时区间包含切页间调度，因此它与 Java 动画采样
区间不同；二者都不是物理显示扫描帧率。场景文件引用对应宿主脚本。

本次修复 TaskManager 终止异常会跳过 GlobalScreenUtils 注销的清理顺序，改为
独立 finally。宿主移除后增加 owned-resource 归零门禁，包装器要求对应标记并
提前创建日志目录。未改变页面顺序、动画、采样或 FPS 算法；未注入 TaskManager 异常。

当前源码重新编译并完成 68 次切页，mobile/safe、Godot Editor/Glass-Godot/Prism-Godot；
本次 RD_DIRECT 与 LCD_SCREEN 环境变量均未设置，RD batch 计数为 0，是 Viewport 路径。
58.464 pulse FPS，宿主 1615 次合成 / 28.949884 秒 = 55.786 次/秒，失焦 0；
p50 16.610 ms、p95 21.542 ms、p99 51.941 ms、max 144.557 ms。
最慢切页 L17 表格页为 36.603 pulse FPS，不能把整体均值写成每页稳定 60。
双侧 PASS 及 `VFX_TRANSITION_RESOURCE_CLEANUP_PASS` 通过。
日志 `artifacts/logs/review-transition-cleanup-full.log`，包装器输出
`artifacts/logs/review-transition-cleanup.log`。不与前述显式 RD 配置直接比较或归因性能变化。

## 着色器改写、转换及退出路径对应（2026-11-10）

2026-11-11 已完成下表五个原始路径的当前源码最终复核，记录在
`artifacts/review-root-final-audit.json`。完整读取改写器、转换器、两个头文件及
模块注册/卸载实现，并追踪 Target/RD 的编译和失败释放调用；没有新增修改项。
记录固定源码哈希及既有 LRU、262 项 corpus、LCD 和 shader-cache 证据；根仓库
剩余路径仍显式列在 pending 列表，不能把这五项当成完整原生渲染审查完成。

本节补齐原始路径与当前源码检查的对应，不把缓存单元测试扩大为 GPU 验收。

| 原始路径（相对 `native/godot_modules/javafx/`） | 当前检查结果 |
| --- | --- |
| `javafx_shader_rewrite.cpp`、`javafx_shader_rewrite.h` | 仅改写识别到的值类型 uniform，超过 16 个实例槽回退到原源码；名称缓存以完整源码为键，限制 256 条/4 MiB 载荷，返回持有 COW 所有权的列表，淘汰不会使调用者的列表悬空。超限源码仍可使用但不缓存 |
| `javafx_shader_translate.cpp`、`javafx_shader_translate.h` | 核对 float/int 及 2–4 分量向量、数组长度 1–1024 的 std140 偏移与步长，单元素数组保留数组身份；默认值由 Godot 解析器求值，按 4 字节复制入缓冲；不支持的 uniform 类型及重复屏幕采样器返回错误。此转换器面向项目生成的 shader 方言，不是任意 Godot Shader 的完整编译器 |
| `register_types.cpp` | 仅在 SCENE 层卸载时执行共享资源清理；先释放 pass，再释放共享流水线和采样器，最后清空实例名称缓存，避免在 CORE 层渲染器拆除后再次清理 |

关联调用链也已核对：`javafx_render_target.cpp` 以原始源码缓存 shader RID，
超出 64 项的 shader 归当前 pass 管理；`javafx_rd_pass.cpp` 对哈希候选再比较完整源码，
流水线创建失败时将尚未入缓存的 shader 交给渲染线程释放。已有记录中的
队列持有资源与淘汰验证仍适用；这里没有声称实际注入 GPU 分配失败。

本次重新编译并运行 `test-bounded-lru.cmd`：`BOUNDED_LRU_PASS`，日志
`artifacts/logs/review-shader-cache-lru.log`。测试覆盖碰撞、访问顺序、字节/条目预算、
替换、超限拒绝、索引分配失败回滚和接近 SIZE_MAX 的计数，未操作窗口或键鼠。
同时重新读取已有 `rd-regressions-safe-runtime.log`：默认值、覆盖值、单元素数组、
ivec3、碰撞源码及流水线淘汰像素门禁通过；这是已有 GPU 运行记录，本次没有重新运行。
本节未发现需要新增代码修改的问题，通用 Shader 语法、全部驱动及失败场景不在这些证据的证明范围。

## 2026-11-10 文档入口核对

原始变更中的 18 个脚本文件都能在 TESTS.md 找到文件名引用；其中 17 个 PowerShell
脚本通过当前解析器语法检查。此检查不证明参数、环境依赖或运行结果正确，也没有
运行物理输入脚本。审计时 HoverDemo 尚无包装脚本；现已新增
`test-hover-demo.ps1`，编译/解析通过；当时获授权的真实运行结果见上节。
该授权已撤回，不能据此再次运行 Robot。


本轮另外逐一核对了原始变更中的 19 个 `.tscn` 单脚本场景声明，引用文件均存在。
Stage 测试已修复整数缩放截断，当前 2× 的 mobile/GL 验证通过；实际分数 DPI
仍未验证，不因数值计算修正而宣称整个跨显示器/缩放链路已验收。


早期 rd_direct_spike / rd_translate_spike 的无设备假通过已修正；mobile/separate
正常路径和 GL 预期拒绝均动态验证。rd_spike 本身只打印 offscreen 成本，没有
功能 PASS 门禁，不能把其退出 0 当成生产渲染正确性证明。


TESTS.md 参数表进一步使用 PowerShell AST 核对：93 个脚本条目、231 个列出的
可选参数均存在于对应脚本的参数声明。此结果只证明参数名可用，不证明所有参数
组合、运行前置条件、像素结果或物理设备行为均已验证。读取出的参数清单位于
`artifacts/script-parameters.json`，是审计辅助数据，不是测试 PASS 清单。


## 外部拖放 helper 边界审查记录

四类 COM 对象 Release 的释放后访问已由 ASan 复现并修复，4000 次生命周期
检查通过。枚举器 Next/Skip/Clone 契约与 Clone/EnumFormatEtc 分配失败现已修复
并通过 ASan 组件测试。外部 UTF-16/UTF-8 文本已加尺寸/终止符检查，Drop 的
介质和锁用 RAII 释放，异常转换及释放顺序通过故障注入。`dnd_helper.cpp` 的启动资源已统一清理，窗口回调分配异常已捕获；
101 次注册失败、OLE 配对、GDI 计数、日志关闭和回调分配失败注入通过 ASan。
真实窗口退出、DoDragDrop 和 GetMessage 错误仍未动态验证。拖放效果掩码/接受状态已修复并通过
ASan 组件测试。GetData 已与
QueryGetData 共用格式校验、清空失败输出并转换分配异常；组件故障注入通过。
这些可继续做非交互组件验证，真实鼠标许可不阻塞该部分工作。

helper 文件列表已改为有界读取，首项不再截断到 MAX_PATH；长路径、未对齐 UTF-16、
ANSI 多文件、空列表、非法边界与分配失败通过 ASan 组件测试。后续继续核对其他
COM 输出契约，并完成原始变更逐项审查；这些组件结果不替代跨进程拖放验收。

生产 DataObject 与 helper 的 GetCanonicalFormatEtc 未完整初始化输出问题已同时
修复；不支持订阅时清空输出。两个对象通过共享输出契约测试，helper 同时通过
ASan。此结果不替代真实外部拖放；后续仍需完成原始变更逐项核对。

## 缩放光标测试复核（2026-11-10）

ResizeCursorProbe 的场景为 400×300 逻辑坐标。宿主测试原用窗口物理尺寸减去
固定 8 像素计算圆心，已改为逻辑圆心及每次偏移分别按窗口比例换算。包装脚本
补齐输出目录创建。mobile/separate 和 GL/safe 合成输入两侧 PASS、资源归零
通过；未移动真实鼠标，未切换显示器 DPI。随后 Runtime 变体亦通过，见
review-scroll-fields-runtime-input.log；不能把早期仅验证 Editor 的记录当作当前缺口。

本次按原始清单明确核对这组四个文件，未发现需要新增改写的问题：

| 原始路径 | 当前源码检查 |
| --- | --- |
| `tests/reference/ResizeCursorProbe.java` | 场景创建、监听器及退出均在 FX 线程；只有收到点击才置完成标记，启动异常与未完成退出不会打印 PASS。本次使用当前 SDK 重新编译通过 |
| `tests/godot/resize_cursor.gd` | 使用 `Input.parse_input_event` 合成事件，无 Robot；40 秒期限覆盖等待，断言进入、连续移动及离开时的光标形状；宿主移除后要求资源归零 |
| `tests/godot/resize_cursor.tscn` | 单一宿主节点引用上述脚本，引用目标存在 |
| `scripts/test-resize-cursor.ps1` | 编译失败即停止，检查进程退出码、Java/Godot 双侧 PASS、进入悬停标记及错误日志；finally 恢复 JDK 环境变量和工作目录。Runtime 使用源码产物及单独项目目录 |

重新读取 `resize_cursor-mobile-separate-runtime.log` 可见 Vulkan/mobile、悬停进入/离开
及两侧 PASS；这是已有运行证据，本次没有重新启动 GUI，也没有据此扩大 DPI 或物理设备验收范围。

ImagePoolReuseProbe 随后发现并修复失效候选锁未归零，验证见下节；手动 hover 脚本是诊断入口，
没有自动功能 PASS，不纳入偶发长帧修复。

## 图像池锁生命周期（2026-11-10）

ImagePool 对候选调用 lock 后发现 isLost 时，原实现只移除引用而未 unlock。
测试旧版 lock/unlock 为空方法，且 LIFO 未必先访问失效项；现记录锁计数并按
遍历方向设置候选顺序。当前 SDK 修复前可复现失败，修复后 FIFO/LIFO 均通过，
checkIn 后再次复用不产生额外分配。Media SDK 源码构建及 mobile/separate
Effect 回归通过；没有注入实际 GPU 设备丢失，也不据此宣称所有场景无泄漏。

## OLE 合成注入测试（2026-11-10）

OleInjectProbe 已修正失败跳过清理、Drop 异常未传回测试主线程的问题；包装脚本
要求 Java 完成标记，宿主成功路径检查资源归零。错误载荷注入发现宿主提前退出
打断 Java 清理，现等待 Java 终态再判失败。mobile/separate 普通与 Timeout
路径通过，错误自定义载荷期望明确退出 1 且无 PASS/清理中断。未覆盖跨进程
OLE 或真实鼠标；仍保留这些路径的许可与验收限制。

## JFX 原始变更逐项证据：基础渲染钩子（2026-11-10）

以下路径相对 `jfx/modules/javafx.graphics/src/main/java/`。此表只记录对应
原始改动及其关联检查，不宣称整个文件的所有历史代码均已验证。

| 路径 | 当前核对结果 | 证据与限制 |
| --- | --- | --- |
| `com/sun/prism/godot/GodotTexturePool.java` | 原始改动将回收目标/硬上限从 64/128 MiB 提到 512/1024 MiB；此前注释误把 64 MiB 称为上限，已更正 | 对照 BaseResourcePool 构造与分配路径、native frame_protocol.h 的 1 GiB 上限；native 另计退役版本，不能认为 Java 通过预检就保证 native 分配成功。没有本轮 1 GiB 分配压力测试 |
| `com/sun/prism/impl/BaseContext.java` | LCD 背景采样钩子默认 false，不改变其他后端默认路径 | 对照 GodotContext 覆盖和 GlyphCache 消费；当前 SDK 的 LCD 重叠回归两模式通过 |
| `com/sun/prism/impl/GlyphCache.java` | 使用屏幕背景采样时不要求 LCDBuffer，保留非屏幕路径尺寸获取 | `review-jfx-core-lcd.log`；不等于所有字体、DPI、GPU 的验证 |
| `com/sun/prism/impl/ps/BaseShaderContext.java` | 默认透明度钩子保留旧值；Godot 的批次透明度变化先 flush 再更新；切换计数含窗口/相机/深度状态，已更正注释 | 源码调用链核对，加上当前 SDK LCD 两模式回归及上一轮 Effect 回归；不将计数解释为离屏 GPU pass 或显示帧率 |

GodotEventLoop 的 HOVER_TAP 时钟读取受静态开关保护；关闭时不采集任务耗时。
这次是源码核对，不是新的性能测量。上述源码改动仅注释，没有改变构建产物行为。

## Glass 原始变更复核（2026-11-10）

- GodotDragClipboard：删除额外静态 instance，current 只从 Glass 共享缓存读取；
  Clipboard.remove 可在最后一个 assistant 关闭时移除条目。临时 assistant 关闭后
  的普通/Timeout OLE 注入通过，但旧版也通过，故没有动态复现错读声明。
- GodotPulseScheduler：源码核对原始 100 ms 饥饿补发上限和关闭路径；当前 SDK 的
  GlassSchedulerProbe 通过线程终止、计时器暂停/恢复、异常传播和嵌套循环等现有门禁。
- GodotView：原生与 Java 解包的默认滚轮行为一致，mobile/separate 合成三格滚动
  120 px 通过。当时发现 native 将 chars 限到 1000、未保留水平特殊值，且
  `(packed_lines + 8) * 1024` 使用 int 算术。这些边界已由下节的滚轮输入 V2
  修复；真实系统分页/极大设置仍未动态验证，不能称所有系统设置兼容。
- GodotWindow：26/27 全局触摸键盘命令路由与此前 HRESULT 修复一致；没有本轮物理键盘验收。
- QuantumClipboard：HTML 没有本地图片时继续扫描 raw image MIME 的逻辑正确；
  本轮未重新操作系统剪贴板，仍遵守共享状态备份保护。

Media SDK 源码构建通过，日志 review-dnd-cache-build.log；复验日志：
review-dnd-cache-after.log、review-dnd-cache-timeout.log、review-glass-scheduler-current.log、
review-glass-scroll-current.log。没有真实鼠标键盘输入或剪贴板改写。

## 滚轮输入 V2 与新发现的 IME 重入（2026-11-10）

滚轮设置已从单字段压缩改成窗口记录第 10/11 字段，记录长度为 12；新的
pollWindowInputV2 JNI 入口要求宿主/SDK 同步构建。完整 UINT32 值按 Win Glass
的 jint 位模式转换，无水平截断或垂直打包溢出。路由不再把记录截成九字段，
并省掉一次数组复制。Editor/Runtime/Media SDK 构建均通过；首次旧 IME chunk
长度编译错误及路由截断失败已修正并复验。

边界解码、mobile/separate 三格滚轮 120 px、Runtime resize-cursor 通过；
IME 的组合/提交/取消与分帧点击通过（`-SpacedClick`）。日志为
review-scroll-fields-codec.log、review-scroll-fields-wheel.log、
review-scroll-fields-runtime-input.log、review-scroll-fields-ime.log。
未修改 Windows 滚轮设置；未动态验证真实分页/极大设置的控件行为或旧 SDK 混用。

**IME 点击事件重入：已修复，结果见下节。** 默认同帧 press/release 注入在完成按钮
处超时；诊断显示点击命中正确按钮，但释放回调先于按下回调（review-ime-event-order.log）。
不能把它当作只有 DPI 的问题。测试已修正 DPI 坐标，但保留默认同帧行为；新增
-SpacedClick 只用于隔离验证，不能替代默认验收。修复要求是定位焦点/IME 同步命令的事件泵，保持 showAndWait 等合法嵌套
循环语义，不能简单禁用所有重入；下节记录此次定位与验证。

## IME 重入修复验证（2026-11-10）

根因是 GodotView._finishInputMethodComposition 等待宿主完成后调用通用
GodotApplication.drainInput，将已排队的鼠标释放分派在当前按下回调内部。
现调用专用 drainImeInput：只提取当前窗口的组合包（13/14）和无物理键码的
Unicode 提交（5/6、key=0），其他输入保持队列顺序。先完成队列筛选，再调用
应用回调，避免迭代器跨重入。没有修改普通调度器或模态事件循环。

Media SDK 构建通过（review-ime-drain-jfx-build.log）。默认、无 SpacedClick
的 IME 在 mobile 和 GL 都通过 PR 顺序、最终文本和宿主完成门禁；mobile/separate
模态及输入取消也通过。日志 review-ime-order-mobile.log、review-ime-order-gl.log、
review-ime-order-modals.log、review-ime-order-cancel.log。之前的失败日志保留。
真实系统 IME、次级窗口物理输入仍不在这次合成输入验证范围；原始全量审查
及尚未执行的物理测试缺口没有因此自动完成。用户后来撤回 Robot 授权，
未执行的物理测试保持未验证，不能用本节历史记录作为运行许可。

## Godot 原始十文件差异复核（2026-11-10）

2026-11-11 完成该组当前源码的逐文件最终复核，固定记录为
`artifacts/review-godot-final-audit.json`：包含原始十文件及关联 GL 头文件的
当前 SHA-256、各自结论，以及已核查日志的 SHA-256 和通过标记。文件内容未变
时不再重复审查这一组；后续相关修改需重新核对对应项。该记录只关闭这组源码
审查，不代表根仓库/JFX 已完成，也不把历史测试伪装为本轮新运行或源码构建溯源。
另外追踪确认 finalize_display 先 finish/delete RenderingServer 再删除 DisplayServer，
因此正常退出时 GL manager 不会先于队列清理被释放。分配失败和全部驱动场景
仍受下方限制约束。

本节对照 `420dfdc1c302dff13a357f178cfb53f6fe97e6ad` 到当前工作树；原始提交
涉及以下十文件。它是源码差异审查记录，不代表所有 Windows/GPU 场景已验收。

| Godot 路径 | 核对结果和当前证据 |
| --- | --- |
| `core/input/input.h` | quiet 光标 setter 仅同步默认形状，不合成额外 motion；宿主同时设置 OS 光标。当前 Runtime resize-cursor 回归已通过（review-scroll-fields-runtime-input.log） |
| `main/main.cpp` | HOVER_TAP 诊断计时受静态开关保护；关闭时不读诊断时钟；未改变 sync/draw 调用顺序。不据此推断 GPU 执行耗时 |
| `platform/windows/display_server_windows.cpp` | OLE 注册成功才发布对象/委托，失败 Release；GL 上下文切换和 vsync 调度到渲染线程。当前合成 OLE 和窗口立即关闭回归通过；系统 RegisterDragDrop 失败未动态注入 |
| `platform/windows/display_server_windows.h` | 委托字段、返回 Error 的安装接口与模块调用端一致；接口不暴露为通用 DisplayServer API |
| `platform/windows/drop_target_windows.cpp` | 先调用可选委托，再回退内置文件拖放；Release 使用 memdelete 调用析构。当前 OLE 注入覆盖宿主委托，不覆盖外部进程/真实拖放 |
| `platform/windows/gl_manager_windows_native.cpp` | 当前修复有窗口表互斥和存在性检查，失败切换不更新 current；立即销毁后的排队操作不重建无效窗口。Editor/Runtime GL separate 各 32 轮立即关闭通过 |
| `servers/rendering/renderer_canvas_cull.cpp` | dirty 更新和资源更新顺序未改；计数/计时受 OFFSCREEN_PROFILE 保护，当前 getter 调用来自渲染路径 |
| `servers/rendering/renderer_canvas_cull.h` | 只增加四个诊断 getter，与实现/调用点一致；不是跨线程统计快照 API |
| `servers/rendering/renderer_rd/storage_rd/utilities.cpp` | 四阶段资源更新保留原顺序；关闭 profile 不采集诊断时间、不打印统计；mesh 字段包含 skeleton，不能只解释成 mesh |
| `servers/rendering/renderer_viewport.cpp` | 离屏绘制顺序和 UPDATE_ONCE 语义未变；时钟与累计日志受 profile 保护；计数是此入口调用次数，不是呈现帧数 |

关联修复文件 `platform/windows/gl_manager_windows_native.h` 的递归互斥和空句柄
初始化也已对照实现。窗口类使用 CS_OWNDC，不能仅凭 window_destroy 没有普通
ReleaseDC 调用就认定 DC 泄漏。没有把当前短循环通过当作所有 GL 驱动生命周期安全的证明。

本轮新日志：review-godot-scope-close-editor.log、review-godot-scope-close-runtime.log、
review-godot-scope-ole.log。未进行新的性能优化、物理输入或系统设置修改。
根仓库其余原始变更与新修复的总体验收仍需继续核对。

## 根仓库原始变更：宿主声明与场景资源边界（2026-11-10）

本节对照根仓库 9ae5a635 与当前工作树，补齐以下原始路径的逐项记录。

| 路径（native/godot_modules/javafx/ 下） | 核对结果与证据 |
| --- | --- |
| javafx_host.h | 新增状态与实现相符：几何表由主线程管理，拖放目标由 unique_ptr 持有；pre_draw 回调有成对连接/解除，CycleState 在宿主析构时兜底释放。诊断统计不是显示帧率；未做宿主析构故障注入 |
| javafx_host_windows.cpp | 次级窗口递归销毁子窗口后，先解除 Windows 拖放委托，再移除 TargetHandler 和窗口；之前 mobile/separate 外部拖放通过，但没有专门注入次级窗口正在外部拖放时被销毁 |
| javafx_scene_view.cpp | 新增 sampler 集合移除位于 SubViewport 删除前；同时核对 surface 的 retain/dispose/clear 路径，不能只看析构中的一个 erase 判断整个生命周期。当前 GodotView mobile/separate Transform 的布局、裁剪、输入和释放门禁通过 |
| javafx_rd_direct.h | CycleState 属于诊断夹具，生产 RD 通道位于 javafx_rd_pass.h；更正将生产通道仍描述为全 Viewport 的过时注释。此前 RD 正常/缺设备验证见上文；本轮只有注释修改，不需重新构建 |

新回归日志 godot-view-mobile-separate-transform.log（含另行运行的原生 D3D 变换
参考 transform-clip-d3d.log）。此为当前测试场景证据，不是所有资源失败路径的证明。
另核对原始 .gitignore 改动仅增加 *.obj，未忽略源码或测试结果判定文件。

## 根仓库原始协议变更：几何事务（2026-11-10）

核对 frame_protocol.h 原始新增的 QUADS/QUADS_REF/GEOMETRY_FREE：解码限制几何
句柄和有限变换/透明度，TextureLedger 对引用绘制仍检查目标反馈和纹理存活，
GeometryLedger 检查注册/引用/释放顺序。FrameQueue 先对两个资源表副本投影，
全部通过并入队后才发布状态及序号；未发现需要改动这一事务实现的问题。

补齐原测试缺少的跨表失败用例：纹理分配和几何注册后遇到非法引用，必须无入队、
不消费序号，原序号完整重试成功；几何释放后遇到非法引用，原几何和纹理仍可引用。
test-protocol.cmd 通过新增 FRAME_RESOURCE_TRANSACTION_PASS 及原 10000 帧并发
检查，日志 review-resource-transaction.log。mobile 缓存压力网格变换回归通过
（mesh-transform-mobile-cache-pressure.log）。后者验证网格消费者，不代替 Java
编码端或所有 GPU 分配失败场景；本轮没有扩大资源上限或放宽断言。

## JFX 原始编码器变更：缓存与失败状态（2026-11-10）

GodotRenderCommands 的几何缓存按内容哈希索引，但命中后仍比较完整数组；缓存
持有独立数组快照，限定 1024 项默认数量及 32 MiB 载荷，近期条目不强制淘汰。
闲置淘汰编码 GEOMETRY_FREE，碰撞或容量不足退回内联几何。submit 对背压保留
同一序号；JNI 异常使编码器进入 failed，宿主停止另记 hostStopped，避免继续使用
可能与宿主不同步的缓存。本轮源码核对未发现需修改上述实现的问题。

扩展 RenderCommandValidationProbe：外线程写入必须拒绝且不污染拥有者；无宿主
JVM 中真实调用 submit 触发 UnsatisfiedLinkError，随后写入/提交必须拒绝，完成
序号不得推进。现有数组快照、强制哈希碰撞、容量、32 MiB 和淘汰检查一起通过，
日志 render-command-validation.log（ENCODER_OWNERSHIP_FAILURE_PASS）。此负向路径
覆盖 Error，不代表实际 JNI 资源拒绝、背压超时或主机停止均已动态注入。
脚本补齐输出目录创建；没有修改运行协议或资源上限。

## 四边形批次容量边界修复（2026-11-10）

GodotGraphics 清屏仍按 164 字节预留，GodotContext 按 40+32×顶点数预留；当前
未带纹理的完整 QUADS 实际为 48+32×顶点数（四边形 176 字节）。临近 4 MiB
批次末尾时，调用方少算容量导致合法绘制抛出 batch limit exceeded。旧 SDK 上
新增测试已复现，日志 review-batch-boundary-before-detail.log。

删除两个调用端的重复预估，由 GodotRenderCommands 对完整绘制、52 字节缓存
引用和16字节淘汰命令分别按实际长度及 65536 命令上限先提交；保留输入验证在
写入前。无协议格式或预算变化。独立 JVM 边界测试验证不足时到达 JNI 提交入口、
恰好容纳时不提交（不冒充真实宿主边界集成测试）。当前 Media SDK 构建成功，
ENCODER_BATCH_BOUNDARY_PASS、mobile/separate Effect、LCD 两模式像素回归通过。
日志 review-batch-boundary-build.log、render-command-validation.log、
effects-mobile-separate.log、lcd-overlap-separate-0.log / -1.log。

## 跨批次 GPU 状态验证（2026-11-10）

为 queued-texture-update 增加可选 -BatchBoundary，使用真实裁剪命令达到 65536
命令上限，下一次 draw 必须推进提交序号；随后 GPU 读回 256 像素检查跨批次
shader/clip 状态及颜色。仅反射读取 count，不篡改它或输送伪造占位字节。
mobile/separate 边界模式及 mobile/safe 默认纹理版本测试通过，宿主移除后资源
计数归零。日志 queued-texture-update-mobile-separate-boundary.log、
queued-texture-update-mobile-safe.log。随后补齐 4 MiB 字节边界：三次合法 1 MiB
纹理上传配合裁剪填充，确认先于命令数上限耗尽字节，再验证自动提交和 GPU 像素。
两种边界均在 mobile/safe 与 separate 通过，日志
queued-texture-update-mobile-safe-boundary.log、queued-texture-update-mobile-separate-boundary.log。
此项覆盖正常资源分配下的两种边界，不代表所有资源分配失败路径。

## JFX Shader 状态与 LCD 接口核对（2026-11-10）

对照 JFX 原始基线，补齐以下改动的调用链记录：

| 文件 | 核对与验证 |
| --- | --- |
| GodotShader.java | 原始新增 LCD 第二遍采样替换；当前代码对无法完整改写的源明确拒绝。Constant 构造/读取复制数组，Snapshot 复制映射，缓存不持有动态参数的可变数组 |
| GodotGraphics.java | LCD 屏幕采样前选择正确目标并开始新采样边界；清屏变换作为参数传递。此前批次长度错误已修复，当前 Effect/LCD 和跨批次像素验证见前节 |
| BaseShaderGraphics.java | 新钩子默认关闭，仅选择屏幕采样的后端跳过旧 LCDBuffer 复制；lcdSampleInvalid 在准备完成后才清除，保留逐节点采样边界 |
| GodotContext.java（关联状态路径） | setTexture 时保存受保护句柄，提交时携带该值；变换复制，透明度变化先 flush。shaderState 对句柄数组再复制，目标/裁剪状态跨普通批次保留 |

另外核对源码适配缓存的实际 variant 调用：CompositeMode 枚举和 Snapshot 中的
不可变 samplerUnits 映射，不以动态常量为缓存值。当前 SDK 的源码缓存测试通过
容量、字符预算及变化常量保留；LCD 加载测试通过两种模式、原始/改写格式的预期
接受和拒绝。日志 review-shader-snapshot-cache.log、review-shader-lcd-load-current.log。
本轮无生产代码修改；源码所有权核对不等于动态注入全部纹理销毁竞态。

## 离屏网格缓存淘汰的生命周期修复（2026-11-10）

核对 prism_mesh.h 的完整内容比较、PackedArray 快照和有界 LRU，再追踪 surface/
target 消费者：普通 surface 已持有绘制引用，但 target 的持久槽仅保存 RID，
缓存淘汰可提前释放尚未绘制的网格。原压力测试只覆盖 surface；扩展为同时在
target 绘制 4097 个不同的屏外网格，旧 Editor 复现 mesh is null、红色区域消失
（review-target-mesh-before.log）。

DrawSlot 现持有 Ref<ArrayMesh>，隐藏并清空命令时释放且清除旧 RID；关闭槽复用
时由本轮 uncached_meshes 持有绘制引用。缓存预算未改变。Editor/Runtime 源码
构建通过；GL、mobile 的扩大后压力用例，以及 GL SLOT_REUSE=0 通过；Runtime
mobile/separate Effect 通过。证据：review-target-mesh-editor-build.log、
review-target-mesh-runtime-build.log、mesh-transform-mobile-cache-pressure.log、
review-target-mesh-no-slots.log、effects-mobile-separate-runtime.log。Bounded LRU
组件检查也通过；没有扩大为所有 GPU 分配失败或无限运行无泄漏证明。

## 离屏槽分配扫描开销（2026-11-10）

draw_prism_mesh_with_instances 每次从零遍历 used 槽，N 次绘制累计约 N(N-1)/2
次判断。现以 next_draw_slot 顺序分配，clear_draws/free_slots 复位；与 draw_index
分开，因为矩形和 copy_target 参与绘制排序但不占网格槽。used/visible 仍用于
轮末清除未使用的命令和网格强引用。未改变槽复用、缓存预算或绘制顺序语义。

Editor/Runtime 构建成功；GL 高槽数缓存压力、100 轮 render-target 复制/引用释放、
GL/separate Effect 回归通过。日志 review-slot-cursor-editor-build.log、
review-slot-cursor-runtime-build.log、mesh-transform-gl_compatibility-cache-pressure.log、
render-targets-gl_compatibility-safe.log、effects-gl_compatibility-separate.log。
复杂度改进由源码循环消除确认，没有新的 FPS 加速幅度声明。

## 复用槽的实例参数残留修复（2026-11-10）

新增 -ViewportState 通过实际 Java 编码、宿主实例参数分流和 Viewport 渲染验证。
旧 Editor 第一轮显式 tint=红色后，第二轮省略参数仍为红色，未恢复默认绿色；
复现日志 review-slot-parameters-before.log。DrawSlot 现记录设置过的参数名，
最初尝试查询默认值并清空不存在的参数；后续输入取消场景发现 NIL 参数错误
及逐帧 RenderingServer 同步警告，故已替换此实现。当前在旧参数被省略或着色器变化时
重建该槽的 canvas item，由 Godot 初始化默认值；同着色器且参数集合不减少时继续复用。
不再查询默认值或传入 NIL，同材质和替换材质两条路径均适用。

Editor/Runtime 构建成功；mobile/safe、separate 的 ViewportState 三阶段（显式
红色、同着色器默认绿色、新着色器默认蓝色）逐像素通过，宿主确认 RD 提交为零
且退出资源归零。separate 原 RD 两种批次边界回归也通过。日志
review-slot-parameters-editor-build.log、review-slot-parameters-runtime-build.log、
queued-texture-update-mobile-safe-viewport-state.log、
queued-texture-update-mobile-separate-viewport-state.log。不是所有参数类型的穷举。

## VSync 回退误覆盖显式 FPS 限制（2026-11-10）

旧实现把 Engine.max_fps=30 造成的 33.33 ms 周期误判为异常，切换成 60 FPS
并关闭 VSync；已由仅保持 JVM 活跃的夹具复现（review-pacing-cap-before.log）。
现采样期间发现非零 max_fps 即终止回退，执行切换前重新确认 VSync 仍开启，
拒绝非有限刷新率。日志和文档不再把低宿主速率直接断言为 FIFO 根因或保证无撕裂。

Editor/Runtime 构建成功，mobile/GL 显式限速保护均通过；日志
review-pacing-cap-editor-build.log、review-pacing-cap-runtime-build.log、
pacing-cap-mobile.log、pacing-cap-gl_compatibility.log。头文件最后仅调整注释。
后续恢复缺失亦已复现：受控 40 ms 主线程延迟触发回退后，Java 结束仍遗留
60 FPS/VSync 关闭（review-pacing-restore-before.log）。现保存实际安装的 FPS，
正常结束、失败通知和 stop_jvm 都调用幂等恢复；只有当前值仍等于宿主设置时
才撤销，应用后来设置的不同值保留。一个进程仅允许一个 JVM 生命周期。

Editor/Runtime 构建通过；mobile cap/restore/override 与 GL restore 均通过，
override 证明 47 FPS 保留，restore 同时检查 Java 结束后及节点移除后状态。
日志 pacing-cap-mobile-cap.log、pacing-cap-mobile-restore.log、
pacing-cap-mobile-override.log、pacing-cap-gl_compatibility-restore.log；构建日志
review-pacing-restore-editor-build.log、review-pacing-restore-runtime-build.log。
比较当前值不能识别外部再次写入相同值；未单独注入运行失败/中途 stop，不能
把共享恢复函数的源码覆盖写成这些路径已逐项动态验证。

## 手动悬停脚本报告复核（2026-11-10）

批次容量修复后补充验证：当前 SDK mobile/safe RD1/LCD1 的 68 次 VFX 切换通过，
1625 pulse、失焦 0，平均 59.125 pulse FPS / 56.547 宿主合成 FPS；独立复算一致。
日志 review-batch-boundary-vfx-full.log、review-batch-boundary-rates.log。
源码同时核对 host 的 shader/clip/target 状态不因单纯取出下一命令批次而清空，
只在相应状态命令或 pass 操作时变化。VFX 回归不等于强制 4 MiB 边界的像素测试，
该边界的独立编码器检查及随后新增的 GPU 集成结果见上节。

移除固定 60 Hz 的冻结毫秒估算和“恒定亮度即冻结”的表述；连续样本检查不再
跨缺帧拼接，帧编号支持 long，收集结果使用 List。新增 -LogPath 离线入口；
实时非零退出和 ERROR/SCRIPT ERROR/SHADER ERROR/Exception 明确失败。
离线构造日志验证连续段、缺帧、超 32 位编号、错误拒绝及环境/工作目录保持，
日志 review-hover-log-checks.log、review-hover-log-summary.log。脚本解析通过；
本轮未启动人工 Demo，也没有动态注入实时进程非零退出。

## 音频夹具脚本复核（2026-11-10）

test-media-audio.ps1 原来在 -Codec all 中重复编译夹具，并将工具链环境保留到
所有播放结束。现每轮脚本仅编译一次、编译后立即恢复，且先创建输出目录。
验证发现 PowerShell 给 SetEnvironmentVariable 传入保存的 null 会成为空字符串，
已按不存在/有值分别恢复。三格式播放通过；正常与编译器故障注入均检查完整
环境和工作目录恢复，日志 review-audio-fixture-scope.log、review-audio-env-restored.log、
review-audio-failure-env.log。播放仍为静音验证，不证明可听设备输出。

原始音频三文件的源码对应补充如下（本次未发现需要新增修改的问题）：

| 原始路径 | 当前源码检查与证据 |
| --- | --- |
| `tests/reference/MediaAudioProbe.java` | 所有媒体控制在 FX 回调执行；有限时长/时钟和 AudioTrack 校验、暂停时钟不前进、seek 到 1200 ms 后恢复、结束状态均有断言。30 秒观察器超时，stop 中分别尝试停止观察器和 dispose，异常保留且不打印 PASS。当前 SDK 重新编译通过 |
| `tests/native/make_audio_fixture.cpp` | 固定 2 秒/44100 Hz/单声道 16 位样本；MP3 的 COM 接口用 ComPtr 持有，锁定缓冲到解锁之间只有有界 memcpy；AIFF 的 FORM/COMM/SSND 尺寸和大端样本匹配固定载荷，写入及 fclose 错误拒绝 PASS。无可变外部长度参与分配 |
| `scripts/test-media-audio.ps1` | 只使用仓库 Media SDK，检查必需 DLL、编译/夹具/播放器退出码和双侧 PASS；每格式独立进程，工具链环境在编码结束前恢复，外层 finally 再保护异常路径；不以静音成功推断真实设备输出 |

关联 `tests/godot/media_audio.gd` 具有 40 秒期限和宿主移除后的资源归零断言。
本次复读 `media-audio-mobile.log`、`media-audio-mobile-mp3.log`、
`media-audio-mobile-aiff.log`，可见时长分别 2000/2058/2000 ms 和双侧 PASS；
这些是已有播放证据，本次未重新播放。现有源码构建的夹具程序另执行不存在父目录的
AIFF 输出测试，退出 1、报告 open AIFF output 且无生成 PASS；日志
`artifacts/logs/review-audio-fixture-invalid-path.log`。该测试不覆盖磁盘写满或关闭失败注入。

其余同类恢复路径已修正：repro-hover-manual、build-jfx-media、build-windows、
run-vfx-demo、test-lcd-overlap、make-media-fixture、test-drag-drop-external、
test-rd-regressions、test-vfx-soak。提取九个脚本实际清理分支，逐一验证变量不存在、
空字符串和普通值三种初态，27 项通过；PowerShell 解析和 git diff --check 通过。
日志 review-script-env-restoration.log。此项验证仅执行清理分支，不代表九个脚本的
构建或 GUI 主体均已重新运行；运行时架构未改变。

## 按住鼠标状态的取消与槽参数回归（2026-11-10）

2026-11-11 当前源码复核：native window 销毁先递归销毁 owned children，
再移除指向 host TargetHandler 的拖放委托，等待渲染后删除窗口并清除 held_buttons；
失焦通知先清除 held_buttons 和 IME 组合，再投递事件。当前构建的
`test-input-cancel.ps1 -Renderer mobile -RenderThread separate` 通过，覆盖丢失
鼠标/键盘释放、模态切换、触摸取消及恢复后的正常动作，日志
`review-current-input-cancel-full.log`。使用 Godot 合成输入，不操作真实键鼠，
不代表全部真实设备、混合 DPI 或所有系统失焦序列验证完毕。

取消夹具不再在模态窗口出现后替原窗口补发鼠标释放，模拟失焦时释放事件丢失。
旧实现留下 held_buttons 状态并产生意外拖动，复现日志 review-held-buttons-before.log。
宿主现于失焦及原生窗口销毁时删除对应状态；最后一个按钮释放也删除空条目，
移动及进出窗口只查询映射，不为无按键窗口插入条目。Java 观察器额外检查
焦点返回后的移动不能携带旧主按钮位。此验证采用合成事件，不等于系统吞事件实测。

回归同时暴露此前槽默认值修复中的 NIL 参数错误和 RenderingServer 同步警告。
已改为旧参数省略或 shader 变化时重建 canvas item，让 Godot 初始化默认值；
同 shader、参数不减少时仍复用。像素用例增加删除 uniform 后的固定白色，
与显式红色、默认绿色、换 shader 默认蓝色一起逐像素验证。
Editor/Runtime 构建通过（review-slot-reset-editor-build.log、
review-slot-reset-runtime-build.log）；mobile safe/separate 的 ViewportState 及
mobile/separate、GL/safe 的 input-cancel 通过，输出无 ERROR。
本轮未重新测量 VFX FPS，不把消除同步查询直接换算为帧率提升。

正常拖动回归：mobile/separate 合成与已获授权的真实 Robot 模式均通过，
日志 physical_drag-mobile-separate.log、physical_drag-mobile-separate-robot.log。
证明此次清理未破坏所测按下—越界移动—释放连续性；仍限当前显示/DPI 环境。
根仓库及 JFX/Godot 的 git diff --check 通过，交付清单已刷新；整个审查目标仍未完成。

## 原始子模块变更及窗口拖动脚本复核（2026-11-10）

本轮以原始基准到当前工作树的完整 diff 核对以下文件，未增加运行时修改：

| 路径（相对子模块） | 核对结果与证据范围 |
| --- | --- |
| Godot `core/input/input.h` | quiet 光标 setter 只更新默认值，不合成鼠标移动；实际调用端已有移动/缩放光标回归记录。 |
| Godot `main/main.cpp` | HOVER_TAP 开关关闭时不取计时时钟；打开时只记录 sync/draw 耗时，不更改主循环决策。 |
| Godot `servers/rendering/renderer_canvas_cull.cpp/.h` | 计数在渲染更新路径累加，读取来自同一渲染路径的 offscreen 诊断；未引入主线程无同步读取。 |
| Godot `servers/rendering/renderer_rd/storage_rd/utilities.cpp` | 诊断计时保留原资源更新顺序；profile 关闭时不读取时钟。 |
| Godot `servers/rendering/renderer_viewport.cpp` | offscreen 计时未改变更新条件及 UPDATE_ONCE 复位；计数不作为显示帧率。 |
| JFX `GodotEventLoop.java` | 新增诊断保留任务异常传播和停止分支；日志仅在开关启用时执行。 |
| JFX `GodotPulseScheduler.java` | 无宿主 tick 时至多补发三次，queued 标志合并回调；停止测试重新运行 50 次通过（pulse-stop.log），不代表饥饿/恢复全部时序穷举。 |
| JFX `GodotTexturePool.java` | 512 MiB 回收目标/1 GiB 最大值与 BaseResourcePool 参数语义、原生账本约束一致；不是直接预分配 1 GiB。 |
| JFX `BaseContext.java`、`GlyphCache.java` | lcdScreenSample 默认 false，Godot 特例跳过不存在的 LCD 目标尺寸读取；其他后端保持原路径。LCD 像素证据见已有专节，本轮未重跑。 |

WindowDragProbe / window_drag.gd / test-window-drag.ps1 已核对：窗口位置由
屏幕绝对坐标差驱动，夹具使用物理像素，最终位置及资源清理有断言。脚本补齐
输出目录创建。原脚本的直接 $env:赋值本就能正确恢复不存在的变量；此前为此增加的
删除分支属过度修改，现已撤回（见下节 PowerShell 行为复核）。
mobile/separate 平均 2.1333 帧、最大 3 帧，GL/safe 平均/最大 2 帧，双侧 PASS；
日志 window_drag-mobile-separate.log、window_drag-gl_compatibility-safe.log。
同进程确认 mobile 调用后 JDK 环境变量仍不存在（WINDOW_DRAG_ENV_RESTORE_PASS）。
包装验证命令曾因末尾再次删除不存在的变量返回 1；拖动脚本及环境断言均通过，
不将该包装退出码宣称为 0。后续 GL 命令退出 0。未操作真实键鼠。
TESTS.md 明确滞后数据为测量值，实际门禁是每步 40 帧上限及最终位置误差。

## 表格滚动探针退出清理与验证限制（2026-11-10）

VfxTableScrollProbe 现在保留 AnimationTimer/Robot 状态，在失败或 Application.stop
时停止计时器、尝试释放主按钮并恢复原光标位置。采样器、TaskManager 与全局输入
注销分别尝试，错误保留并使测试失败；不再因前一项异常跳过后一项。
脚本补齐输出目录；JDK/profile 环境仍使用原本即可正确处理 null 的直接 $env:赋值恢复。

mobile/separate direct 通过（review-table-cleanup-direct.log），96 脉冲约 45.023 FPS、
位移 2325 px；mobile/safe real 合成模式通过（review-table-cleanup-real.log），
96 脉冲约 55.153 FPS、位移 2325 px。两者驱动方式不同，不作线程模式的性能对照。
本轮实际 Robot 运行受到用户操作电脑干扰，零位移失败不作为实现缺陷证据，
其约 59.384 FPS 也不能作为滚动性能验收；原日志 review-table-robot-no-motion.log。
用户随后明确停止 Robot 测试，旧持续授权失效，不再启动真实输入。
清理异常路径未独立故障注入，不能宣称所有恢复路径已动态验证。

当时发现水平模式跳过位移断言且 direct/real 固定纵向；已由下节修复并用非物理模式验证。性能仍需区分短样本、
驱动方式与实际工作负载，不能用本轮受干扰 Robot 结果覆盖真实滚动结果。

## 表格水平模式覆盖修复（2026-11-10）

水平模式原先只改变 Robot 坐标且跳过位移断言；direct/real 仍驱动纵向，可能输出
与选择轴不一致的 PASS。现水平选择内容宽于视口的最深 DragHandler，direct 的
屏幕坐标由局部点转换而来，real 夹具沿配置轴合成输入。两轴都只累计所选轴的
位移并要求至少 200 px，使用 double 避免逐次截断；日志明确输出 VFX_TABLE_AXIS。
没有修改 VFX 业务代码，没有运行 Robot。

mobile/safe Viewport 路径（RD 未设置）的水平 direct/real 均通过，累计位移各
1500 px；垂直 direct 回归通过、2325 px。完整日志 review-table-horizontal-direct-full.log、
review-table-horizontal-real-full.log、review-table-vertical-direct-full.log。
各自 96 脉冲平均 44.020、42.645、56.916 FPS，不能互相替代或声称都接近 60。

显式 RD_DIRECT=1 / LCD_SCREEN=1 的同一水平 direct 负载亦通过，1500 px、
rd_batch_commits=2644、失焦 0，平均 51.819 FPS、p50 16.933 ms、p95 36.334 ms、
最大 59.333 ms（review-table-horizontal-rd-full.log）。这是约两秒短样本，
不能用接近 60 Hz 的中位数替代平均值，也不据单次对照宣称确定的优化幅度。
用户暂不修复偶发长帧；完整目标的性能结论仍需结合稳定负载证据。

## 持续表格负载与状态参数分流（2026-11-10）

新增 -Sweeps 3..30，默认行为仍为 96 脉冲，Java/合成输入端共用段数。
无诊断的 RD 水平 direct/mobile/safe 960 脉冲平均 50.978 FPS，后 864 脉冲
按舍入日志复算约 50.870 FPS，不能归结为最初启动开销；功能位移与清理通过。
证据 review-table-horizontal-long.log、review-table-horizontal-long-analysis.json。
20 ms 栈采样和命令诊断将较多宿主成本定位到 geometry/shader 状态处理；
原生等待的 Java RUNNABLE 标签不表示 CPU 忙碌，诊断运行不作为帧率验收。

SHADER_STATE 原先逐条构造临时 HashSet，再复制全部 Dictionary 键后分流实例
参数。现直接遍历已缓存的实例参数名，用 String 键查询现有字典，复制 Variant
后再删除条目，避免集合/键数组分配；省略参数与 sampler 留存语义保持一致。
不修改 Java/C++ 协议、不增加长期缓存，不声称消除了全部分配。
Editor/Runtime 构建通过（review-instance-lookup-{editor,runtime}-build.log）；
mobile/separate ViewportState 四阶段像素与 RD Runtime Effect 对照通过，
日志 queued-texture-update-mobile-separate-viewport-state.log、effects-mobile-separate-runtime.log。

关闭诊断后的修复版同配置长测通过：960 脉冲、15000 px、失焦 0、23069 次 RD
批次提交，平均 53.707 FPS，p50 16.803 ms、p95 33.556 ms、max 56.192 ms；
日志 review-table-instance-lookup-long-full.log。旧样本为 50.978 FPS，但 VFX 数据
随机且没有重复交错对照，因此只报告结果，不断言差值全部来自此次修改。
该重负载仍低于稳定 60，不能用其接近 16.7 ms 的中位数替代平均值。

## 标量/向量常量解码的临时分配（2026-11-10）

SHADER_STATE 原来对每个常量都创建 PackedInt32Array/PackedFloat32Array，再从中
取出 1–4 个值构造 Variant；普通标量/向量并不需要该临时堆数组。现只为真正的
array_count 参数保留 PackedArray，标量/向量用四个元素的栈上缓冲区按位复制。
协议格式及值的类型不变；复制边界依赖 decode_frame 的 1..4 分量及精确词数校验，
所有消费者数据来自校验后的帧，不用指针别名转换浮点位模式。

协议回归明确检查 components=0、5、UINT32_MAX 在 shape 校验处拒绝，完整协议
测试通过（含 10000 并发帧），日志 review-scalar-constants-protocol.log。
ViewportState 增加实际 Java 编码→宿主转换→shader 执行→读回的八类检查：
float/int 各 1–4 分量，包含负整数、负小数及多分量值，逐像素要求白色。
mobile/separate 通过 SHADER_CONSTANT_TYPES_PASS cases=8 及原四阶段状态测试，
日志 queued-texture-update-mobile-separate-viewport-state.log。
Editor/Runtime 构建日志 review-scalar-constants-{editor,runtime}-build.log。
此次减少分配由源码路径确认，不把它直接换算成 FPS 提升。

显式 RD_DIRECT=1 的 mobile/separate Runtime Effect 像素对照亦通过，日志
effects-mobile-separate-runtime.log；该回归覆盖实际效果参数，未穷举全部数组长度。

## RD 顶点转换与调用方数组所有权（2026-11-10）

PackedFloat32Array/PackedByteArray 在 Godot 中就是 Vector<float>/Vector<uint8_t>。
原 draw_prism_quads_with_instances 仍分配两份 Vector 并完整 memcpy 后才调用
RD 转换；现直接传只读引用。OffscreenPass::draw_quads 在调用内完成布局转换，
后续记录只持有 RD 资源与已自有的上传数据，不保留调用方数组指针。
布局转换只取一次 ptrw，使用 memcpy 拼接 xy、UV0/UV1 和 RGBA8，消除每顶点
重复 COW 检查，并避免在字节向量上以 float* 写入。未改变协议或顶点布局。
历史 RD_SINKS 的 copy_us 字段保留兼容，但此入口已不再产生该项复制计时。

新增 RD_VERTEX_INPUT_OWNERSHIP_PASS：记录后、提交前将调用方顶点改成 -1000、
颜色清零；逐像素检查原位置、UV0.x、UV1.y、蓝色分量仍正确。夹具使用 RD 支持
的 godot_uv1 约定名称，不据此扩大任意自定义 varying 的支持范围。
Editor/Runtime 构建成功，日志 review-vertex-packing-{editor,runtime}-build.log。
separate Editor 与 safe Runtime 的完整 RD 回归均通过（含该所有权检查），
日志 rd-regressions-separate.log、rd-regressions-safe-runtime.log；Java→宿主两种
容量跨批次像素回归亦通过（queued-texture-update-mobile-separate-boundary.log）。
本轮没有新的帧率测量；不能把减少复制直接声明为达到 60 FPS。

另核对原始 BaseShaderContext/BaseShaderGraphics 改动：opacity 由 GodotContext
变化前 flush 后以 draw 参数携带，默认父类行为保持；LCD 特例在节点边界调用
prepareLCDScreenSample，其他管线保留 LCDBuffer 路径。SceneTextureProbe 的新
绘制签名显式传入单位变换及 alpha=1；surface/shader/render_target/shader_cache
夹具将缓存引用计数与临时资源计数分开，未删除原像素门禁。该源码核对不代替
所有诊断开关组合的动态验收。

## 环境恢复行为纠错及系统接口差异核对（2026-11-10）

当前 PowerShell 中直接 `$env:NAME=$null` 会删除变量；此前将此行为与
`[Environment]::SetEnvironmentVariable(NAME,$null,'Process')` 混淆，错误地把
window-drag/table-scroll 的直接赋值也描述为缺陷。本轮撤回该结论及冗余删除分支。
三个初态（不存在、空字符串、有值）均验证直接赋值正确；API 的 null 仍复现为
存在的空字符串，故此前九个 API 调用位置的修复继续保留。证据
review-env-assignment-vs-api.log。不把正确的原代码写成被修复的 bug。

本轮核对以下原始差异：
- javafx_window_surface.cpp：RD_DEBUG 关闭时不额外读取计时器，composition 的
  draw/sync 仍执行，finish_present 在其后释放来源；诊断不改变屏障顺序。
- windows_custom_format.h：格式名长度/前缀/小写后缀校验与注册返回值明确，
  常量限制为 32 格式、单载荷 16 MiB；这不是所有系统剪贴板格式的通用编码。
- windows_tabtip.h、GodotWindow._requestInput/_releaseInput：主/次窗口均路由全局
  OS 命令，成功 COM 对象配对 Release，Toggle/消息失败返回 HRESULT。Toggle
  并非幂等显示，成功调用不等于实际键盘可见；本轮未启动系统触摸键盘。
- Godot drop_target_windows.cpp：委托覆盖 Enter/Over/Leave/Drop，引用计数归零用
  memdelete 配对 Godot 对象分配；实际外部拖放证据沿用先前记录，未运行 Robot。

ScrollWheelProbe/scroll_wheel.gd/test-scroll-wheel.ps1 的三格事件、系统滚轮设置
映射及最终内容位移断言保持。脚本仅增加输出目录初始化；原环境恢复不需要修复。
mobile/separate 合成验证通过：3 格约 120 px，调用后 JDK 变量仍不存在，
SCROLL_ENV_RESTORE_PASS；日志 scroll_wheel-mobile-separate.log。未移动真实键鼠，
未修改系统滚轮设置，也不将这次默认设置运行替代全部系统设置边界测试。

## RD 脚本公开入口的几何校验缺口（2026-11-10）

Java 帧解码器与 Viewport 网格构造都拒绝非零 Z，但 Godot 脚本直接调用
JavaFXRenderTarget.draw_prism_quads 的 RD 分支曾绕过这些检查。旧 Editor 将
Z=1 的四边形正常画成红色，未报告不支持 3D；复现 review-rd-input-before.log。
同入口还未明确拒绝顶点尾部多余数据、非有限属性及超出 16 位索引容量的批次。

现 RD 公开 packed-array 入口检查 1..65536 顶点、四边形倍数、精确 7-float/4-byte
长度、所有属性有限且 Z=0，检查在资源/管线创建之前。C++ 内部 raw 入口不新增
脚本绑定，Java 已验证的引用几何路径维持原处理；不增加 3D 支持。
新增 test-rd-input-validation.ps1 / rd_input_validation.gd，逐一提交非零 Z、
尾部 float、NaN、65540 顶点和短颜色数组；每次检查透明读回及下一合法 pass
完整红色。包装器只接受按顺序五条指定错误，不能把任意 ERROR 当作预期。

Editor/Runtime 构建通过：review-rd-input-{editor,runtime}-build.log。
safe/separate 五类拒绝与恢复均通过：rd-input-validation-{safe,separate}.log。
separate 完整 RD 回归及 Java 两种容量边界像素回归也通过：rd-regressions-separate.log、
queued-texture-update-mobile-separate-boundary.log。本轮未单独在 Runtime 执行负向
脚本，不把构建成功写成该变体已运行；无物理输入、无新的 FPS 结论。

## 原始范围固定与当前验证快照（2026-11-10）

重新从三个明确 Git 范围提取原始清单：根仓库 127 路径、Godot 10、JFX 19。
artifacts/review-original-scope.json 保存路径、原始首尾提交以及当前文件 SHA-256，
用于防止原始已提交改动从审查范围消失；它只是定位索引，不是逐项通过证明。
后续修复/新增文件仍由 artifacts/change-inventory.json 跟踪，不能互相替代。

最新源码下 RD1/LCD1、mobile/safe、诊断与采样关闭的 68 次 VFX 切页通过，
1627 pulse、失焦 0，平均 57.553 pulse FPS / 54.324900 宿主合成 FPS；由每段
脉冲数/舍入速率加权复算得 57.552547，与摘要一致。日志
review-vfx-after-input-validation-full.log、review-vfx-after-input-validation-rates.json。
不是逐页稳定 60 或物理扫描输出证明，长帧仍按用户指示不单独修复。

文档对照发现 native-module.md 仍遗漏此前 VSync 回退的显式限帧保护与退出恢复，
并将 FIFO 因果说得过满，已按当前源码修正。架构中的顶点所有权/几何输入校验
说明移动到绘制段落，避免混在输入法章节。node-shaders/media-godot 的原始新增
说明与默认参数、音频夹具实现及已有验证范围相符；历史 RD 方案已有醒目的历史
标注。完成条件仍需原始路径到审查/适用验证的对应，索引生成不等于整体完成。

## HoverFlickerProbe 清理复核（2026-11-10）

FX FutureTask 的 10 秒期限、超时/中断取消、异常传播和静态/动画/Fusion 阶段
已经存在，未重复改写。发现可选 Robot 分支未保存/恢复原光标，现由 FX 任务
保存位置，退出时在关闭窗口前尝试恢复，恢复失败仍执行窗口关闭并使探针失败。
没有执行 Robot；动态结论仅覆盖合成模式，不能把编译成功写成真实光标恢复验收。

原宿主在像素通过后直接退出，现先 remove_child(host)，断言 GPU 所有资源计数
为零，再 free，并要求 HOVER_RESOURCE_CLEANUP_PASS。包装器补齐输出目录，
不放宽原有像素/期限门禁。TESTS 修正依赖为 G+J+V，并将 Robot 行为准确写成
悬停而非按下按钮。

mobile/separate 合成模式通过：enters=8、exits=7、输入 flickers=0；普通按钮
1437 hold 帧中 27 帧未找到悬停色，在既有 5% 阈值内；Fusion 稳定 hold 582、
gap 223，其中亮 582、暗 222，六轮及资源清理通过。日志
hover-flicker-mobile-separate.log。逐帧 GPU 读回导致的同步警告属于观察成本，
本测试不是帧率基准。没有新增对所有故障清理路径或物理输入的覆盖声明。

## 虚拟键盘探针的超时与活跃判定（2026-11-10）

VirtualKeyboardProbe 原先在失败/超时时绕过 Platform.exit；成功路径将 close 排队
后立即输出 PASS，不能保证关闭失败会被观察到。宿主活跃循环也只拒绝负 tick，
连续超时返回同一个值仍会通过。现 FX 请求/关闭经有期限 FutureTask 执行，
超时/中断取消未启动任务；统一 finally 尝试释放尚未完成的输入请求、关闭 Stage
并退出 JavaFX，清理异常使探针失败。活跃检查记录起始 tick，要求随后实际前进，
拒绝停止及倒退；PASS 移到清理完成后。宿主夹具移除后补充资源归零断言。

test-virtual-keyboard.ps1 新增 -CompileOnly；此模式编译后直接退出，不创建窗口或
请求 TabTip。当前编译通过，test-tabtip-result.cmd 模拟 COM/消息返回与释放契约
也通过 TABTIP_RESULT_TEST_PASS。没有运行系统键盘流程，没有故障注入 FX 卡住，
因此不把编译或原生模拟结果写成完整 Java→OS 链路/真实可见性通过。
这修正的是原始探针的判定与退出结构，不扩大平台功能支持声明。

## 剪贴板快照辅助代码的内存所有权（2026-11-10）

2026-11-11 当前进展：恢复后的第三次只读检查发现剪贴板已变为可备份的四种
格式，按原有测试授权继续互操作。Java/Godot 双侧通过，但首次恢复因序列号
变化而被保护机制拒绝。只读确认全部已发布测试格式一致、额外格式为合成 DIBV5，
随后使用当前序列号保护恢复初始备份，逐字节校验成功；未覆盖未知外部内容。

独立的有备份/恢复保护实验复现：WriteRaw 在 CloseClipboard 前返回 101，
关闭后实际为 103。原实现过早采样，误把自己的发布收尾当成外部修改。现在在
关闭后重新 OpenClipboard，确认 GetClipboardOwner 仍等于测试窗口，再记录
非零序列号；如果间隙有外部写入则拒绝，最终恢复仍严格检查序列号。PowerShell
包装器同时保证 Invoke 抛错时也报告保留的备份路径。

修复后 Editor mobile 的完整格式交换及原始字节恢复通过，既有无剪贴板访问
guard 检查通过。证据：`review-clipboard-close-sequence.json`、
`review-clipboard-postclose-guard.log`、`review-clipboard-postclose-interop.log`、
`review-clipboard-postclose-editor-full.log`。先前等待准备回复的记录是历史，
本次由实际安全快照和恢复结果验证外部条件已改变。没有放宽外部改写或私有格式保护。

同一修复在 mobile Runtime 也完成交换与精确恢复，日志
`review-clipboard-postclose-runtime.log` 和 `review-clipboard-postclose-runtime-full.log`。

生产 `windows_clipboard.h::custom_formats` 也存在相同的 Win32 结束/失败混淆，
现统一经 `next_format` 检查，失败通过 JNI 明确报错而非返回半份列表；OpenClipboard
的 RAII 关闭路径保持不变。组件 mock 测试覆盖首项/中途失败与成功/结束边界，
原有所有权检查继续通过，日志 `review-native-clipboard-enumeration.log`。
这是原生枚举边界验证，不是完整 JNI 故障注入或共享剪贴板互操作。

2026-11-11 补充修复：`Capture` 原先把 EnumClipboardFormats 返回 0 一律
当作列表结束，可能接受因枚举失败而截断的备份。现在 P/Invoke 保留最后错误，
仅错误码为 0 才接受正常结束，其余错误在任何测试写入之前拒绝快照。
契约依据：[Microsoft EnumClipboardFormats](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumclipboardformats)。
无真实剪贴板访问的委托故障测试覆盖空/完整列表、首项失败、部分列表后失败，
以及 P/Invoke 错误保留属性。既有预算与分配释放检查也通过，日志
`artifacts/logs/review-clipboard-enumeration-guard.log`。未动态制造 Windows 枚举失败，
不把模拟结果当作真实互操作通过；已请求用户在自行保留内容后准备可恢复的普通
文本，收到准备完成回复前不启动共享剪贴板交换。

ClipboardSnapshot.Capture 原来仅对单格式限制 256 MiB，多格式的托管快照总量
没有上限。现总预算仍为 256 MiB，在分配下一块前检查，零长度/加法溢出也拒绝；
WriteRaw/Restore 在任何原生发布操作前检查完整输入。超限拒绝测试写入，不删除
未知私有格式保护，不改变序列号校验，也不自动清空用户剪贴板以绕过限制。

GlobalAlloc 成功后将句柄加入 Dictionary 的异常原来会丢失尚未交接的块；现
TrackBlock 捕获跟踪失败并 GlobalFree，交接成功才由外层 finally 管理。用于
发布的格式键列表也提前创建，避免 EmptyClipboard 后才因分配失败中断。
这不保证 Windows 的多格式 SetClipboardData 是原子事务，OS 发布失败仍须报告。

离线 guard 通过三组标记：格式/owner/序列号、总预算边界，以及 4 KiB HGLOBAL
加抛错字典的跟踪失败释放检查（GlobalSize 确认不再有效）。日志
review-clipboard-snapshot-budget.log。没有调用系统剪贴板读取/写入，没有运行
完整备份恢复或原生发布故障注入；内存辅助测试不替代系统互操作验收。

## Shared-cache follow-up results (2026-11-11)

Editor/Runtime source builds pass. GL and Vulkan pressure fixtures verify a shared
4096-entry budget, peer destruction preserving other users, final-user release
starting a fresh cache, and queued-draw pixels. The old binary fails the new shared
budget assertion. Three-round navigation/cleanup passes with 205 samples and final
zero; no forced GC. Homepage static MiB is 211/226/234 versus 401/566/650 before.
Process private peak drops from about 5.19 to 3.70 GiB; tail-half slope drops from
about 116 to 38 MiB/minute. These are bounded observations, not zero-growth proof.
Targets still grow 196/219/231 and materials 1957/2555/2836; texture memory grows
775/817/836 MiB. Remaining retention needs explanation before memory closeout.
Evidence: review-shared-mesh-after.json and .analysis.json in artifacts/reference.

Current mobile/safe 68-transition rates are Viewport 58.604 pulse / 55.741 host
composition FPS and RD 59.662 / 56.786, both unfocused=0 and cleanup PASS.
The independent rate calculation and current binary hashes are recorded in
artifacts/review-shared-mesh-performance.json. Occasional long frames remain
explicitly deferred. These counters do not measure physical scanout.
