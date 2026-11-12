# RenderingDevice 直连后端：当前状态与历史评估

当前状态（2026-11-11 文档复核）：**生产 RD 路径已实现，处于缺陷修复与重新验收阶段，并非只有 P1 原型。** 默认仍为视口路径，`GODOT_JFX_RD_DIRECT=1` 才启用 RD，GLES3 保持视口回退。

历史记录的 56.96fps/P95 27.6ms 只证明当时的基准结果。原计划的 P95 <25ms 门槛保留为历史记录；用户后续要求 FPS 接近 60 即可，偶发长帧暂不修复，因此不能再把该旧 P95 门槛单独作为当前阻塞项。第一轮审查复现了脚本初始化接口、RD 矩形/复制和 Java 几何缓存的错误，并发现顶点缓冲复用、uniform 默认值和 OLE 超时问题；因此不能沿用下方旧的“全绿”作为当前完整验收。修复和最新测试以 acceptance-status.md 的审查修复节为准。

2026-11-10 更正：下方历史 corpus 的 186 exact / 76 edge 并非已证实的近似精度差。生产像素坐标翻译额外翻转了 Y；修复后 262 个 Shader 全部在 2/255 容差内通过，旧 edge 宽松通过分支已删除。不要继续使用下方“两个近似/边缘精度”的推断解释该历史差异。当前命令为 `scripts/test-rd-corpus.ps1`。

下方保留立项、实验与后续 P1–P5 的历史过程；“尚未批准”“等待决定”“44fps 地板”等均描述对应时间点，已被后续获批的 RD 实现取代。

当前实现与验证入口：

- 生产路径位于 `javafx_rd_pass.*`，由 `JavaFXRenderTarget` 在 RD 开关启用且设备可用时选择；`javafx_rd_direct.*` 是独立诊断探针。探针不能证明未执行的生产回退路径。
- 绘制按顺序批量提交，但呈现、读回、资源回收和顶点环复用等边界可能提前提交；早期“每帧最多一次提交/围栏”是设计意向，不是当前实现保证。
- 共享管线缓存限制为 256 项、16 MiB 源码/翻译文本/默认值数据；已记录的绘制另持资源引用。哈希命中后比较完整内容，不能用换哈希算法代替身份校验。纹理版本、uniform set 依赖与缓存淘汰的修复见 prism-godot.md。
- `test-rd-regressions.ps1` 检查生产路径的绘制、默认参数、环复用、缓存压力、屏幕采样和读回等边界；`test-rd-corpus.ps1` 对全部 262 个生成 Shader 使用 2/255 容差，不再允许 edge/deferred 豁免。两者各有固定输入范围，不代表任意 Shader 或设备故障均已验证。
- RD 原型在缺少 RenderingDevice 时明确失败；旧 GL `PASS rd_unavailable` 只是跳过。生产 OpenGL 回退由 Stage、Effect、窗口等功能测试证明。
- 功能与性能结果必须对应具体构建、开关和日志。最新审查汇总见 acceptance-status.md，性能采样见 frame-benchmark.md；此处的历史“全绿”“零泄漏”只描述当时测试覆盖和观测计数，不证明任意时长、所有资源或最新构建。


2026-11-10 屏幕采样补充：生产翻译器保留 hint 采样器的原始变量名，不再改名为 `dst_color_snap`；旧改名仅覆盖 header 的固定名称，导致 fragment 直接采样或其他变量名编译失败。屏幕快照发生在 pass 内第一次屏幕采样绘制前，包含本轮清空和先前绘制，坐标使用正向 framebuffer Y。下方 P2b-3 的改名、Y 翻转与 pass 前快照描述仅为历史实现。

用户批复与验收约束（2026-11-07）：批准引擎级 RD 直连后端立项，同时四条硬
约束作为验收门：① Godot shader 必须仍可作用于 JavaFX 组件（node-shaders）；
② Godot 组件必须仍可嵌入 JavaFX（GodotView）；③ JavaFX 组件必须仍可嵌入
Godot（宿主本身）；④ 最终在 VFX demo 上验证性能提升。三项能力回归须在 RD
路径开启与关闭两种状态下全绿（GLES3 保留视口路径回退）。

决策历史：五次正式决策询问（四次 AskUserQuestion + 一次收尾确认）均未获
回答，完成判定复核第六次询问后用户于新一轮会话中明确批复选项②。桥接层十
条证据链已闭环并全部提交，作为本立项的归因基础。此前默认收盘记录（翻页
44-45.7fps、拖拽 p95 22.7ms 作为架构地板）由本立项取代。

## P0 spike 结论（2026-11-07，JavaFXHost.benchmark_offscreen_cycle）

本评估的核心经济假设是"每次离屏 pass 的视口渲染周期单价 ~440µs，RD 直连
可将其压向微秒级"。同机实测（效果 pass 分辨率 2016x928，premul 混色，
400 次循环取均值，批量围栏）：

| 画布绘制项 | 单周期成本 |
| --- | --- |
| 0 | 5.9 µs |
| 1 | 6.7 µs |
| 4 | 8.2 µs |
| 16 | 18.3 µs |
| 64 | 37.5 µs |

裸视口渲染周期为 **6-38 µs**，比假设低两个数量级；此前归因引用的
~440µs/次是"渲染 + 逐 pass 全设备同步等待"的墙钟时间（其中同步已由
PASS_SYNC_INTERVAL 批量围栏移除且 fps 不变，本身就是旁证）。因此 RD 直连
重写的可回收上限约为 ~30 µs/pass CPU——**不足以解释或关闭 17-20 fps 的
翻页差距**。剩余差距的真实所在地在视口周期之外（候选：效果 pass 的实际
GPU 工作量、呈现管线、主线程材料/几何常量），需按第六批数据重新立项。

## 按新证据重估（2026-11-07 收盘补充，决策包完成的最后一块）

第八批再归因给出了单 pass 成本的真实分解，据此重估 RD 直连的期望值：

| 单 pass 成本分量 | 当前（视口+画布材质系统） | RD 直连（自管描述符集） |
| --- | --- | --- |
| 编码提交 | ~30µs | ~30µs（保留） |
| 材质/描述符集重建 | ~120µs | ~0（自有描述符缓存，纹理集合身份命中即复用） |
| canvas 脏处理 | ~45µs | ~0（无画布脏队列） |
| 队列/应用其余 | ~120µs | 部分保留（~60µs 量级） |
| **合计** | **~314µs** | **~90µs 量级** |

帧数学：~18 pass/帧 × 节省 ~224µs ≈ 4.0ms/帧；当前 23.2ms 帧（43fps）→ ~19.2ms ≈ **52fps 量级**，继续向 62 靠近需再压缩编码与队列项。

重估结论：P0 spike 证伪的是“视口周期本身”前提（周期 6-38µs）；但第八批证据把真成本定位到周期内部的画布材质系统——这正是 RD 直连会替换的部分。因此在新证据下，RD 直连的期望值从“不值得”修正为“**可能值得，预期 ~52fps 量级，仍为数周级且需完整像素回归体系**”。工作量与风险估算沿用下方原评估的 P1-P5 分解（合计 4-6 周）。

替代路径对比：上游 API 扩展（数组层渲染目标/多纹理逐 item 绑定）同样能消除描述符集重建且改动更小，但周期受上游社区流程支配。三个选项（接受地板/重启 RD 直连/引擎扩展）的完整决策输入至此齐备。

## 原评估（历史保留，前提已被上节修正）本文档基于 2026-11-07 六轮量化优化的完整归因数据链
（docs/prism-godot.md「Historical page-turn gap investigation」起的历史章节），
为"是否启动"提供决策材料。启动需用户批准。

## 为什么需要它（证据链摘要）

同一基准（68 页过渡，VfxTransitionProbe）下原生 D3D 62.0 fps / p95 16.9 ms，
Godot 管线 42-45 fps / p95 55-62 ms，六轮桥接层杠杆（LCD 目标采样、绘制调制
协议+状态抑制、槽位材质跳过+RID 材质缓存、instance uniform 迁移、ImagePool
LIFO 帧亲和、逐 pass 同步流水化）均未改变带宽。已排除项：

1. Java 侧空闲（进程内栈采样：QuantumRenderer ~88% park）。
2. 离屏 pass 数低于原生（27,675 vs 70,428 次目标切换）且低于帧预算。
3. 值常量材质 uniform 重建已消除（实例参数迁移，5.47→4.56 s/37 s）。
4. 采样器 RID 轮换驱动的冷 miss 无法靠 tie-break 消除（尺寸量子逐帧变）。
5. 逐 pass 同步开关不改变带宽（批量围栏为默认，噪声内）。

结论：剩余差距主项 = 每次离屏 pass 的 RenderingServer 视口渲染周期单价
（~440 µs/次 vs D3D SetRenderTarget 的微秒级）。

## 目标形态

把 Prism 效果/裁剪链的离屏 pass 从"每 pass 一次完整视口渲染周期"改为
RenderingDevice 直连：

- 每个 RTT 持有一对 RD 纹理（颜色 + 可选输入附件）与自建 framebuffer。
- pass 编码 = RD render_pass_begin + 逐批次 pipeline/descriptor + draw +
  render_pass_end，全部在宿主进程内组帧，每帧最多一次提交/围栏。
- Java→宿主协议不变（QUADS/SHADER_STATE/END_PASS 语义照旧），只替换宿主
  应用端；窗口呈现层（presentWindow/native composition）保持 RenderingServer
  路径，最终通过一次 RD blit 交还。
- GLES3 兼容路径：gl_compatibility 渲染器无 RD；保留现有视口路径作为回退
  （env 选择），像素回归两路都要绿。

## 工作量分解（预估，数周级）

| 阶段 | 内容 | 估算 |
| --- | --- | --- |
| P1 | RD 纹理/帧缓冲生命周期、与现有纹理账本的对接、单 pass 原型（纯色四边形） | 3-5 天 |
| P2 | Prism 全部 stock 着色器（212 个 loader）翻译为 RD 兼容 SPIR-V 与管线缓存 | 1-1.5 周 |
| P3 | 绘制槽位模型迁移（材质/实例数据→descriptor set）、混合/裁剪/调制语义对齐 | 1 周 |
| P4 | 与窗口呈现层的交接、readback/快照路径、资源退役语义 | 3-5 天 |
| P5 | 像素回归策略（下节）+ 双渲染器全量回归 + 性能验收 | 3-5 天 |

合计约 4-6 周专注工作；最大不确定项在 P2/P3（着色器族语义对齐）。

## 原计划的像素回归策略（历史）

1. 硬门：composite-edges（对源码构建 D3D 逐像素、±2/255 容差）、effects×2、
   render-targets、composite、mesh×2、shader-cache、stage、m1。
2. 新增 RD-vs-视口路径自对照夹具：同命令流双路径渲染同帧，全像素 diff
   （当时拟定容差 0；当前 corpus 门禁为各通道 2/255，见顶部更正）。
3. 快照/读回路径显式覆盖（snapshot、readback 夹具）。
4. 验收基准：transitions ≥55 fps（向 62 收窄）且 p95 <25 ms；table-scroll
   real 模式 p95 向地板 18.4 ms 收敛至 +10% 以内。当时要求未达标不合并；
   这一长帧门槛已由用户后续要求调整，当前以接近 60 FPS 为目标。

## 风险

- GLES3 无 RD：需长期维护双后端，或明示 gl_compatibility 保留旧路径。
- Godot RD 内部 API 无稳定性承诺（引擎升级时需重审）。
- 纹理/内存语义（租借视口纹理、修订版纹理）需重新对接账本校验。
- 工期估算基于桥接层经验，P2 着色器族可能超支。

## P1 原型结果（2026-11-07，已提交）

`native/godot_modules/javafx/javafx_rd_direct.{h,cpp}` + `JavaFXHost.benchmark_rd_cycle/
release_rd_cycle` + `tests/godot/rd_direct_spike.{gd,tscn}`。纯增量探针，不改任何生
产路径；三种运行形态全部通过（mobile+separate、mobile+safe、gl_compatibility 按
设计走 `rd_unavailable` 回退），退出时零 RID 泄漏，纹理生命周期冒烟
（test-texture-lookup mobile）不受影响。

证明的设备路径：RD 纹理（RGBA8，sampling+color attachment+copy from）→ 自建
framebuffer → glslang 编译 SPIR-V → render pipeline → draw_list 渲染纯色四边形 →
`texture_get_data` 回读逐像素校验（容差 ±2/255）→ `texture_rd_initialize` 注册进
纹理账本 → 普通 canvas item 采样上屏（窗口截图与期望色差 ≤1/255，容差 6 内）。

单周期 CPU 成本（draw_list 编码，2016×928，400 次取均值；括号内为 P0 视口路径
同负载对照）：

| 绘制项 | RD 直连 | 视口路径 |
| --- | --- | --- |
| 0 | 0.45 µs | 5.9 µs |
| 1 | 0.29-0.37 µs | 6.7 µs |
| 4 | 0.38 µs | 8.2 µs |
| 16 | 0.52 µs | 18.3 µs |
| 64 | 1.09 µs | 37.5 µs |

语义差异必须记录：RD 数字是纯编码/提交 CPU 成本（主设备命令在帧尾由引擎执行，
无逐 pass 设备围栏）；视口数字含渲染线程上完整视口渲染周期的执行。两者都是
"每 pass 提交侧 CPU 成本"，量级差 ~13-35×，为 P3 替换 draw_offscreen_pass 提供
了成本空间；但生产集成还需逐 pass 依赖（后续 pass 采样本 pass 结果）的 RD 内部
屏障与帧尾一次提交，实际净收益以 P5 性能验收为准。

实施中确认的引擎约束（P2-P5 设计输入）：

1. `draw_list_*`、`texture_get_data`、`free_rid` 等 75 个 RD 方法仅限渲染线程
   （`ERR_RENDER_THREAD_GUARD`）；创建类调用线程安全。宿主侧必须经
   `call_on_render_thread` FIFO 封送（与 draw_offscreen_pass 同模式）。
2. 引擎主设备禁止 `submit()`/`sync()`（仅 `create_local_rendering_device` 的本
   地设备可用）；主设备命令流由帧循环驱动，`texture_get_data` 自带 staging flush。
3. `texture_rd_initialize`（账本桥接）含 RD 纹理校验，也限渲染线程；本原型在
   render job 内完成桥接（与 render target 的代理纹理初始化同模式）。
4. `VertexAttribute.binding` 默认 UINT32_MAX 表示"用属性序号作 binding"，多属性
   单缓冲布局必须显式 `binding = 0`，否则 vertex_array_create 要求逐 binding 的
   源缓冲。

下一步（P2）：把 Prism stock 着色器的 Godot shader 源翻译为 RD 兼容 GLSL 并建管
线缓存；随后 P3 槽位迁移、P4 呈现交接、P5 双渲染器全量像素回归 + 性能验收
（transitions ≥55fps 且 p95 <25ms）。四条用户约束（node-shaders / GodotView /
JavaFX-in-Godot / VFX demo 性能）在此期间每批回归。

## P2a 结果（2026-11-07，已提交）

`javafx_shader_translate.{h,cpp}`：翻译层放宿主侧（协议零改动）。方言清单：
212 个 prism + 50 个 decora gdshader 全部由本 fork 的 JSL 编译器机器生成，
vertex() 体只有三种固定赋值（UV/CUSTOM0.xy/COLOR→varying），fragment() 为单
表达式+可选 discard，松散 uniform 声明，函数体本身已是原始 GLSL。翻译=头部
手术：剥离 shader_type/render_mode/varying/vertex() 块，值 uniform 以 std430
规则并入推常量块（64B 规范头：仿射变换+调制+像素→NDC，上限 128B），采样器
按声明序注入 `layout(set=0,binding=N)`；`COLOR` 引用改经局部变量（out 回读在
原始 GLSL 未定义）。SCREEN_*（154 个 LCD 二段）与 uniform 数组（渐变族
fractions[12]）显式拒绝并归入 P2b。

`JavaFXHost.rd_translate_probe` + `tests/godot/rd_translate_spike.{gd,tscn}`：
同批次（顶点/颜色/纹理/参数逐字节相同）分别走视口路径（JavaFXRenderTarget）
与翻译后 RD 管线（规范顶点着色器+预乘混合+推常量+采样器 uniform set），双回
读逐像素对比。三族首验全绿：Solid_Color / Solid_TextureRGB / AlphaTexture_
Color **max_diff=0、diffs_gt1=0**（512×256×4 全字节相等）——翻译语义与预乘
混合、采样状态、顶点调制在首个族上逐位正确。三形态（mobile separate/safe、
gl_compatibility 回退）通过，零泄漏、零 invalid free；P1 spike 与
FRAME_PROTOCOL 回归不破坏。

双释放教训：uniform set 依赖 shader 布局，先释放 shader 会级联释放 set，再显
式释放即报 invalid ID——退役顺序必须 set → sampler → 其余。

下一步（P2b 剩余）：① 渐变族 UBO 路径（fractions[12]=192B 超 128B 推常量）；
② LCD 二段的目标拷贝语义（SCREEN_UV→采样本 pass 开始前的目标内容副本）；
③ 全 corpus 212+50 逐个自对照（fixture 参数化加载生成文件）后进入 P3 槽位
迁移。

## P2b-1 结果（2026-11-07，全 corpus 自对照通过）

`tests/godot/rd_corpus_spike.{gd,tscn}`：遍历生成的全 corpus（jsl-prism 212 +
jsl-decora 50），每个 gdshader 走 rd_translate_probe 双路径对比。结果
`compared=83 deferred=179 failed=0`（RD_CORPUS_SPIKE_PASS）：

- 83 个着色器翻译后与视口路径逐像素一致（max_diff ≤ 2、diffs_gt4 = 0），含
  全部基础填充族、纹理族、mask 族、多数 Blend/效果族与 SCREEN_UV 透视族
  （154 个透视填充已由 `gl_FragCoord` + 推常量 target_size 改写解锁）。
- 179 个精确归入两个 P2b UBO 类别：uniform 数组 161（渐变 fractions[12]×132、
  卷积 weights[k]×22、kvals[8]×3 等）与值 uniform 总量超 128B 推常量 18
  （DrawPgram/Circle/Ellipse/RoundRect_ImagePattern 透视族）。

本轮修复的两个双路径语义关键点：

1. 推常量块必须匿名（成员全局作用域）：生成代码按松散 uniform 的裸名引用，
  带实例名的块（params.xxx）会全部编译失败（首轮 83 个 fragment_spirv 错误
  的根因）。
2. 宿主默认把值 uniform 改写为逐 item 实例参数（生产路径），探针的视口侧
  必须经 draw_prism_quads_with_instances 传同样的值，否则视口侧落在默认值
  0、RD 侧用播种值，造成 55 个系统性像素分歧。

另：探针对值 uniform 以确定性非零模式播种（材质/实例/推常量三路同值），
避免零默认触发除零 NaN 的位模式不确定。三夹具（rd_direct/rd_translate/
rd_corpus）在 mobile separate 全绿且互不回归。

## P2b-2 结果（2026-11-07，UBO 路径落地，全 corpus 通过）

值 uniform（标量+数组）统一进 std140 uniform buffer（set 0、采样器后一
binding、匿名块裸名访问，std140 数组元素 16B 步进），推常量只留 64/72B 规范
头。全 corpus 自对照（rd_corpus_spike，mobile separate/safe、gl 回退）：
**exact=186 / edge=76 / deferred=0 / failed=0**——全部 262 个 gdshader 编译并
渲染，零拒绝。

本轮排障记录（均为双路径语义关键点，进 P3 设计输入）：

1. **count==1 歧义**：`weights[1]` 是单元素数组而非标量，探针曾误构造
   Vector4 材质参数被 canvas 静默忽略——RdValueUniform 增加 is_array 显式
   区分；canvas 数组通道要求扁平 PackedFloat32Array/PackedInt32Array（与生
   产宿主编码一致）。
2. **FIFO 离屏渲染丢首用材质 uniform**：draw_offscreen_2d 立即渲染时材质路
   径的数组常量读 0（update_dirty_resources、双渲染、120ms 延迟重渲染均无
   效）；生产靠材质跨帧持久掩盖。探针改为两阶段：阶段 A 录制 pass 交引擎帧
   渲染（UPDATE_ONCE），阶段 B 回读+RD 半场+对比。P3 切换生产路径时必须处理
   该首用语义（材质预热或帧内统一渲染时机）。
3. **首帧状态滞后**：阶段 A 后第一帧会漏 RS 队列里的逐 item 状态（实例参
   数），UPDATE_ONCE 存活到第二帧——夹具统一双帧等待。
4. **透视族双近似分歧**：canvas 用插值 varying 的 SCREEN_UV，RD 用精确
   gl_FragCoord（原生 D3D 语义）；经透视数学后可测分歧（陡峭测试纹理上最
   高 ~33% 字节差、中心一致；半像素变体试验未能收敛）。canvas 视口对透视族
   不是真值基准——其像素门归 P5 的 D3D 对照套件（±2/255）；本层只要求编译
   通过、中心一致（±2/通道）、分歧在有界带内（gt4 ≤ 40% 字节）。

线性卷积族（weights[k] 数组）与全部 Blend/效果族现逐位一致；LCD 运行时
SCREEN_TEXTURE 变体（P2b-3）是剩余唯一翻译拒绝项，corpus 基础文件（dstColor
采样器形态）已全部通过。下一步 P3 槽位迁移与 draw_offscreen_pass 替换。

## P2b-3 结果（2026-11-07，LCD 运行时变体通过，P2 完成）

翻译器接受 LCD 运行时替换形态（`SCREEN_TEXTURE : hint_screen_texture` 声明
与裸 `SCREEN_UV` 坐标）：hint 采样器转为普通 `dst_color_snap` 快照采样器
（GLSL 要求先声明后使用），裸 `SCREEN_UV`→归一化片元位置
`vec2(gl_FragCoord.x/target_size.x, 1-gl_FragCoord.y/target_size.y)`，
`SCREEN_PIXEL_SIZE` 同理。`rd_lcd_spike` 夹具以与 GodotShader.loadPrism 相同
的三条替换从 corpus 生成运行时形态并双路径对比：**max_diff=0 逐位一致**。

经验事实（P3 快照实现输入）：canvas hint 屏幕采样把清屏（透明）目标读回为
**不透明黑**（canvas 回buffer 拷贝不带透明度）；探针替身 accordingly 为
(0,0,0,1)。P3 生产实现快照时按 pass 前目标内容做真实快照，但需注意 canvas
的该语义差异——生产 RD 路径的 LCD 将采样真实快照（含 alpha），与 canvas 路
径有可预期的微小差异，以 P5 D3D 基准判定哪个是正确语义。

至此 P2 全部完成：262 corpus + LCD 运行时形态全部可翻译、可编译、双路径
验证。进入 P3。

## P3 阶段成果（2026-11-07，RD 生产路径接入，合成像素缺口待收口）

`javafx_rd_pass.{h,cpp}`（OffscreenPass）：env `GODOT_JFX_RD_DIRECT=1` 时
`JavaFXRenderTarget` 全生命周期委托 RD 直连——纹理/帧缓冲/桥接自建，矩形/纹
理拷贝/四边形批次录制，flush 单渲染线程作业一次 draw_list 提交；四级缓存
（管线按翻译源、顶点缓冲按内容哈希、uniform set 按参数+纹理全等校验+存活
复验、UBO 按常量字节）。QUADS_REF 经宿主新增的原始浮点几何缓存走
draw_prism_raw（RD 不消费 ArrayMesh）。gl_compatibility 自动回退视口路径。

当前验证状态：
- 默认（视口）模式 composite-edges 对 D3D 全绿、corpus 186+76/0/0——回退
  无回归。
- RD 模式端到端运行，**零引擎错误、零泄漏告警**；composite-edges 20 组布
  局中 17 组与 D3D 逐像素一致，ADD/CLEAR/DST_OUT 三组各 36 像素差异待查
  （合成末端在窗口路径采样 RD 目标内容，条纹状差异指向这些布局的目标内容
  生成环节，疑点：blend_disabled 直通/合成尾声着色器在 RD 侧的语义）。
- 本轮实现的引擎语义映射：render_mode blend_disabled/add/mul → RD 混合因
  子；无 fragment 的隐式直通源（clear 族）合成 COLOR=顶点色；blit 源的裸
  UV 令牌改写；VertexFormatID 为 int64（uint32 截断会导致管线创建查表失
  败）；依赖序退役（uniform set→数组→缓冲→管线→着色器→帧缓冲→纹理；
  纹理退役失效回调会销毁引用它的 uniform set，缓存须按存活复验并丢弃死
  项）。

P3 收口清单（下一批）：① 三组合成布局 108 像素差异根因；② copy_target
双线性/边缘语义对照；③ 与性能基准对接（transitions/table-scroll 在 RD 模
式下的 fps 与 p95）；④ P4 呈现交接与 P5 全量回归按原计划。

## P3 收口第一批（2026-11-07，108→72 像素差异，CLEAR 修复）

诊断链（作业内读回 vs Java 读回对拍，GODOT_JFX_RD_DEBUG 门控打印保留）：
渲染作业内目标内容正确、SRC 布局逐字节一致——锁定两处非渲染层根因并修复：

1. **读回链断裂**：texture_2d_get 对 bridge（texture_rd_initialize 的 shared
   view）blit 读回不等价——RD 模式读回改经 OffscreenPass::readback（渲染线
   程直接 texture_get_data 原纹理→Image），宿主 apply_readback 分支调用。
2. **QUADS_REF mesh 通道丢失**：引用几何的 raw 对缺失时 draw_prism_mesh 走
   视口槽位路径，RD 目标无 canvas 即无声丢弃——draw_prism_mesh 增加 RD 分支
   从 ArrayMesh surface 反解顶点（position/uv/custom0.xy/color→7float+RGBA8）
   兜底，任何 QUADS_REF 都可画。
3. 顶点数组缓存键修复：RID id 为 64 位，`id<<32^count` 静默别名不同缓冲。

当前：默认模式 composite-edges 对 D3D 全绿（无回归）；RD 模式 20 布局中
18 组逐像素一致，**ADD/DST_OUT 各 36 像素待查**。已锁定线索：两布局差异
均与"尾声数学的输入色"吻合——ADD 实际 R=180=255×√0.5（尾声 rgb 侧像拿到
非预乘色 (1,0,0) 而期望预乘 (0.5,0,0)）；DST_OUT 出现纯白像素（值与内部
TEXTURED 源的白色顶点吻合）。下批从 Java 端 ADD/DST_OUT fillRect 的顶点色
编码（premul 与否）与 copy_target 调用点（白顶点来源）入手。

## P3 收口第二批（2026-11-07，composite-edges RD 模式 20/20 全绿）

ADD/DST_OUT 根因：acquire_pipeline 的 blend switch 之后残留四行硬编码
premul 因子赋值（早期脚本修复重复执行的产物），无条件覆盖 add/mul 因子。
数值验证吻合：ADD 实际 =(√a,0,1-√a) 与 DST_OUT 实际 =(0.5,0.5,1) 都是
premul 混合的精确输出。删除覆盖后 blend_disabled/add/mul 因子表生效。

GODOT_JFX_RD_DIRECT=1 下 composite-edges 对 D3D 基准 20/20 布局逐像素一
致；默认模式全绿、corpus 186+76/0/0、LCD max_diff=0 回归无破坏。教训落
档：批量脚本修复重复执行会产生覆盖性残留，语义修复后必须读回目标区段确
认只有一份赋值。

## P3 收口第四批（2026-11-07，LCD 文字消失回归修复）

用户实测报告 RD 模式下 VFX demo 文字全部消失。根因（两处）：
1. flush 的目标快照条件要求 initialized_contents——每目标首个 pass（恰是
   文字首页）从不快照，LCD 二段采样到未初始化纹理。修复：pass 含屏幕
   采样 draw 即无条件先快照。
2. 快照纹理是 RD 设备纹理，uniform 构建却把它当账本纹理再做一次
   texture_get_rd_texture 转换——绑定无效纹理。修复：屏幕采样分支直接
   使用设备 RID。

修复后 VFX demo RD 模式正常启动、文字可见（用户确认），smoke 通过、零
引擎错误。交互模式停在首页等待输入为设计行为。

## P3 收口第五批（2026-11-07，性能基线测得，性能差距待归因）

transitions 基准（mobile/safe，68 次翻页）三方对拍：
- 视口路径基线：pulse_fps=44.5，p50=17.3ms，p95=59.9ms。
- RD 直连：pulse_fps=31.2-31.7，p50=23.6-24.8ms，p95=77-78ms。
- 原生 D3D 对照（历史）：62fps / p95 16.9ms。

已排除：flush 逐 pass rs->sync()（去除后无变化，已按视口路径的批量围栏
语义对齐移除——读回自带同步、FIFO 保序）。HOST 计数显示 presentation_fps
=28.8 是当前节拍瓶颈（1105 次呈现/38.4s），encode_us 口径含 Java 等待宿
主 tick 的重叠计时不可直接比较。下一批归因方向：窗口合成对 bridge 纹理
（texture_rd_create 外部纹理）的每帧依赖处理成本、渲染线程 draw_list 提
交节奏与呈现路径的交互。

已知问题：RD 模式 render-thread separate 下崩溃（访问违例 + uniform set
失效后的 invalid free），safe 模式稳定；separate 支持列为 P4 范畴。

## P3 收口第六批（2026-11-07，性能差距归因：环境噪声纠正后真实差 ~10%）

同会话串行对拍（mobile/safe，均前台、vsync 回退两模式均未触发）：
- 视口路径：pulse_fps=35.6，p50=22.3ms，p95=70.0ms（encode 32.5s/36.1s，
  presentation_fps 32.7，host_ticks 1331）。
- RD 直连：pulse_fps=32.1，p50=24.0ms，p95=79.8ms（encode 35.3s/38.4s，
  presentation_fps 28.8，host_ticks 1255）。

关键纠正：此前 44.5fps 视口样本为有利环境下的离群值；同会话下两模式的
HOST 计数结构几乎相同（encode 占比均 ~90%，jni_tick_wait 均为重叠计时），
真实差距 fps -10% / p95 +14%，即每帧约 2.6ms。

归因：1105 次呈现对应 16448 个离屏 pass ≈ 15 pass/帧；每帧 2.6ms 差与
"每 pass 完整渲染通道提交（draw_list_begin/end + framebuffer 布局屏障）"
的量级吻合（纯编码成本 P1 已证 0.3-1µs，非瓶颈）。逐 pass sync 已在前批
排除。收窄方向（后续批次）：同帧多 pass 合并为单次渲染线程批量提交/围栏
（对应立项文档"每帧最多一次提交"的目标形态），以及 uniform set 在纹理
RID 轮换下的创建成本复核。

## P3 性能收窄批（2026-11-07，table-scroll 基准与成本尺寸相关性）

table-scroll（96 脉冲拖拽，mobile/safe）：
- 视口基线：fps=59.9，p95=18.0ms。
- RD 直连：fps=25-28，p95=114-127ms（拖拽期长帧为主症状）。

修正上批归因：RD flush 宿主侧总耗时在 transitions 仅 0.126s/38.4s（
7.7µs/pass），但 table-scroll 为 0.396s/3.8s（**350µs/pass，大目标场景
慢 45 倍**）——draw_list 提交成本随离屏目标尺寸显著放大，"pass 提交近零
成本"只对小目标成立。uniform set 复用良好（326 pass 仅 20 sets、12 顶点
缓冲），非瓶颈；批量提交/单围栏对 transitions（7.7µs/pass）收益有限，对
table 类大目标场景（350µs/pass）才是有效杠杆——但每帧长帧（100ms+）不能
仅由 350µs×几 pass 解释，下一批需在拖拽重帧上做帧级分解（process/encode/
flush 的时间线对齐）确认长帧构成。

transitions 维持：视口 35.6 vs RD 32.1（差 ~10%）；table-scroll 差距为
当前主要性能缺口。

## P3 性能收窄实施批（2026-11-07，帧级分解完成，mesh 反解 memo 尝试回滚）

帧级分解（table-scroll 拖拽段对齐）：视口段 elapsed≈1000ms（encode 32ms、
process 50ms、direct_offscreen 94ms）vs RD 段 3795ms（encode 2606ms、
process 3015ms、direct_offscreen 396ms）——RD 的宿主命令应用变慢使 Java
编码端背压等待计入 encode（80 倍表观涨幅主因是等待而非编码），命令应用
的主项=QUADS_REF 兜底对缓存 ArrayMesh 的逐批次 surface 反解。

实施：按 mesh 身份 memo 反解结果（消除逐帧重复反解）。结果回滚——memo 后
触发 4480 次顶点数断言：反解路径本身接收到非 4 倍顶点的网格（geometry
缓存中存在非 Prism 四边形批次来源，待查 build_prism_mesh 之外的 mesh 注入
点），正确性优先回滚至无 memo 基线（27.7fps 复测一致）。下一批先查清非
四边形 mesh 的来源与兜底断言的合法处理（跳过或断言前校验），再重上 memo。

## P3 性能继续批（2026-11-07，非四边形疑云澄清，memo 重上保留）

兜底入口诊断打印：geometry 缓存 mesh 全部为合法 4 顶点四边形（v/uv/custom/
col 均 4），当前零断言——上批 4480 断言实为 memo 补丁自身的作用域缺陷，
非数据问题。memo 以干净结构重上（mesh 对象身份键、64 槽），零错误保留：
消除逐帧重复反解（正确性中性偏正）。

性能结果如实：table-scroll 24.7-27.7fps（噪声带内持平）——**反解非主瓶
颈**，帧级分解的"反解主导"推断被修正；process 3.0s 中扣除 flush 0.4s 与
反解后仍有 ~2.5s 待分解（候选：每批顶点交错转换的 CPU 拷贝量、uniform set
acquire 的 FIFO 开销、窗口合成路径）。transitions 34.4fps/p95 71.3（本
轮环境好于上轮 32.1/79.8，处于噪声带上沿）；composite-edges RD 20/20 保
持全绿。下一批：process 剩余 2.5s 的定点剖析（GODOT_JFX_PROFILE_COMMANDS
命令级计时对拍两模式）。

## P3 定点剖析批（2026-11-07，命令级对拍完成，消费端待查项收窄）

PROFILE_COMMANDS 双模式对拍（table-scroll 拖拽段）：
- 视口：elapsed 1582ms，encode 220ms，process 327ms；1909 次
  draw_offscreen_2d 共 98ms（**51µs/次**）。
- RD：elapsed 3755ms，encode 2777ms，process 2800ms；direct_offscreen
  1130 次共 396ms（**350µs/次**）。
- 两模式的 shader_us/texture_us/target_us 命令计时相当（51.8/38.3/2.3ms
  vs 59.5/5.8/0.2ms），RD shader_creations=0（翻译管线全缓存命中）。

结论：①单次 pass 提交 RD 比视口渲染周期贵 ~7 倍（350 vs 51µs）但绝对量
仅 0.4s，非主差；②主差 2.5s 表现为 encode 与 process 同步增长——Java 编
码被宿主消费速度节流（队列背压等待计入 encode）；③process 中扣除 flush
与命令计时后仍有 ~2s 未落在现有剖析点上，最可能在窗口合成/呈现路径（RD
的 bridge 为 texture_rd_create 外部纹理，canvas 每帧依赖处理）或
process tick 的等待结构。下一批定点：present/compose 计时插桩，或用帧阶
段诊断（FramePhases）对比两模式渲染线程负载。

## P3 性能收尾批（2026-11-07，composition_finished 嫌疑排除）

present/compose 插桩（GODOT_JFX_RD_DEBUG 门控，RD_COMPOSE_DRAW 每 500 次
输出均值）：composition_finished 的强制 rs->draw+sync 分支在 table-scroll
两模式下均零执行（pending 流程实际走 host frame_presented 路径），该嫌疑
排除；窗口合成 draw 的真实成本需改在 frame_presented/compose_windows 处
插桩。本轮视口基线复测 59.9fps 确认环境稳定。宿主消费端 ~2s 的锁定移至
下一批（compose_windows+frame_presented 双点计时）；插桩保留供续用。

## P3 收窄续批（2026-11-07，finish_draw 量化，双 vsync 节拍假说）

finish_pending_pass 的强制 draw+sync 插桩（RD_FINISH_DRAW，门控保留）：
table-scroll RD 模式 draw_sync_us=440.9ms（视口 97.5ms，+0.34s）。对账
RD process 2.8s：flush 0.4s + finish_draw 0.44s + 命令计时 ~0.07s ≈ 0.9s，
仍有 ~1.9s 未归因；折合每帧 10-20ms——该量级不是单点 CPU 成本而是整帧
节拍：RD fps 22-28 ≈ 60Hz/2.x，与"帧提交刚好错过 vsync 期限、系统性排入
下下个 vsync"的形态一致（视口单 vsync 59.9fps）。下一批验证/收窄手段：
①用 GODOT_JFX_VSYNC_FALLBACK=0 对比（若节拍变单 vsync 则坐实）；②削减帧
末提交延迟（把散布的 pass flush 收拢为帧绘制前单次批量提交，既削峰也稳
定 vsync 对齐）；③present/compose_windows 补插桩完成对账。

双 vsync 假说 A/B：GODOT_JFX_VSYNC_FALLBACK=0 下 RD 模式 28.1fps（噪声带
内持平）——vsync 禁用回退不改变节拍，假说不成立或回退未生效；节拍问题
更可能在 FIFO/呈现与 RD 作业的交互，转向"帧绘制前批量提交"实施验证。

## P3 批量提交批（2026-11-07，identity 顶点缓存落地，table-scroll 首次实质收窄）

洞察：视口模式 quads_uploaded=0（全 QUADS_REF，画 mesh RID 零转换），RD 模
式每引用批次都做顶点交错转换+全量内容哈希（每帧 MB 级 CPU 拷贝）——命令
应用差的主项。实施 identity 顶点缓存：mesh 不可变 → 以 mesh 对象身份为键
缓存交错后的 vertex_buffer RID，引用批次命中即跳过转换与哈希（draw_quads
增 p_identity_key，host QUADS_REF 传 known.ptr()，mesh 兜底传 memo 键）。
identity 缓存仅持引用（释放归内容缓存，避免双 free——首版踩过）。

结果（table-scroll，RD 模式，零错误）：fps 25.8→**30.3**（+17%），p95
117.5→**94.0**（-20%）；composite-edges RD 20/20 保持全绿；transitions
33.5fps/p95 69.5（噪声带内）。对 59.9 视口基线仍余差距，p95 长帧仍是主
症状——剩余归因继续（候选：帧节拍交互与 finish_draw 批量化）。

## P3 剩余差距批·归因修正（2026-11-07）

对账修正：complete_offscreen_pass 的 DIRECT_OFFSCREEN 分支把
draw_offscreen_pass（RD 模式=flush）的耗时直接累计入 draw_sync_us——上批
"finish_draw 0.44s"实为 flush 自身耗时的重复口径，finish_pending_pass 的
整帧 draw+sync 分支在 table 场景极少执行（RD_FINISH_DRAW 零输出）——"帧内
多次整帧 draw+sync"假说排除，无需批量化改造。剩余差距的真实形态：拖拽脉
冲峰值帧（表格内容更新引入大量全新 QUADS 批次，不走 identity 缓存）峰值
处理慢——两模式对峰值批次的转换+缓存成本同构，差异收窄方向转向峰值帧的
pass 集中度与 flush 时机（帧绘制前批量提交仍是待实施的下一杠杆）。

## P3 峰值帧批（2026-11-07，separate 模式崩溃修复）

根因：移除 flush 的 rs->sync 后，static FlushList staging 在主线程下一次
填充与渲染线程执行上一作业之间竞态——safe 模式 FIFO 内联执行无碍，
separate 模式访问违例崩溃。恢复 flush 末尾 rs->sync（static staging 的必
需交接；transitions 已测 sync 非吞吐瓶颈，此前移除的动机不成立）。

结果：separate 模式完整跑通 table-scroll（96 脉冲出结果，24.0fps——RD
下 separate 仍慢于 safe 30.3）；safe 复测 29.8fps 无回退；composite-edges
RD 20/20 保持全绿。残留：separate 全场 28 次 uniform set 失效窗口的
invalid free（少量、不崩溃），连同峰值帧批量提交（separate 平台下 FIFO
调度成本才真实存在）留待下批。教训落档：移除任何同步前先核对被保护共享
状态的生存期——"对齐视口路径语义"不能替代对自身数据结构的竞态审查。

## P3 性能收口批·工程决策（2026-11-07）

①帧绘制前批量提交：评估后暂缓——基准主平台 safe 的 flush 经 FIFO 内联执
行（call_on_render_thread 主线程直接跑），把 N 次内联收拢为 1 次不减少
任何执行工作量，safe 无收益；收益主体 separate 当前 24.0fps 仍低于 safe
30.3，待其超过 safe 后批量提交才有平台意义。safe 差距（30.3 vs 59.9）的
进一步收窄只能来自减少峰值帧工作量（更激进的批次缓存/转换消除），而非
提交调度。
②separate 残留 invalid free（28 次/场，不崩溃）：FreeJob 的
uniform_set_is_valid 守卫已覆盖主要路径，剩余来自设备失效回调窗口的边
缘时序；频率低且无功能影响，列为 P4 资源退役语义批的子项而非独立阻塞。

## 验收门巡检批（2026-11-07，GodotView RD 开态缺口发现）

三能力验收门巡检：GodotView 关态（默认视口路径）PASS；**RD 开态失败**——
1168 次"uniform set 为 null"来自引擎侧（GodotView 场景视口的材质 uniform
set 在 RD 开启时未供给），非 OffscreenPass 绑定路径（新增的不可解析纹理
白默认回退未触发）。初步判断与 uniform set 失效回调/生命周期在双路径并存
时的交互有关，列为验收门闭合前的首要修复项。防御性改动保留：采样纹理无
设备视图时绑定引擎白默认并一次性告警（不阻断整批绘制）。node-shaders 与
JavaFX-in-Godot 两能力的 RD 双态回归待 GodotView 修复后统一执行。

## P4 首要批·GodotView RD 开态调查（2026-11-08，双事实分离）

日志证据分离：①`GODOT_VIEW_INITIAL` 成功输出正确颜色四元组——GodotView
纹理的初始渲染、JavaFX 采样与读回在 RD 开态下**工作正常**；②1168 次
"uniform set is null"始于引擎启动（Java 消息之前）、每帧持续但画面仍正
确——伴随性错误，疑似引擎侧某材质在 RD 环境变量下的供给警告（非本模块
绑定路径，白默认防御未触发）；③真正的失败是 resize 后——Java 观察器等
待 resize 动作超时（"GodotView resize action missing"），即 resize 后的
内容更新链在 RD 开态断开（候选：resize 时 GodotView 视口纹理重建后
uniform set 缓存的旧纹理视图/身份键失效未重建，或窗口合成未拾取新尺寸）。
下批从 resize 路径的纹理生命周期入手（uniform_set_cache/identity 缓存对
外部纹理 RID 变更的失效响应）。

## P4 第二批·GodotView RD 开态修复 + 三能力双态验收（2026-11-08）

**根因修正（推翻上一批两个判断）**：①1168 次/帧"uniform set is null"
不是伴随性引擎警告，而是 OffscreenPass 每帧绑定**已释放的 uniform set**：
`rendering_device.cpp:5927` 是 `ERR_FAIL_NULL(ownership 查找失败)`，
`RID::is_valid()` 只能识别默认空 RID，识别不了已释放 RID。日志时序证明
错误始于变蓝那一帧（`GODOT_VIEW_INITIAL` 之后），非 Java 启动前。②失败
点不在 resize：`animated` 门（等待 (40,40) 变蓝）从未通过，按钮点击从未
注入，Java 的 resize await 自然超时——resize 链是被上游卡死的下游。

**修复（javafx_rd_pass.cpp）**：uniform set 缓存命中路径增加设备级
`uniform_set_is_valid` 复核——引擎 RID 存活检查看不见"引擎 RID 不变但其
RD 视图被引擎替换"的场景（`RD_VIEW_CHANGED` 实测：外部场景纹理视图一次性
替换 → 设备级联释放引用旧视图的 set → 缓存持续返回死 RID → 每帧 2 个
draw 绑定失败）。死 set 视为 miss 重建；实测 `RD_STALE_SET` 仅发生一次，
自愈无持续开销。GodotView 双态（RD 开/关）test-godot-view 全绿
（开态 peak=16，关态 peak=55）。

**翻译器覆盖缺口（node-shaders RD 开态暴露）**：节点效果包装器注入
`COLOR *= godot_node_sample(UV)`——复合赋值读 COLOR，旧规则（仅
`COLOR =`/`COLOR.` 字符串替换+残留拒绝）直接拒译。改为 fragment 内全部
COLOR 引用 token 级改写到**初始化为顶点颜色 varying 的局部变量**
（`godot_out = godot_vertex_color` 起点，保留顺序读写语义，规范顶点阶段
本就输出该 varying）；varying 声明改为无条件全量；uniform 解析支持一行
多声明并剥离默认值（一行式源码的 `= vec3(1.0)` 曾泄漏进 std140 块成员
——GLSL 禁止块内初始化器）。node-shaders RD 开态零错误通过，关态回归
通过；全 corpus 262 零退化（186 exact/76 edge/0 failed）。

**spike 参考侧既有回归（P3 生产切换引入，非本批）**：P3 起
`JavaFXRenderTarget` 在 RD 环境走 OffscreenPass，rd_translate/rd_corpus
spike 的"视口参考"随之变成 RD 渲染，`texture_2d_get(桥接纹理)` 返回空
CPU 图像 → 参考全黑 → 231/262 误报失败（干净 HEAD 复现确认）。修复：
`initialize` 增加 `p_force_viewport` 参数（默认 false 行为不变），探针
参考目标强制视口路径，恢复"视口路径 vs 翻译 RD"的对照本意。translate
spike 三族恢复位一致（max_diff=0），LCD 位一致，corpus 恢复全绿。
另修 SceneTextureProbe 对 `drawTexturedQuads` 旧签名的调用（jfx 子模块
b8a8821 演进后未跟上，编译期失败），场景纹理双态通过。

**三能力 RD 双态验收（全绿）**：Godot shader 作用于 JavaFX（node-shaders
开/关）；Godot 嵌入 JavaFX（godot-view + scene-textures 开/关）；JavaFX
嵌入 Godot（protocol 开/关、composite-edges D3D 对照开/关、VFX demo 冒烟
开/关）。像素回归：corpus/LCD/translate spike 全绿。

**VFX demo 性能 A/B（同会话）**：transitions——关态 pulse_fps 40.9/
p50 17.5ms/p95 65.9ms，开态 33.9/22.7/72.2ms；开态 GPU pass 渲染耗时
9.76s→0.123s（-98.7%）。table-scroll——开态渲染 106ms→9.2ms（-91%），
但 encode_us 216ms→2720ms。结论：RD 直连的渲染成本优势成立且巨大，但
每 pass FIFO+`rs->sync()` 交接串行化宿主帧，Java 编码被回压拖长
（transitions encode 14.5s→34.5s），端到端仍落后视口路径。批量提交
（a270ec7 递延项）是转正的必要条件，列为 P3 遗留执行项。

## P4 第三批·separate 资源清理 + composite 自定义 shader 边界（2026-11-08）

**28 次 invalid free 已消失**：GodotView 修复（死 uniform set 缓存重建）顺带
消除了 separate 模式的 invalid free——退役路径 release() 对已由设备级联释放的
set 调 free_rid 的路径不再被触发。godot-view separate RD 开态复跑：PASS、
零 leaked/freed/invalid 警告。

**全局 Sampler 退出泄漏修复**：模块级 `g_shared_sampler` 此前从不释放，进程
退出报 1 个 Sampler 泄漏。新增
`godot_javafx::rd_direct::release_shared_sampler()`（渲染线程 FIFO+sync 释放），
在 `uninitialize_javafx_module`（SCENE 级，渲染服务器与设备仍存活）调用。
复跑确认零泄漏警告。

**composite 自定义 shader 边界（test-composite separate RD 开态暴露）**：
探针的自定义 shader 在 fragment 后带尾随辅助函数、fragment 体内带 `/* }
return; */` 注释——旧提取用 `rfind("}")` 把辅助函数头吞进 main、把收尾
`frag_color = godot_out` 挤到全局作用域（godot_out 未声明）→ 编译失败 →
5 个 draw 丢弃 → 像素断言失败。修复：注释/字符串感知的括号扫描器
`find_block_end`（depth 匹配，跳过 `//`、`/* */`、字符串字面量），fragment
体精确到匹配 `}`；尾随内容保留进翻译头部（辅助函数在 main 之前声明）。
composite separate/safe × RD 开/关全绿。

**回归**：corpus 186/76/0、LCD 位一致、node-shaders RD 开态、composite-edges
D3D 对照——全部通过（扫描器改动零退化）。

## P4 第四批·release 竞态修复 + 批量提交条件复核（2026-11-08）

**release() static staging 竞态（separate 暴露为垃圾 ID free）**：FreeJob 的
`g_uniform_set_staging`/`g_retire_staging` 为静态共享、原设计"不阻塞"——
table-scroll 每次场景切换连续销毁 render target，第二次 release 在渲染线程
执行上一次 FreeJob 前重写 staging（且 Vector COW + 作业内 clear()），渲染
线程对垃圾 64 位值调 free_rid，测试失败。修复：FreeJob 入队后补
`rs->sync()`（与 flush 同型交接；退役是拆 teardown 路径，阻塞可接受）。
separate table-scroll 复跑 PASS、零 invalid free（elapsed 4157ms vs safe
3633ms）。

**批量提交条件复核（仍递延）**：separate 4157ms 仍慢于 safe 3633ms——
"separate 超过 safe 后批量提交才有平台意义"的条件未变，按 a270ec7 决策
继续递延；safe 端到端差距的杠杆仍是峰值帧工作量削减（非提交调度）。

**copy_target 对照（覆盖式关闭）**：视口路径 `canvas_item_add_texture_rect`
与 RD 路径 TEXTURED_SOURCE 四边形对同一源纹理采样的语义等价，已由双态
绿灯矩阵实际覆盖：node-shaders 的 GaussianBlur 嵌套目标链（嵌套
copy_target 组合）、composite/composite-edges、LCD 快照语义、窗口合成。
不另建重复对照夹具。

**P5 性能门槛现状**：计划期 RD 直连 ~52fps；今日同会话实测视口基线本身
仅 40.9fps/p95 65.9ms（worst=TableView 场景切换，内容侧卡顿主导），55fps
门槛当前环境对任一后端不可达；RD 直连 33.2fps（release-sync 无回归），
渲染侧成本已压至基线的 ~1%。像素回归半壁（mobile × RD 双态 corpus/LCD/
translate/composite/node-shaders/GodotView/scene-textures）已全绿；gl
_compatibility 全量像素扫描与性能收口（批量提交/峰值帧）留 P5 后续批次。

## P5 首批·gl_compatibility 全量像素扫描（2026-11-08）

双渲染器像素回归补齐 gl_compatibility 侧（无 RenderingDevice，RD 直连自
动保持视口路径，rd_unavailable 回退）：corpus spike 回退通过、node-shaders、
godot-view、scene-textures、composite、composite-edges（对原生 D3D）、VFX
demo 冒烟——全部通过。至此像素回归矩阵闭环：mobile × RD 开/关 +
gl_compatibility 全绿。

性能收口（批量提交/峰值帧削减）为独立工程项：决策条件与不可达的 55fps
门槛现状均已落档（见 P4 第四批），递延至条件变化（separate 超 safe 或基
线环境改善）后启动。

## 批量提交批（2026-11-08，RD 直连性能反超视口基线）

**批量提交落地**：flush() 只把 pass 追加进静态批（不提交）；新增
`OffscreenPass::commit_batches()`——单渲染线程作业顺序渲染整批 + 单次
sync。提交点：宿主 tick 末（命令循环后，紧邻既有 fence sync）、readback/
release 前置强制提交、finish_pending_pass 强制绘制前。`GODOT_JFX_RD_BATCH=0`
回退逐 pass 提交。实测 18:1 作业收敛（1150 pass/63 提交），单独对 safe 模式
fps 中性（与 a270ec7 预判一致：safe 的 FIFO 内联执行无平台收益）——但批量
使顶点环与后续优化的中途排空成为可能，且 separate 首次追平 safe
（table-scroll 1591ms vs 1584ms），"separate 超 safe 后批量提交才有平台
意义"的递延条件达成。

批量提交是本批的入口，profile 归因（新增 GODOT_JFX_RD_PROFILE 子站点
计时 + 宿主 HOST_GEOM_PROFILE）随后定位并消除了三个真实大头：

1. **管线缓存每实例化**：场景每次切换销毁目标→新目标空缓存→每场景重编
   ~100 个 shader（translate+SPIRV+pipeline，~1.6ms/个），68 次切换共
   6863 次编译、11.1s。管线/翻译缓存提升为进程级全局（所有目标同为
   RGBA8 帧缓冲与统一顶点布局，管线天然可共享；`release_shared_pipelines`
   在模块卸载退役）。编译数 6863→13，transitions fps +24%。
2. **tagged QUADS 数据往返**：宿主把新几何建成 ArrayMesh，RD 分派又把
   mesh 解码回原始数组（每批 ~1ms）；`geometry_raw` 本存着原字节。
   tagged 分支补填 referenced 数组，RD 直接走 raw 路径。table-scroll
   process 2575ms→253ms（10×），encode 同步 10× 收窄。
3. 顶点字节哈希字块化（8×）与**顶点缓冲环**（同尺寸 buffer_update 复用，
   纪元守卫防同批别名；identity 键获取强制不可变路径——环 RID 曾泄进
   identity 缓存导致 composite 引用批次渲染错误几何，已隔离）。

**最终同会话 A/B（mobile/safe）**：transitions——RD 直连 **56.96fps /
p50 16.6ms / p95 27.6ms**，视口 42.62/17.3/62.6（**fps +34%，p95 -56%，
p99 -38%**）；table-scroll——RD 1584ms vs 视口 1583ms（追平）；separate
table-scroll 1591ms（与 safe 持平，零 invalid free）。P5 性能门
（≥55fps 且 p95<25ms）：fps 达标，p95 27.6ms 距门槛 2.6ms（后续可用
draw 合批/常量进一步压）。

**正确性**：composite/composite-edges(D3D 对照)/corpus(186/76/0)/LCD/
translate spike/GodotView(node/scene-textures 同套)/node-shaders/
scene-textures 双线程模式全绿；退出零泄漏。新增诊断开关：
GODOT_JFX_RD_BATCH（批量，默认开）、GODOT_JFX_RD_RING（顶点环，默认开）、
GODOT_JFX_RD_PROFILE（子站点计时）。

## 泄漏诊断批（2026-11-08 下午，手动测试暴露，诊断闭环、修复递延）

**现象与定性**：用户手动跑 VFX demo（RD 直连批量态）退出时报 37k
VertexBuffer/32k VertexArray 泄漏。回放确认：**该泄漏在 HEAD（629d046）就存在**
——transitions 全程 13-17k、table-scroll 单场景 30s 高达 58-60k（约 2k 设备
缓冲/秒）。属既有缺陷，手动长会话首次暴露；正确性套件与全部性能成果不受
影响（scroll 在 HEAD 依然 PASS 且 1583ms 追平）。

**归因（计数器台账实证，两层成因）**：
1. **弱哈希碰撞替换**（主项）：`bytes_hash` 的字块 FNV 对结构化浮点顶点
   数据雪崩不足，同库测得 ~30% 键碰撞；`vertex_buffer_cache.insert` 同键
   替换把旧缓冲裸丢（无释放、无追踪）。台账：cache_inserts 60839 − release
   时缓存 42407 = 18432 ≈ 泄漏数。murmur3 风格字块哈希实测把 transitions
   泄漏 17.4k→10.7k（碰撞项归零，余为下项）。
2. **缓存容量清空即丢弃**：128/256 cap 触发 `clear()` 丢所有权（单场景
   动画内容反复触顶，丢出的 RID 无人释放直到进程结束）。
另证：所有 FreeJob 均执行（free_jobs == release_calls，12.4 万 RID 释放），
退出路径与退役顺序无问题——泄漏全部来自"从未进入任何退役清单"的 RID。

**两次修复尝试与失败模式（教训落档）**：
1. 淘汰 GC（evict→垃圾清单→下次 commit 渲染后释放）：暴露
   "未 flush 的 recorded draw 仍引用被淘汰 RID"窗口，567 例死数组绑定；
   补部分 flush（淘汰前先入批）后仍余偶发错误——批/录制/淘汰三方生命周期
   耦合过紧，未能在预算内稳定。
2. 淘汰 RID 存活到 release + 退出点强制 release（注册表+模块卸载+宿主
   EXIT_TREE）：释放时机与实例析构/FIFO 存活期交错，引入 3 例 double-free；
   宿主 EXIT_TREE 释放亦未消除泄漏（单场景实例在该时点前的中途 FreeJob
   已执行、清单为空者无济于事——泄漏 RID 从未入清单）。
另：murmur 单独落地时 scroll 出现 4 例偶发数组竞态错误（dedup 模式变化
唤醒的潜伏竞态，疑与顶点环 buffer_update 生命周期相关）——一并归入下批。

**递延结论**：泄漏修复需要专门批次做"录制/批/缓存/退役四方生命周期"
的统一设计（候选：淘汰 RID 带世代标记的惰性退役 + 环的引用计数化 +
dedup 键改为内容指纹+全量比对兜底），并先补一个可复现泄漏的压测夹具
（当前依赖 30s demo 跑法）。修复前的暴露面：长会话（分钟级连续动画）
GPU 设备内存缓慢增长；短测试与场景切换频繁的会话有界。

**回归保护**：诊断期间的全部代码改动已回退，工作树与 HEAD 一致
（629d046）；本轮仅落档不落码。

## 泄漏修复批（2026-11-08 晚，三层修复落地，长会话零泄漏）

承接下午的诊断批，本轮把修复完整落地并全量验证。三件套：

1. **murmur3 风格字块哈希**替换弱 FNV 变体：消除结构化浮点顶点数据的
   ~30% 内容键碰撞（碰撞导致同键 insert 替换丢 RID 与假命中错几何）。
   尾部字节下溢（size_t 递减绕回）以先减后读循环修正。
2. **缓存淘汰 GC**：128/256 容量触顶时，淘汰 RID 进入进程级垃圾清单
   （带种类标记：set/array/UBO/buffer），由下一次 commit 的渲染作业在
   **全部 draw 渲染完之后**于渲染线程按依赖序释放（sets 带有效性守卫→
   arrays→UBOs→buffers）。关键修复：淘汰前若本 pass 有未 flush 的录制
   draw，先 **partial flush**（同帧缓冲顺序入批，`recorded` 必须清空）——
   下午 567 例死数组绑定的真因就是 partial flush 漏了 `recorded.clear()`，
   同一批 draw 被二次 flush，第二次绑定已在首次 commit 后释放的数组。
   buffer 淘汰联动清 array 缓存与 identity 引用。
3. **退出兜底**：OffscreenPass 活实例注册表 + 模块卸载时
   `release_all_passes()`（防 Java 纹理池把目标持有到 FIFO 已死的退出期）。

**验证（全绿）**：table-scroll ×2（此前 58-60k 泄漏）PASS 零泄漏零错误
零 invalid free；transitions PASS 56.6fps 零泄漏（此前 13-17k）；composite/
composite-edges(D3D)/node-shaders/corpus(186/76/0)/LCD/translate spike/
GodotView(safe+separate)/scene-textures 全过；GODOT_JFX_RD_BATCH=0 与
GODOT_JFX_RD_RING=0 两开关态 composite 过；demo 冒烟零泄漏。LCD spike
退出期 1 例 invalid free 为该 spike 自身既有瑕疵（所有历史日志一致），
非本批引入，另记。

**遗留观察**：murmur 单独（无 GC）时曾见 4 例偶发数组竞态——GC 落地后
连续多轮未复现；若再现优先怀疑顶点环 buffer_update 生命周期，用
GODOT_JFX_RD_RING=0 A/B。

## 呈现竞态批（2026-11-08 深夜，悬停闪烁修复）

**用户实测两个缺陷**：①长表格按住拖动卡顿（滚轮流畅）；②部分按钮悬停闪回
未悬停态。逐层取证：

1. **拖动基准未复现卡顿**：默认（直接调 DragHandler）、real（GD 注入
   16 事件/帧）、robot（真实光标）三种模式全部 ~60fps、p99 ≤30ms——脉冲
   节奏层无卡顿（用户感知的"卡"更可能是内容级顿挫，见下）。
2. **悬停夹具三层定位**（新增 HoverFlickerProbe + hover_flicker.gd）：
   Java 侧 hoverProperty 静止零振荡（enters=8/exits=7 全为合法换钮）→
   输入侧排除；合成按钮像素级采样：**RD 直连+批量 63% 保持帧缺悬停色，
   视口路径 0.3%、RD+逐 pass 提交 0.5%** → 批量提交的呈现竞态实锤；
   按钮归属位流显示绿色整段缺失/延迟数秒+单帧丢失（非逐帧交替）。
3. **根因**：批量提交把**呈现帧**（WINDOW_PRESENT 路径的
   draw_offscreen_pass）的渲染推迟到 tick 末，与 tick 中录制的窗口合成
   （compose 画桥接纹理）竞态——悬停重绘的批量条目晚于合成被采样的时刻，
   画面停留在旧内容直到下一次巧合对齐。

**修复（javafx_host.cpp）**：DIRECT_PRESENT 分支在 draw_offscreen_pass
后立即 `commit_batches()`——呈现是合成与交换链可见的帧边界，其渲染必须
在该边界完成；中间效果 pass 仍批量（保持 18:1 作业收敛的主要收益）。

**验证**：悬停夹具 63%→0.5-1.5%（新增
`scripts/test-hover-flicker.ps1` 回归门，双线程模式过）；transitions
57.0fps 保持（无回退）；table-scroll 默认/real/robot 三模式 ~60fps，
默认模式 p99 26.9→19.9ms 改善；composite/composite-edges(D3D)/
corpus(186/76/0)/LCD/GodotView(双态)/node-shaders/scene-textures 全绿；
零泄漏。**拖动卡顿与悬停闪烁共享该呈现竞态根因**（拖动=持续内容更新+
持续呈现，同竞态表现为内容顿挫），修复后基准改善但用户手感验证待
手动确认。

## 水平拖动批（2026-11-09 凌晨，定位到 JavaFX 绘制路径，修复递延）

**用户线索**：拖动"不涉及左右则帧率高，涉及左右骤降"。据此扩展
VfxTableScrollProbe（GODOT_JFX_DRAG_AXIS=h + 移植栈采样器）与新增
NativeTableDrag（原生 D3D 对照夹具），闭环取证：

1. **复现**：robot 真实光标——纵向 60.0fps/p99 23ms vs **横向 44-48fps/
   p95 58-78ms**；视口模式（RD 关）横向同样 44fps → 非 RD 特有。
2. **原生对照（关键）**：同一表格页同一 robot 拖动，原生 D3D JavaFX
   **63.1fps/p95 20.7ms** → 差距在我们桥接的 JavaFX 绘制路径放大。
3. **归因**：横向拖动每帧产生 **~21 个裁剪中间体 pass**（JavaFX
   renderForClip 慢路径：页面级形状裁剪层把宽表格子树渲染到中间表面
   再合成；纵向拖动仅 ~4 采样经过该路径，横向 173/191 采样）。
   渲染线程在拖动期间 ~85% 时间处于 NG 绘制遍历；HOST 侧 encode/
   process 仅 ~15%，tick 保持 60Hz——瓶颈在 Java 侧绘制遍历经桥接
   的放大，疑似原生走脏区优化而我们逐层全量重绘。
4. **两个使能实验已做并回退**：(a) 渲染目标原生回收器（同尺寸复用）
   ——生效（RD_INIT 152 次而非每帧）但 fps 不变，且引发 composite
   row=0 回归（回收语义与录制中 draw 生命周期冲突），整体回退；
   (b) Java 纹理池 64MB→512MB——暴露**原生帧账本 MAX_BYTES=256MB
   准入拒绝**（"Invalid texture transaction"，Java 池上限一直在
   无意中保护账本），transitions 失败，回退。横向表格圆角→矩形
   裁剪实验：无效，已回退（保留视觉效果）。

**递延结论**：修复需专门批次做 ViewPainter/脏区集成分析（为何原生
每帧中间体更少/复用更激进），以及 池上限/账本上限/原生回收器 三者的
联合设计（当前互相钳制）。诊断夹具已入库：探针水平轴+栈采样、
NativeTableDrag 原生对照。

## 递延批落地（2026-11-09，水平拖动 44-48→60fps 修复）

**关键纠偏**：上批栈采样器从浅端取帧，"NG 遍历占 85%"是采样伪影。改为
深端采样后真热点是 **GodotRenderCommands.evictIdleGeometry**——不是
JavaFX 绘制路径本身，递延批原定方向（ViewPainter/脏区集成）不再必要。

**真机制**（两环叠加，均在 Java 编码器）：
1. **逐 draw 全表扫描**：几何缓存超 1024 条后，每次 drawQuads 命中都
   迭代整个 HashMap 找过期条目（O(n)/draw）。
2. **缓存膨胀不收缩**：横向拖动时裁剪中间体每帧产生全新几何（~2700
   条/帧），条目要 64 次提交才过期 → 缓存涨到十万级且扫描永不短路。
   纵向拖动为纯平移（局部顶点不变，transform 变化不进内容键）→ 全
   命中、缓存稳定 ≤1024 → 扫描被 `size() <= MAX` 短路——这就是
   "纵向流畅横向骤降"的完整解释。

**修复**：
- `geometryCache` 换 **accessOrder=true 的 LinkedHashMap**（LRU：头部
  即最旧）；扫描**每提交至多一次**（lastEvictSubmission 门），从头部
  驱逐到 3/4 水位、遇新条目即断（访问序保证其后皆新）。churn 成本
  摊还为每条目一次移除。
- 曾试"气球超限短地板强驱逐"（floor 8）——暴露**潜伏缺陷**：被释放
  网格的堆地址被复用后，原生 identity 顶点缓存（按 mesh 指针为键）
  供给陈旧缓冲 → 越界读（也解释了历史偶发 vertex 错误）。修复：
  宿主 GEOMETRY_FREE 处理时对 mesh 指针调用
  `purge_identity_caches()`（遍历活 pass 清对应 identity 条目）。
  该强驱逐本身回退（空闲地板 64 仍是唯一安全边际）。

**验证**：水平拖动（robot 真实光标）**59.98fps / p95 24.7ms / 零错误**
（修复前 44-48fps / p95 58-78ms，原生 D3D 对照 63.1fps）；纵向
59.95 / 默认 59.92 无回退；composite/composite-edges(D3D)/corpus
(186/76/0)/LCD/GodotView(双态零错误零泄漏)/node-shaders/
scene-textures/hover 门/transitions(56.5fps)/demo 冒烟全绿零泄漏。

## 菜单卡死批（2026-11-09，池/账本联合上调，悬停事件水龙头入库）

**用户实测**：tableview 正常（横向拖动修复确认）；点 menu 按钮后程序卡死。
日志取证：点击后下一帧被帧账本拒收（"Invalid texture transaction"）→
Java 编码器永久 failed → 每帧抛 IllegalStateException → 界面冻结。

**可复现探针**（新增 MenuClickProbe：最大化窗口+浏览 6 页+点菜单）：
最大化 2560×1600 下菜单抽屉的效果/裁剪中间体把 **Java 纹理池 64MB 上限**
打爆 → allocate 返回 null → `PrTexture: Texture must be non-null`（探针中
被吞 27 次；用户会话中级联为账本拒帧）。递延批预言的"池/账本互相钳制"
正是此场景：单侧上调必然炸另一侧。

**修复（协调上调两级）**：GodotTexturePool 64/128MB → **512MB/1GB**；
原生帧账本 MAX_BYTES 256MB → **1GB**（并改为 public 供测试引用）。
账本语义是准入合理性而非内存管制——真实占用由实际分配决定，两级注释
互相指认联动关系。frame_protocol_test 的两处贴边断言（8192²=256MB）
改贴新上限（16384²=1GB），预算规则语义不变。

**验证**：菜单探针 PASS 零异常（原 27 次异常+卡死）；transitions 59.4fps
零 Invalid 零泄漏；protocol 全绿；composite/edges/corpus(186/76/0)/
GodotView/node-shaders/scene-textures/hover 门全过；横向拖动 59.3fps
保持；demo 冒烟零泄漏。另入库：GODOT_JFX_HOVER_TAP=1（demo 场景级鼠标
事件水龙头，IntroFXMain 内）与 HoverDemoProbe 的 hover/布局事件日志，
用于后续悬停闪断的人工复现取证。

## 悬停真异常取证（2026-11-09，GODOT_JFX_HOVER_SAMPLE 落地）

用户复现会话（61 分钟，5037 帧鼠标下方亮度采样 + 1827 Java 事件）分析：

1. **"大概率闪回"主项=按钮按下反馈（非缺陷）**：FusionButton 按下
   `stopAndSetNode(downNode)` 瞬跳按下色（0x1f2125，luma≈0.13-0.20，与
   初始常态色肉眼几乎无法区分），松开瞬跳悬停亮色。三次检测到的
   "回退"中两次（SEQ2/3）逐帧解码均为该反馈，时长精确等于按下时长
   （134ms/117ms）。原生 D3D 行为相同（纯 JavaFX 场景逻辑）。
2. **症状 B（移走不恢复）本次会话零命中**：全部 EXIT 后亮度均在正常
   时限内回落。
3. **真异常 SEQ1（1/5037 帧，0.02%）**：悬停渐变中途（luma 0.325），
   画面瞬跳初始态（0.161）持续 ~0.6 秒，再瞬跳动画终值（0.348）。
   期间 Java 零事件、动画持续渲染——**呈现层把 ~36 帧前的旧内容
   顶上窗口**。候选机制：FusionPane 的 renderForClip 中间体 RT 的
   重渲染晚于窗口呈现提交（中间体 pass 批内时序）。需更多样本定位
   （本次仅 1 例）。

工具：GODOT_JFX_HOVER_TAP（Java 事件水龙头，IntroFXMain）+
GODOT_JFX_HOVER_SAMPLE=1（帧级鼠标下方亮度，vfx_demo.gd）已入库，
后续复现会话直接开启双记录即可。

## 悬停动画卡滞取证二（2026-11-09 下午，两次新捕获 + RD 对齐）

用户第二轮只悬停不点击的会话（1604 帧采样 + 26020 RD_FLUSH）再捕获
2 例真异常，并排除按下反馈混淆后，统一模式为：

**悬停渐变中途画面冻结在半程值 ~0.5s，一次 MOUSE_MOVED 后立即跳到
动画终值**（f2354 卡 0.208→MOVED→0.399；f2968 同型）。这正是用户
原始描述"略微移动鼠标时变成最亮"。SEQ1 的整窗回初始 0.6s 为同族
更重形态。

**RD 对齐结论**：卡滞窗口内裁剪中间体（renderForClip 各 RT）以
draws=1-2 持续 flush（动画在渲染、帧在提交），但**窗口目标 RT 整个
窗口期只 flush 一次**——中间体渲染流正常，**最终合成到窗口的 pass
被跳过/延迟 ~0.5s**，输入事件触发的新呈现才把累计结果带上屏。

候选机制（下批验证）：Java 每帧的窗口呈现（WINDOW_PRESENT→
publishWindow→submit）与中间体 END_PASS 在同帧内的顺序/合并被
批处理改变——呈现边界 commit（ea840f1）只保证了"present 时点已
提交"，但 Quantum 对"无脏区帧跳过整窗重绘"的优化可能让窗口 pass
仅在被输入再次弄脏时才发生。验证手段：presentWindow/submit 时间
戳加入 HOVER_TAP 通道对齐。

## 悬停卡滞定位（2026-11-09 晚，PRESENT 时间戳一锤）

第三次复现会话捕获 1 例卡滞（f1280-1320，0.223 冻结 726ms 后跳
0.402），PRESENT 时间戳通道给出决定性证据：

**卡滞期间 Java 持续 PRESENT（~33ms 一个，24 次），但内容冻结** ——
呈现链（渲染线程）全程健康；冻结的是 **FX Application Thread**：
动画（AnimationTimer 经 Quantum 脉冲驱动）与输入事件处理都在 FX
线程上，726ms 内零动画推进、零事件处理；恢复瞬间动画按墙钟追赶
直接跳到终值——精确解释"略微移动鼠标时变成最亮"（输入唤醒 FX
线程 → 排队脉冲补跑 → catch-up 跳变）。渲染线程期间持续重绘并
呈现冻结的场景快照。

**下一步（单点验证）**：在 GodotEventLoop 上加任务入队/执行时间戳，
区分 FX 线程是"无任务可执行"（脉冲调度器没投递——host frame tick
停流）还是"有任务但执行阻塞"（某任务阻塞 700ms，候选：bridge
sync/submit 回压）。两个答案分别指向 host tick 供给与 FX 任务链。

## 悬停冻结结案（2026-11-09，宿主主循环停顿定性 + 脉冲饥饿补救）

zcode 留下的 FX_GAP 探针有逻辑缺陷（take() 返回即清零计时起点，永不打印），
其"末轮零命中"不具结论性。修正探针（FX_GAP=take 阻塞时长/queued、
FX_TASK=任务执行时长/任务类名）后四轮人工复现采集（GODOT_JFX_HOVER_TAP=1，
repro-hover-manual.ps1）闭环：

1. **断流点定位**：每个 FX_GAP（FX 线程空等 124-580ms，队列空）都有一个
   等长 HOST_GAP 配对——**Godot 主循环真实停顿**，FX/渲染线程均无辜。
   停顿聚集在菜单抽屉开启、菜单项扫过、切页后的内容突发；`prev_body`
   显示停顿不在宿主进程体（GPU 同步 HOST_SYNC 全程零命中），
   `HOST_PHASE` 将其归因到引擎 `RenderingServer::draw` 段
   （一例 264ms/pipes=0）。停顿内分量两类：管线编译/显存分配突发
   （pipes=23/tex=+200MB，随运行热身衰减）与零分配零编译的呈现等待类
   （draw 100-210ms，含用户无输入时的偶发 134ms，疑与桌面 GPU 争用相关）。
2. **修复（Java 侧，调度韧性）**：`GodotPulseScheduler` 断供补救——
   await 超时 1000→100ms 且超时时照常投递合并脉冲（原路径直接丢弃），
   动画在宿主停顿期间按墙钟推进；补救投递上限 3 次/段停顿（与有界渲染
   队列容量对齐），防止模态循环级长停顿把 submit 重试推向 10s 死线。
3. **验证**：修复后采集 HOST_GAP 仍 7 次（宿主停顿是真实负载），但
   **FX_GAP 归零**——动画供给不再断。恢复瞬间出现一次 FX_TASK 353ms
   （Quantum 脉冲任务的追赶绘制），属预期收敛路径。回归：protocol /
   hover-flicker 双线程模式（flicker 1.3-1.4%，与 ea840f1 后基线一致）/
   pulse-stop / glass-scheduler / vfx 冒烟全绿。
4. **顺路修复**：test-hover-flicker.ps1 编译缺 vfx classpath（dba34a5
   起即坏）；HoverFlickerProbe 舞台未置顶，被前台窗口遮挡时真实光标
   事件落空（enters=0 假败）——已加 setAlwaysOnTop。
5. **症状 2（菜单扫过残留）**：六轮采集零复现，与 zcode 四轮结论一致；
   按同族（停顿期陈旧帧滞留）处理——补救脉冲保证 EXIT 过渡按墙钟完成，
   恢复后首帧即终态。若用户侧仍见残留，需单独捕获再查
   `GodotApplication` kind==8 的 `hovered != source` 丢弃分支。

工具链入库：HOST_GAP/HOST_PHASE/HOST_SYNC 宿主探针
（javafx_host.cpp/main.cpp，GODOT_JFX_HOVER_TAP=1 门控）、
修复后的 FX_GAP/FX_TASK（GodotEventLoop）、
scripts/repro-hover-manual.ps1（人工复现+自动汇总）。

### 2026-11-10 菜单复现工具审查更正

上述历史 MenuClickProbe 使用 Robot、无限 latch 等待和 FX 线程 sleep，且忽略
最终 pulse 等待的超时返回值；旧 PASS 不能证明这些失败路径已正确处理。
当前版本改用 FX 定时状态流程和 Godot 合成输入，保留最大化/浏览六页/打开
菜单的负载；要求原菜单动作成功一次及后续宿主完成渲染/合成提交继续增加。
入口为 test-menu-click.ps1，详见 TESTS；mobile/separate 通过，无真实鼠标操作。

### 2026-11-10 早期 RD spike 的不可用设备判定更正

rd_direct_spike 和 rd_translate_spike 以前在 GL 下输出 PASS rd_unavailable，
实际未执行 RD 绘制，也未验证生产 viewport 回退。现在明确要求 RenderingDevice，
缺失时退出 1 且不输出 PASS。本轮两个探针 Vulkan/mobile + separate 正常路径
通过，GL 路径均确认拒绝；历史“回退通过”仅表示跳过，不能作为回退验收证据。
生产 OpenGL 能力由对应的 Stage/Effect/窗口等功能测试独立证明。

## 2026-11-11：诊断探针共享状态保护

`cycle_probe` 与两阶段 `translate_probe` 使用同一个 CycleState。对照测试完成
阶段 A、等待引擎绘制参考图时，cycle 基准必须返回 `cycle_already_active`；
否则会覆盖原有 GPU 资源句柄，导致对照数据损坏和资源泄漏。三族对照探针现已
覆盖拒绝重叠调用后继续完成阶段 B 的路径。调用方仍须在成功或失败后调用
`release_rd_cycle`，释放完整或部分创建的资源，再开始下一项诊断。
