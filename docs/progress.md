# 历史工作记录

本文件保存历史实施与验证记录。每条记录中的“当前”“下一步”“未实现”仅指当时阶段；旧 RD/separate 命令不再适用于当前版本。当前实现见 [架构](architecture.md)，证据与限制见 [验收状态](acceptance-status.md)，可运行命令见 [TESTS.md](../TESTS.md)。

## 2026-11-13 — Viewport＋safe 收敛与残留清理

- 删除自定义 RD-direct 后端、翻译器、编译/运行开关、JNI 能力查询和专用探针，以及 separate 专用通知、纹理代理和 Windows 线程适配。保留 Godot 自身渲染器、RenderingDevice、区域上传及资源回收修复。
- 以 `9d1f2a2` 和其 Godot/JFX 指针为基线，复查函数、内联方法、字段读写、JNI、ClassDB、协议和测试入口。累计清理遗留 spike/mesh 包装、旧剪贴板 JNI 入口、回调计时状态、上传派发包装、full-shadow 参数分支及从未更新的窗口 GPU 字段。
- 34 个剩余 JNI 入口、30 个协议命令有调用/消费路径；层合成器仍服务主 Stage 和次级原生窗口，不是可删除的旧窗口模型。审计清单为 `artifacts/dead-code-audit/audit.json`，生成时的 HEAD 早于随后 amend；文件散列对应审计源码。
- 引擎、JFX、Media 源码构建及主要回归分轮通过；最终上传 API 改动后重测两种渲染器的纹理更新、Viewport 状态、批次边界、协议、Runtime 窗口控制及 Demo 启动。更早的 Robot 与 Media 结果不等同每次清理都全量重跑。
- 表格和 68 次切页 GPU 诊断通过，但默认时间戳池先发生容量错误；临时使用 8192 槽位后恢复配置。直接离屏路径的 GPU 样本为零是测量限制；窗口 GPU 样本由夹具直接读取，不再输出旧宿主零值。诊断运行不作为普通性能验收。
- 系统剪贴板复验因现有 `DataObject` 无法安全备份而在写入前停止，未改写内容；编码和保护单元测试通过。保留物理设备、长期内存等验收限制。
- 清理验收入口与性能指南中的重复过程、已删除开关和旧字段说明；详细历史过程可从旧提交查阅。当前状态以对应指南为准。

## 2026-11-11：本次实现审查收尾

- 固定原始审查 156/156、累计补充收尾 52/52。范围保持根仓库 127、Godot 10、JFX 19 原始路径，并包含累计修复；当前修改内容与审查哈希对应。没有提交或更改 VFX 业务行为。
- 六轮 Viewport/mobile/256MiB 实跑完成，35 页、409 份 Java/原生样本、988 次进程采样、40 次自然 GC，最终 owned=0。第 3–6 轮目标数保持 232；首页 static MiB 为 235.78/238.11/240.61/241.24，纹理 MiB 为 869.86/872.09/873.64/873.64。共享网格预算始终不超过 4096。
- 剩余 owned 增加主要是每目标有界材质/着色器/绘制槽填充，不能把总数要求为常数。末半段 private OLS 约 +9.70 MiB/min；另排除最后 10 秒退出段、只看 750 秒之后，private 范围 3876.29–3895.27 MiB、OLS +4.87 MiB/min。结果支持该有限工作负载预热趋缓，不宣称零增长或无限时长无泄漏。
- 当前双路径帧率 Viewport 58.604 / RD 59.662 Pulse FPS，68 次切换、失焦 0、清理通过。GL/Vulkan 共享缓存预算、淘汰后像素、单个及最后目标释放通过；补充 mobile/separate 离屏目标、Media 平面和 Runtime 视频控制均通过。
- 最终证据与限制见 artifacts/review-completion-audit.json、review-cumulative-closeout.json 和 memory-validation.md。系统剪贴板最新完整复验被未知私有格式保护拒绝，实际输入法/虚拟键盘可见性等项目兼容性限制仍保留，不改写成通过；它们不等同本次代码审查仍有已定位未修缺陷。

## 2026-11-11：六轮运行期间同步验收入口

- 验收状态和审查清单顶部统一为共享缓存修复后的内存/双路径帧率，旧 58.742 FPS 和修复前增长值标为历史；避免入口与文末最新结果不一致。
- 六轮 soak 同一进程仍在推进；未并发运行 GUI/性能测试，未重启或修改配置。最终结果待完成后分析，不把当前阶段写成通过。
- 根仓库/Godot/JFX diff 检查通过。原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52。

## 2026-11-11：剩余增长的纹理池回收语义与六轮验证

- 复读 GodotTexturePool、BaseResourcePool、ImagePool 与 Quantum 调用点。正常帧维护会更新资源年龄；分配超出动态目标时才依次清理/淘汰，目标可从 512 MiB 增长至 1 GiB。软引用图像池不是每页切换后立即释放，不据此把三轮增长直接判为泄漏或正常。
- 三轮首页分类差值保存 review-residual-growth-analysis.json。第二到第三轮共享网格增量为 0；目标 +12、材质 +281、shader +73、slot +46，retired 列表为 0；继续定位剩余资源而非重复修改已受控网格缓存。
- 相同 Viewport/mobile/256MiB 配置启动六轮完整验证，不强制 GC，不改业务逻辑、动画或池预算；结果待进程完成后检查后半程同页趋势。没有同时运行其他 GUI/性能任务。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52。

## 2026-11-11：共享缓存三轮结果、最终释放与双路径性能

- 三轮完整运行及最后使用者释放断言通过；GL/Vulkan 均确认最后目标退出后新缓存只有新绘制的 1 项。原始排队像素断言保持不变。
- 首页 static 211/226/234 MiB（此前 401/566/650）；进程 private 峰值约 3.70 GiB（此前 5.19），末半段斜率约 +38 MiB/min（此前 +116）。shared_target_meshes 始终不超过 4096。
- mobile/safe Viewport 58.604 pulse / 55.741 composition FPS；RD 59.662 / 56.786。均 68 次切页、失焦 0、清理通过；独立复算和当前产物哈希见 review-shared-mesh-performance.json。偶发长帧不修复。
- 目标数仍为 196/219/231、材质 1957/2555/2836，纹理约 775/817/836 MiB。缓存预算累乘问题修复有效，但残余增长尚未解释，不能将导航 PASS 当作完整内存验收。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52，下一步核对目标/纹理池和材质保留。

## 2026-11-11：共享缓存第一轮数据与最终释放断言

- 修改后三轮 soak 仍使用同一进程。第一轮回到首页 shared_target_meshes=4096、static_bytes=221471571（约 211 MiB）；单轮对照快照见 review-shared-mesh-first-round.json。完整趋势与性能结论仍待运行结束，不能据此宣布全部内存稳定。
- 压力夹具增加最后使用者释放检查：释放全部目标后新目标只绘制一个网格，缓存必须为 1，包装脚本要求独立 RELEASE_PASS；源码已检查，待 soak 完成后串行实跑，不与 GUI 测试并发。
- TESTS 同步断言说明。原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52。

## 2026-11-11：离屏目标共享有界网格缓存

- 修改前分类三轮正常结束，第三轮首页 220 个目标、57435 个目标缓存网格。报告 review-soak-classified-before.json 独立保留；缓存的按目标预算累乘得到实际样本支持。
- Viewport 目标改为惰性共享一个 4096 项/48 MiB 输入预算的 PrismMeshCache。弱注册表不拥有 GPU 资源，最后目标释放缓存；DrawSlot 自己的 Ref 继续保护排队网格。Surface 缓存不变，缓存预算不等同全部活跃网格/驱动内存。
- 新压力断言在旧二进制上明确失败；新引擎的 mobile 和 GL 跨目标共享/销毁/像素测试通过，mobile/separate shader-cache 积压回归通过。引擎源码构建成功，日志 review-shared-mesh-*-build.log。
- 修改后三轮 mobile/256MiB soak 已启动，尚未完成。共享缓存减少保留的实际幅度和帧率影响还需复验，未宣称增长问题全部解决。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52。

## 2026-11-11：资源增长定位到按目标累乘的缓存预算

- 分类诊断仍在同一进程运行；第一轮尚未结束时已观察到 200 个目标、29522 个目标缓存网格，retired target/texture 为 0，说明当次增长不主要由等待退休的列表解释。
- 源码核对：PrismMeshCache 的 4096 项/48 MiB 是每实例预算，每个 RenderTarget 独立持有，因此总体预算随目标数累乘；DrawSlot 的 Ref<ArrayMesh> 负责保护已排队绘制。共享有界缓存是候选改进，尚未据此宣称完整根因或修改生产淘汰行为。
- 采样中间证据保存 artifacts/review-soak-growth-localization.json；这是未完成运行的快照，不能代替最终报告。继续观察首页计数及第二、三轮变化，保留原始失败证据。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52。

## 2026-11-11：soak 资源增长分类诊断

- 扩展已有 get_texture_resource_stats 按需接口，增加每目标 owned/mesh/shader/material/slot/RD 字段及 surface mesh、retired texture 计数，并要求主线程调用。未修改缓存淘汰、纹理池预算或绘制行为。
- soak 原始逐页采样新增 resources 分类，原有样本计数、导航和清理断言不变。分类为按所有者累计，不能当作去重 GPU 对象数或字节数。
- 引擎源码构建通过（review-soak-counters-editor-build.log）；三轮分类诊断运行中。此前 58.742 FPS 对应旧测量产物，不冒充新增计数构建的性能复验。Memory 文档同步最新增长证据与旧文件名覆盖限制。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52，最后资源增长定位仍进行中。

## 2026-11-11：最终 soak 暴露运行中资源增长

- 同一个三轮 mobile/256MiB soak 进程正常完成：35 页、205 份 Java/原生样本、497 次实际进程采样，导航及退出 final_owned=0 通过；未重启或挑选最好一次结果。
- 首页资源 4869→6166→6840，静态内存约 404→578→670 MiB；第二到第三轮 68 对同页资源均增长（至少 673），22 次自然 GC。进程末半段 private OLS 约 +160 MiB/min，峰值约 5.41 GiB。不能据最终释放宣称运行中稳定。
- 保存独立 review-final-soak-growth 日志/报告，更新审查状态和验收限制。下一步定位缓存、绘制槽及纹理资源增长，暂不认定根因、不放宽断言。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：51/52，最后一项因本次新证据保持未闭环。

## 2026-11-11：最终覆盖核对与三轮 soak 复验启动

- 审查状态文档明确历史与当前边界，补齐最后截图/输入探针修复记录及剪贴板最新复验限制。原始审查 156/156，累计收尾 51/52；最后 soak 结果尚未产生。
- 当前所有已登记源码哈希匹配；未提交修改仅剩审查状态文档与 soak 入口待登记，没有清单外的 Godot/JFX 修改。性能测量记录的引擎、graphics.jar 哈希仍匹配当前产物。
- 复读 soak 脚本：采样实际引擎进程、等待退出后读取输出、严格核对每页样本数、失败终止自身子进程、释放 Process 并恢复环境；导航/清理与内存趋势结论分开。三轮 mobile/256 MiB 验证正在运行，不把启动当作通过。

## 2026-11-11：输入探针异常退出与最后输入链复核

- ImeProbe/InputCancelProbe 的初始化回调异常现在传给等待线程；等待被中断也在 finally 请求 Platform.exit，避免跳过清理。未修改生产输入逻辑或正常断言。
- mobile spaced-click IME、mobile/separate 输入取消、Glass scheduler、mobile/separate 独立窗口像素通过。两个探针的隔离副本在等待前注入中断，原生 JavaFX 下均在 15 秒内非零退出并报告 InterruptedException；这是退出路径证据，不冒充 Godot 功能验收。
- IME 文档修正旧输入记录宽度（当前 V2 为 12 doubles，window ID 索引 9），保留物理候选框与混合 DPI 未验收限制。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：50/52，剩余 soak 入口与审查状态文档。

## 2026-11-11：LCD 截图失败门禁与累计纹理回归

- 修复 LCD 重叠测试未检查 PNG 写入结果的问题，避免保存失败后使用旧基准；截图前等待新的 pre_draw/post_draw，并明确拒绝空图像。未调整像素阈值或生产渲染逻辑。
- mobile/separate 正常 LCD 两路径对照通过；隔离项目将输出指向不存在的父目录，确认退出码 1、明确 save failed、无 capture PASS。日志 review-lcd-save-failure.log。
- 排队纹理命令数/字节数边界与 viewport 参数恢复、shader-cache 旧通知积压、菜单合成点击均通过。HoverDemo 只重新编译，并核对已有物理通过日志，没有重新操作真实鼠标。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：42/52，剩余 10 项。TESTS 同步截图门禁，相关日志哈希登记于累计收尾清单。

## 2026-11-11：累计修复的 RD、窗口退出与限速验证

- 核对 16 个累计测试入口/探针/场景：LCD 资源加载、RD corpus、LCD、非法输入、缺失纹理视图、窗口立即关闭及限速所有权。未发现需再次修改的实现问题。
- 新运行通过：LCD 四组合；RD separate 非法输入五例、缺失视图恢复及 LCD；262 个 corpus 全部满足 2/255；GL/separate Runtime 32 次窗口立即关闭；mobile 的 cap/restore/override 三种限速模式。测试串行，不操作真实键鼠。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：31/52，剩余 21 个路径。日志哈希登记于 artifacts/review-cumulative-closeout.json；这些检查不替代全页面帧率或所有驱动的验证。

## 2026-11-11：累计修复的输入、采样和内存保护复核

- 核对 GodotInputPacket 及调用点、滚轮设置探针、共享采样器与探针、LRU/TabTip/剪贴板所有权组件测试、剪贴板编码和快照保护入口，共 15 个新增收尾路径；未发现需再次修改的实现问题。
- 七个对应入口重新执行通过，覆盖无符号设置边界、采样退出/容量/错误传播、LRU 分配失败回滚、COM 错误与释放、剪贴板格式/分配保护。未启动 GUI、未合成真实输入、未读写系统剪贴板。日志与哈希保存在 artifacts/review-cumulative-closeout.json。
- 原始审查已完成/总计：156/156；累计补充收尾已完成/总计：15/52，剩余 37 个路径。不将组件测试等同完整剪贴板互通或实际键盘可见性。

## 2026-11-11：历史记录边界与累计修复收尾清单

- 将历史阅读说明放在入口，为未统一标注日期的早期英文记录增加边界。保留早期未实现项、测量值与失败记录，不把它们改写成当前结果。
- 原始范围审查已完成/总计：156/156（根仓库 127/127、Godot 10/10、JFX 19/19）。已登记文件哈希与当前工作区匹配；该检查只证明内容对应，不能代替代码审查或测试。
- 累计修复继续单列收尾：当前新增/修改路径与原始审查及关联文件登记逐一对照，未覆盖项保留到 artifacts/review-cumulative-closeout.json，不因原始计数完成而忽略。
- 本轮核对四个构建/启动入口的环境恢复变更：不存在的环境变量在 finally 中删除，原有值恢复，失败不继续运行旧产物。未重新执行构建或 GUI 测试。

## 2026-11-11：验收状态与最新证据对齐

- 全文核对 acceptance-status，补充最新 58.742 / 56.542773 FPS、原生生命周期修复及限定配置的测试证据。同步物理拖动、原生 Table 对照和 Runtime 外部拖放的后续通过记录。
- 区分剪贴板历史完整通过与后续复验在写入前被保护机制拒绝；区分确定性旧完成通知复现与无截图的原始偶发异常。修正虚拟键盘可见性、历史提交状态和过时的“最新”标题，同步 review-open-items 顶部摘要。
- 本轮只修正文档及审查记录，未重新运行 Robot 或修改生产代码。git diff --check 通过。固定原始审查已完成/总计：155/156（根仓库 126/127、Godot 10/10、JFX 19/19）；剩余历史进度核对与累计修复收尾。

## 2026-11-11：测试指南入口与运行约束核对

- TESTS 全文核对，现有 scripts/test-* 入口均有说明，表中列出的选项与脚本参数声明匹配。区分免真实输入、允许失焦与性能前台要求；已有会话授权未撤销时不重复请求，但不作为其他会话永久授权。
- 同步外部 Runtime 拖放、虚拟键盘拒绝访问和 hover-demo safe 模式后续实跑记录，不扩大到其他线程模式/设备；关闭栈采样要求移除变量而不是设置 0。Glass 文档同时修正 WindowDragProbe 旧物理光标 warp 描述，当前只读光标且合成拖动。
- 本轮未新运行 GUI/Robot，仅检查脚本声明、现有日志与文档；git diff --check 通过。固定原始审查已完成/总计：154/156（根仓库 125/127、Godot 10/10、JFX 19/19）；剩余验收状态、历史进度与累计修复收尾。

## 2026-11-11：性能文档核对及当前切页复验

- 性能文档全文核对，修正共享管线淘汰生命周期、launch upcall 计数范围和旧命令示例。最新普通引擎 mobile/safe RD1/LCD1 切页通过：58.742 Pulse FPS / 56.542773 合成 FPS，68 次切换、失焦 0、资源清理通过，max 114.793 ms；不追加偶发长帧修复。
- 日志 review-final-transition-full.log，独立复算 review-final-performance-rates.json，产物哈希 review-final-performance-binaries.json。首轮采样变量错误设为 0 的启动失败单独保留，不计入性能样本。未修改生产代码或测试断言。
- 固定原始审查已完成/总计：153/156（根仓库 124/127、Godot 10/10、JFX 19/19）；剩余 TESTS、验收状态、历史进度与累计修复收尾。

## 2026-11-11：Glass 文档系统状态与验证范围更正

- 剪贴板测试说明改为当前的已知格式白名单、256 MiB 总备份上限、临时 CLIXML、序列保护恢复及成功字节验证后删除；删除旧“内容不保存到磁盘”描述。记录历史互通成功与最新未知私有格式导致复验拒绝的区别。
- 明确历史嵌入窗口章节结束位置及当前主/次级窗口路由；不再把已经连接的原生输入/光标当作未来工作，也不将继承键位映射等同所有键盘布局兼容。
- VSync 说明补齐应用限速、刷新率条件和设置恢复，移除无撕裂保证。物理拖动章节同步后续已获授权 Robot 通过日志，保留 2 倍 DPI 与非故障注入的范围限制。
- 本轮未操作剪贴板或真实键鼠，仅更新文档及审查记录；git diff --check 通过。固定原始审查已完成/总计：152/156（根仓库 123/127、Godot 10/10、JFX 19/19）；剩余 TESTS、验收状态、性能文档、历史进度及累计修复收尾。

## 2026-11-11：RD 计划与当前目标对齐

- RD 文档全文按阶段核对；顶部明确生产 OffscreenPass 与诊断探针的区别、缓存预算、提前提交边界、corpus 2/255 严格门及无设备诊断失败语义。早期每帧一次围栏是设计意向，不作为当前代码保证。
- 用户已经要求接近 60 FPS、暂不修复偶发长帧，故将旧 P95 <25ms 独立阻塞门明确保留为历史要求；功能正确性和资源生命周期验收仍保留。未改动测试阈值，也未用旧“全绿/零泄漏”证明最新构建或任意工作负载。
- 本轮仅修改文档及审查记录，git diff --check 通过。固定原始审查已完成/总计：151/156（根仓库 122/127、Godot 10/10、JFX 19/19）；剩余 5 项文档及累计修复收尾。

## 2026-11-11：Prism 文档当前契约与历史结论分离

- 对照 GodotTexturePool 与原生 ledger，将旧 64/128/256 MiB 描述更正为 Java 回收目标 512 MiB、上限 1 GiB，以及原生 live/retired 投影预算 1 GiB；不将其解释为实际进程或驱动内存占用。
- 区分默认 viewport、可选纹理代理与 RD 输出资源，说明带 RID 的不可变材质缓存和槽默认参数重置；修正当前独立 Stage 文档链接及 LCD 每节点边界说明。
- 早期“RD 不应实施”“约 44 FPS 为架构极限”等判断明确置于历史调查范围，不覆盖已经实现的 RD 路径及后续近 60 帧证据。保留当时实测值，避免用旧结果替代新构建验收。
- 本轮仅修改文档及审查记录，git diff --check 通过。固定原始审查已完成/总计：150/156（根仓库 121/127、Godot 10/10、JFX 19/19）；剩余 6 项文档及累计修复收尾。

## 2026-11-11：通信协议文档清理过时状态

- 对照 Java 编码器、C++ ledger/消费循环、V2 输入及 ScreenLayout，修正资源投影预算为 1 GiB、几何缓存默认 1024 项 / 32 MiB；区分三批队列容量与默认 16 批 / 4 ms 消费预算。
- 移除已实现 Glass/Prism、HiDPI、读回仍“待实现”的旧描述；说明输入独立唤醒、次级 Stage 使用 opcode 26、显式 GPU 读回走独立 JNI 请求。整理 opcode 25 标题位置。
- 资源说明区分 viewport 借用纹理、异步代理、RD 输出及各自缓存，并记录 RD 批次对退休纹理的引用。OLE 说明补充按需附着/成对分离、关闭回调入口与 JNI 分配失败清理。
- 本轮仅修改文档与审查记录，git diff --check 通过，未重复构建或测试。固定原始审查已完成/总计：149/156（根仓库 120/127、Godot 10/10、JFX 19/19）；剩余 7 项文档及累计修复收尾。

## 2026-11-11：Node Shader 与 Media 文档复核

- Node Shader 对照公开 Effect、Java 适配器和 GPU Filter 实现核对。区分 Java 入口拒绝与 Godot 编译时报错，补充显式 RD 开关及环境恢复示例，并说明日志名不含 RD 状态、重复运行会覆盖。
- Media 全文保留各阶段历史证据与限制；对照运行参数、双帧队列/显式纹理释放入口、1080p60 sample12/14 日志和 120 次循环分析。明确旧构建数据不是后续全部修改的即时复验，避免“当前”措辞误导。
- 本轮只调整文档，没有重新运行 GPU 或 Robot 测试。固定原始审查已完成/总计：148/156（根仓库 119/127、Godot 10/10、JFX 19/19）；剩余 8 项文档及累计修复收尾。

## 2026-11-11：原生模块说明与子模块记录核对

- native-module 补全显式 RD 和异步纹理代理两条可选路径，区分借用纹理与自有代理的释放责任；补充 Canvas 清空不能替代 RD 批次完成的资源回收边界。
- GodotView 的嵌入子窗口约束明确限定为其内部场景，不再暗示整个宿主只能有一个原生窗口。独立 Stage 描述改为保留最后发布的输出尺寸，并记录原生窗口销毁前停用 viewport 和渲染同步。移除必须先完成 stock 构建的歧义。
- AGENTS 全文、链接和所列构建/运行参数已核对，无需修改。根 gitlink 与 Godot/JFX 实际 HEAD 及固定审查终点一致；两个子模块审查记录中的当前源码哈希全部匹配。未提交修复仍保留，提交指针匹配不作为测试通过证明。
- 本轮仅修改说明与审查记录，不重复构建或操作真实键鼠。固定原始审查已完成/总计：146/156（根仓库 117/127、Godot 10/10、JFX 19/19）；剩余 10 项文档及累计修复收尾。

## 2026-11-11：架构说明与当前缓存实现对齐

- 删除 Shader 缓存“分配内部编号”“一直保留到宿主清理且无固定上限”的过时描述。当前实现按哈希定位后比较完整源码，编译缓存最多 256 项 / 16 MiB 统计数据；快捷引用在插入前清除，排队绘制单独保留所需资源。
- 区分按条目限制的顶点/参数/绑定缓存与同时受数据量限制的共享 Shader、Mesh 缓存，避免把局部预算解释为进程内存上限。明确默认视口路径、显式 RD 环境变量与 Demo 保留外部配置的行为。
- 剪贴板说明保留此前引擎完整互通通过的证据，同时说明最新修改后复测因未知私有格式保护而未完成，不能把历史结果当成最新代码完整复验。
- 本轮仅修改文档与审查记录，未重新构建或运行 Robot。固定原始审查已完成/总计：142/156（根仓库 113/127、Godot 10/10、JFX 19/19），剩余 14 项与累计修复收尾继续核对。

## 2026-11-11：宿主默认光标恢复所有权

- stop_host 原先无条件恢复默认光标，导致尚未连接 Java 应用 的诊断宿主也改写 Godot 应用设置；正常 EXIT_TREE 后析构再次调用 stop_host，还会覆盖应用新选择的光标。增加 default_cursor_state_saved：启动保存时置位，首次恢复后清除；未保存或已恢复均不再写入。
- 在现有 native_windows_test 加入未绑定宿主离树/析构的光标保留断言，在 image_cursor 加入正常 JavaFX 退出后应用重新选择光标再销毁宿主的断言。修复前两项分别明确失败（`review-cursor-ownership-before-raw.log`、`review-cursor-repeat-before-raw.log`）；前者旧夹具失败早退时尚有一个手工移出的宿主未释放，现已补齐失败清理，旧日志的该退出告警不单独归因于生产泄漏。
- 引擎顺序构建通过（`review-cursor-ownership-editor-build.log`、`review-cursor-ownership-runtime-build.log`）；mobile/separate 原生窗口测试与 Runtime 图像光标测试通过，日志 `review-cursor-ownership-after.log`、`review-cursor-repeat-runtime-after.log`。合成 viewport motion，不移动真实鼠标。Glass 和 TESTS 同步。
- 主宿主源码全文及关联入口复核完成；进度覆盖代码审查与已说明范围的验证，不是所有 OS/内存耗尽状态的穷举证明。固定原始源码审查已完成/总计：141/156（根仓库 112/127、Godot 10/10、JFX 19/19）；剩余文档、子模块指针等 15 项及累计修复收尾继续进行。

## 2026-11-11：外部拖放请求 JNI 分配异常边界

- drag_start_external 只有部分局部分配带有 bad_alloc 处理，文本/富文本字符串、路径、自定义载荷和图像缓冲区仍可能让原生异常越过 JNI。给整个入口增加统一 bad_alloc 边界；原生所有权按栈展开清理、请求不发布，Java 收到 OutOfMemoryError。JNI 局部引用在本次原生调用返回时自动释放。
- 隔离夹具使用实际函数体和模拟 JNI，注入请求对象、64 字符文本、64 字节富文本的三个分配失败位置。旧版在文本分配处退出 1；修复版三个失败均保持 dnd_pending 为空，并在同一 Runtime 上恢复分配后成功重试。日志 `review-drag-request-before.log`、`review-drag-request-after.log`，夹具 `artifacts/native-tests/drag-request-failure/`。没有声称已经逐一注入文件、自定义格式、图像所有分支或真实 JVM 堆耗尽。
- 引擎顺序构建通过（`review-drag-request-editor-build.log`、`review-drag-request-runtime-build.log`）。Runtime mobile/safe 真实 Robot 跨进程双向传输、拖动图像及取消测试通过，日志 `review-drag-request-runtime-external.log`；测试已退出。Glass 文档同步。
- 主宿主复核已推进到 JVM 初始化/启动配置，仍需继续核对启动失败与主循环。固定原始源码审查已完成/总计保持 140/156。

## 2026-11-11：屏幕信息 JNI 分配失败边界

- screen_info 原先复制原生 screens 向量时未捕获 std::bad_alloc，可能让 C++ 异常越过 JNI。现在与其他快照入口一致转换为 Java OutOfMemoryError；局部锁在异常处理前释放，正常查询路径不变。
- 使用实际函数体与模拟 JNI 的隔离夹具注入快照复制失败。旧版退出 1 并报告原生异常逃逸；修复版验证 Java 异常类型、没有尝试创建 Java 数组、锁已释放及重试返回原始三个值。源与运行入口在 `artifacts/native-tests/screen-snapshot-failure/`，日志 `review-screen-snapshot-before.log` / `review-screen-snapshot-after.log`。这不是完整 JVM 内存耗尽测试。
- 引擎顺序构建通过（`review-screen-snapshot-editor-build.log`、`review-screen-snapshot-runtime-build.log`）；mobile/separate 的 `test-screens.ps1` 屏幕枚举、元数据与窗口关联通过（`screens-mobile-separate.log`），没有修改用户显示设置。
- Glass 文档同步。主宿主 JNI 读取已推进至外部拖放请求构造部分；该部分还有字符串/图像容器分配需继续核对异常边界，主循环全文尚未完成。固定原始源码审查已完成/总计仍为 140/156。

## 2026-11-11：自定义光标入队序号事务修复

- 主宿主 JNI 部分复核发现 custom_cursor 在 deque 入队前递增 next_host_sequence；若 push_back 分配失败，关闭完成判断会等待一个从未成功入队的序号。改为 push_back 成功后递增，与普通窗口/图标命令一致。
- 从实际 custom_cursor 函数体生成隔离原生夹具，以模拟 JNI 环境和 STL 分配失败遍历队列已有 0～255 项，验证失败时队列/序号均不变、恢复分配后原序号可重试。旧版本退出 1（count=0 即暴露序号消耗）；修复版通过 256 次失败/重试。夹具在 `artifacts/native-tests/cursor-queue-transaction/`，日志 `review-cursor-queue-before.log`、`review-cursor-queue-after.log`；不是全进程内存耗尽或完整退出流程的动态测试。
- 引擎顺序构建通过：`review-cursor-queue-editor-build.log`、`review-cursor-queue-runtime-build.log`。Runtime mobile/separate 的 `test-image-cursor.ps1` 通过 13 步光标图像/热点/隐藏恢复/子窗口与退出清理；使用 Godot 合成输入，不移动真实鼠标。
- Glass 文档补充成功入队才提交序号的约束。主宿主文件全文复核仍未完成，本轮固定原始源码审查已完成/总计保持 140/156；后续继续核对 JNI 分配异常边界和主循环。

## 2026-11-11：原生窗口宿主与声明最终复核

- 完整核对 javafx_host_windows.cpp 和 javafx_host.h；关联核对 NativeWindowTransport、JavaFXNativeWindow、宿主窗口命令消费与 IME 更新。确认次级窗口 force_native、主线程应用经过队列校验的属性、交换链修改前同步、隐藏 owner 前解除 HWND 所属关系、子窗口优先销毁及 OLE 委托先注销的顺序。
- 队列有 256 条命令、64 个窗口、图标字节预算与递增身份限制；入队成功后才提交投影 owner 树。finish 禁止新命令但保留待处理项，stop 清空待处理项。窗口保持内容引用，树退出先停 viewport 更新并等待渲染完成。
- 核对 native_windows_test / native_exit 的断言与既有 mobile/separate 日志：独立 OS 窗口、超出原宿主边界、像素及资源替换、大小/显隐隔离、owner 递归销毁、12 轮父节点退出清理。没有把这些测试扩大解释为所有 Windows 创建/前台焦点失败或混合 DPI 已验证。本轮无代码修改，未重复运行未受影响测试。
- 固定原始源码审查已完成/总计：140/156（根仓库 111/127、Godot 10/10、JFX 19/19）。主宿主 cpp 全文和其余文档等 16 项仍待完成，累计新增修复保持在范围内。

## 2026-11-11：生产 RD 离屏提交与缓存最终复核

- 完整核对 javafx_rd_pass.cpp/.h：着色器管线的录制引用、哈希命中后的完整内容比较、不可变几何与 16 槽可变缓冲区、缓存淘汰前暂存未提交绘制、uniform buffer 与依赖绑定的释放、渲染线程共享中转数据同步、读回图像的 COW 所有权，以及模块退出时先释放 pass 再清理共享管线/采样器。
- 对照 RenderTarget 的输入校验、源目标持有与 pass 边界，以及 register_types 的退出调用顺序。核对已有 rd_regressions 断言实际覆盖 48 次绘制耗尽环形槽、129 个常量缓冲淘汰后重取、260 个着色器淘汰时保留另一目标的未结束绘制、输入数组修改和读回所有权、当前 pass 屏幕采样；既有 `rd-regressions-separate.log` 包含对应 PASS。本轮没有重复运行未受改动影响的测试，也没有新增生产修改。
- 同时全文复核累计新增 bounded_lru_cache.h 的插入回滚、替换、淘汰和防溢出计费。该复核不等于 GPU 分配失败或所有外部纹理视图替换时序均已动态验证；现有测试与限制保持各自范围。
- 固定原始源码审查已完成/总计：138/156（根仓库 109/127、Godot 10/10、JFX 19/19）；剩余 18 项及其他累计修复继续核对。

## 2026-11-11：RD 诊断重叠调用覆盖资源修复

- 完整核对 javafx_rd_direct.cpp/.h 及宿主入口、现有调用方。cycle_probe 原先只检查 active，没有检查 translate_probe 第一阶段后的 phase_pending，重叠调用会覆盖同一个 CycleState 的 GPU 句柄。现统一拒绝尚有对照测试等待完成的状态；接口注释明确每次成功或失败后均须 release_rd_cycle 释放已创建资源。
- 在三族着色器对照中加入真实 API 重叠调用：第一阶段后尝试 cycle 基准，要求 cycle_already_active，随后原测试的第二阶段、逐像素对照和左右预览仍通过。修复前退出 1 并报告 Pipeline/Shader/Index/Vertex/Framebuffer/Texture 泄漏（`review-rd-probe-overlap-before.log`）；修复后 mobile safe/separate 均通过，日志 `review-rd-probe-overlap-safe.log`、`review-rd-probe-overlap-separate.log`，无 ERROR 或泄漏警告。
- 引擎顺序构建通过，日志 `review-rd-probe-overlap-editor-build.log`、`review-rd-probe-overlap-runtime-build.log`。更新 TESTS、RD 历史计划的当前补充及头文件使用契约；此次修复只影响诊断探针，不改变生产逐帧渲染。未注入 GPU 分配失败，部分创建资源仍按明确调用方释放契约处理。
- 固定原始源码审查已完成/总计：136/156（根仓库 107/127、Godot 10/10、JFX 19/19）；剩余 20 项及其他累计修复继续核对。

## 2026-11-11：外部拖放辅助程序最终复核

- 完整核对 dnd_helper.cpp：STA COM 引用计数、数据查询/枚举、带边界的文本及文件列表读取、COPY 协商、窗口回调异常边界和启动/退出资源清理。补齐直接使用的 algorithm 头文件，显式转换 Windows 注册格式编号为 CLIPFORMAT，消除构建警告；无运行行为变更。
- 同时核对累计新增的 helper 生命周期测试、公共输出契约、DROPFILES 字节解析器及测试脚本。`test-dnd-helper-lifetime.cmd --asan` 重新编译并通过：101 次启动失败清理、文件列表/枚举/读取/数据/输出/效果契约、4000 个对象引用计数释放，未见 AddressSanitizer 诊断。日志 `review-dnd-helper-final-asan.log`。没有重新操作真实键鼠；前轮 Runtime 跨进程证据仍对应相同业务行为。
- .gitignore 全文复核及 check-ignore 检查完成；工具、缓存、产物被忽略，代表性源码及文档仍被跟踪。此次代码变化不改变接口或测试入口，现有 TESTS 说明仍适用。
- 固定原始源码审查已完成/总计：134/156（根仓库 105/127、Godot 10/10、JFX 19/19）。剩余 22 项和其他累计修复仍在范围内。

## 2026-11-11：OLE 回调与 JVM 销毁协调

- 确认原子 bridge_class 置空不足以保护“回调已读到桥接指针、尚未 GetEnv/AttachCurrentThread”这一窗口。改用 Runtime 持有的 UpcallState：同一互斥锁发布 VM/全局类引用/方法、保护完整回调和临时引用释放/线程脱离，并在销毁 JVM 前关闭入口。关闭后拒绝任何新调用，也消除入口字段分开发布的风险。锁不进入逐帧渲染路径。
- 模拟 JNI 回归在 GetEnv 内、附加线程前暂停调用，核对关闭入口所用锁仍被占用，释放后等待调用与关闭线程完成，再确认关闭后的调用不触碰 JNI。当前通过 `DND_JNI_SHUTDOWN_GATE_PASS`；隔离副本移除生命周期锁后明确失败（`review-dnd-gate-without-lock.log`），没有修改生产测试断言。23 点异常回归及所有原有 OLE 组件测试一并通过（`review-dnd-gate-component.log`）。
- 引擎顺序构建通过（`review-dnd-gate-editor-build.log`、`review-dnd-gate-runtime-build.log`）。真实 JVM 的 mobile/separate OLE 入站超时取消通过；Runtime mobile/safe 真实 Robot 跨进程双向拖放、拖动图像及 Escape 取消通过。保留日志 `review-dnd-gate-ole-timeout.log`、`review-dnd-gate-external-runtime.log`。这些不是所有 Windows/JVM 退出时序的穷举验证。
- 更新架构入门说明、Glass 文档、TESTS 与审查清单。固定原始源码审查已完成/总计：132/156（根仓库 103/127、Godot 10/10、JFX 19/19）；剩余 24 项和累计新增修复继续收尾。

## 2026-11-11：OLE JNI 参数构造失败清理

- 修复 windows_dnd.h 的 call_target：JNI 分配、数组写入或查找类失败后立即停止参数构造，释放已经取得的局部引用并平衡线程附加；不向 Java 回调传递部分构造的载荷。
- 模拟 JNI 覆盖两项自定义格式载荷中的 23 个失败位置，包括 Java 回调本身异常；要求异常后无额外 JNI 转换、引用清零、拒绝拖放、清除异常并脱离线程。旧函数在新测试中报告 `JNI operation executed with a pending exception`，当前版本通过。日志 `review-dnd-jni-before.log` / `review-dnd-jni-after.log`；不是实际 JVM 堆耗尽实验。
- 引擎顺序构建通过：`review-dnd-jni-editor-build.log` / `review-dnd-jni-runtime-build.log`。mobile/separate 的 OLE 注入和超时取消分别通过：`ole-inject-mobile-separate.log` / `ole-inject-mobile-separate-timeout.log`。不操作真实鼠标或系统剪贴板。
- 尚需核对 Upcall 从读取 bridge_class 到附加线程之间与关闭桥接的竞态；原子指针置空本身不提供整个调用的生命周期保护。因此 windows_dnd.h 暂不计为最终复核完成。
- 固定原始源码审查已完成/总计仍为 131/156；本轮完成上述缺陷修复，累计新增回归一并纳入收尾。

## 2026-11-11：剪贴板文件列表编码快照修复

- 原生 encode_hdrop 原先先读取 Java String[] 计算长度，分配后再次读取；并发替换数组元素可能使第二次路径更长或为 null。现在逐项取得并验证原生 UTF-16 快照，再按同一快照分配与编码，同时把路径终止符纳入总字符预算。
- 新增不访问系统剪贴板的确定性 JNI 模拟：同一数组第二次读取会返回替换路径。旧编码器失败，新编码器只读取一次并保留原路径和双 NUL；已有句柄、锁、枚举、图像布局检查一并通过。日志 `review-clipboard-path-before.log`、`review-clipboard-path-after.log`。
- 引擎顺序构建通过，日志 `review-clipboard-path-editor-build.log`、`review-clipboard-path-runtime-build.log`。当前剪贴板私有格式保护保持不变，没有清空或执行格式交换；这次证据为编码器回归及构建，不冒充完整系统互操作复测。
- glass-godot 文档同步。固定原始源码审查已完成/总计：131/156（根仓库 102/127、Godot 10/10、JFX 19/19），累计新增修复另行收尾。

## 2026-11-11：帧协议与资源事务最终核对

- 完整核对 frame_protocol.h 及 frame_protocol_test.cpp，并确认 JNI 先复制 Java 字节、解码，再进入队列。临时解码结果和投影资源账本保证无效批次不消耗序列号、不部分登记/释放资源。
- 核对纹理类型、代次、区域、反馈采样、窗口持有、场景缩放/输入、几何引用、背压及三个时钟。finish 保留已接收命令，stop 才丢弃。直接账本预算测试有意绕过线格式尺寸约束，不能把它们当作合法协议输入示例。
- `test-protocol.cmd` 重新编译并通过资源事务与 10000 帧并发 FIFO 检查。没有新增生产修改；几何总量仍依赖 Java 编码器缓存预算，GeometryLedger 本身不是按字节计费的内存限制器。
- 固定原始源码审查已完成/总计：130/156（根仓库 101/127、Godot 10/10、JFX 19/19）；剩余 26 项及累计新增修复继续核对。

## 2026-11-11：剪贴板探针失败退出清理

- ClipboardProbe 的启动超时/等待中断原先可能跳过窗口关闭和 Platform.exit；现统一在 finally 中关闭，FX 清理等待有界且可取消，保留原始异常并恢复中断状态。PASS 移至清理成功后。
- 当前探针编译通过。完整测试在备份阶段因 Chromium 私有格式被保护逻辑拒绝，未执行剪贴板写入；不绕过保护，不把此次拒绝当成互操作回归失败。日志 `review-clipboard-finally.log`，先前完整互操作记录仍属此前版本。
- 从当前清理代码生成无剪贴板访问的独立故障夹具：创建临时窗口后注入中断异常，确认窗口关闭、中断恢复、进程退出 1 且无 PASS。日志 `review-clipboard-cleanup-interruption.log`；夹具位于 `artifacts/native-tests/clipboard-cleanup/`。这验证新清理路径，不代替格式交换验证。
- 完整核对 ClipboardSnapshot 的总量预算、枚举错误、句柄交接、写后序列号及带锁恢复保护。固定原始源码审查已完成/总计：128/156（根仓库 99/127、Godot 10/10、JFX 19/19）；累计新增修复仍需收尾。

## 2026-11-11：悬停与编码探针核对、拖放测试读边界修复

- 完整核对 HoverDemo、HoverFlicker、RenderCommandValidation 和 dnd_drag_image_test。悬停 Java 计数属于观察数据，包装脚本同时要求宿主像素门槛；离线编码器反射夹具不能替代 GPU 批次边界验证。
- 原生拖放测试在比较返回的 HGLOBAL 内容前增加长度检查，防止被测实现返回短块时由测试本身越界读取。`test-dnd-drag-image.cmd` 重新编译运行通过，含分配失败清理、COM 输出约定及 8×6/偏移 5,3 的拖动图像检查；未操作真实鼠标。
- 固定原始源码审查已完成/总计：126/156（根仓库 97/127、Godot 10/10、JFX 19/19），剩余 30 项及累计新增修复收尾。测试入口与验收条件未变，相关 TESTS 说明仍适用。

## 2026-11-11：原生表格对照补齐实际滚动门槛

- NativeTableDrag 原先只检查 96 次 Pulse，可能在没有滚动表格时报告成功；水平模式也未筛选水平可滚动容器。现在匹配可滚动目标，并要求所选轴实际累计位移至少 200 像素，报告增加 displaced_px。
- 在已获授权下串行运行原生 Windows Glass/D3D 对照：纵向 62.475 Pulse FPS、1581 像素；横向 62.530 Pulse FPS、867 像素，各 96 个间隔、正常退出。日志 `review-native-table-displacement-v.log`、`review-native-table-displacement-h.log`。不是 Godot 性能验收，不调整偶发长帧。
- 同时完整核对 VfxTableScrollProbe：它已有 200 像素门槛、模式区分、采样器及输入清理；未新增修改。固定原始源码审查已完成/总计：122/156（根仓库 93/127、Godot 10/10、JFX 19/19）；累计新增修复另行收尾，不能据此宣布整个目标完成。

## 2026-11-11：十一项 Java 探针最终源码核对

- 核对 VirtualKeyboard、WindowDrag、ResizeCursor、MenuClick、ScrollWheel、ImagePoolReuse、SceneTexture、MediaAudio、OleInject、PhysicalDrag、ExternalDrag 探针的完整源码和相关宿主判定边界。
- 重点检查超时取消、线程停止、输入释放、鼠标恢复、异常保留、资源关闭及成功标记的条件；本轮未发现新的必改项。WindowDrag/ResizeCursor 的主要几何或光标断言由宿主场景负责，Java PASS 不能单独替代；Media 静音测试和虚拟键盘调用测试的能力限制保留。
- 当前哈希和逐项结论记录在 `artifacts/review-root-final-audit.json`，累计 91/127 项，剩余 36 项及累计新增修复。本轮未重复执行已通过的 GUI/Robot 测试，未修改生产行为或放宽断言。

## 2026-11-11：RenderTarget 最终核对与音频样本工具收尾修复

- 完整核对 RenderTarget 的两种后端、源目标持有、异步 RID 回调、备用对象回调同步、材质碰撞与淘汰、网格缓存及绘制槽位；关联检查已有 churn、碰撞和 RD ownership 回归记录，没有新增生产修改。
- 音频样本生成器现在仅在 MFStartup 成功后配对 MFShutdown，正常收尾检查关闭返回值，避免失败时仍打印 PASS；补齐标准库头文件。MSVC 重新编译、MP3/AIFF 生成通过，不存在输出目录返回 1。
- 日志 `review-audio-fixture-lifecycle-build.log`、`review-audio-fixture-lifecycle-mp3.log`、`review-audio-fixture-lifecycle-aiff.log`、`review-audio-fixture-lifecycle-failure.log`。未注入系统 MFStartup/MFShutdown 失败，未重新播放音频；本轮验证仅覆盖生成器。
- 固定原始根仓库核对累计 80/127 项，剩余 47 项及累计新增修复。测试入口和音频格式未改变，现有 TESTS 命令仍适用。

## 2026-11-11：Surface、SceneView 与历史窗口合成器最终核对

- 完整核对 Surface 实现及声明：材质状态分段、网格持有、纹理版本替换、RD 批次提交、区域上传回调及退出释放；关联核对 SceneView 的对象 ID、父节点先销毁、输入解码边界和场景纹理转移路径。
- 历史 WindowSurface 合成器与宿主的原生 Stage 分支分别检查。修正两处容易误解的源码注释：GodotView 内的场景弹窗可以嵌入，但 JavaFX 次级 Stage 是独立原生窗口。现有 GodotView 和历史窗口文档已正确描述此区别。
- 当前源码核对累计 77/127 项，剩余 50 项及累计新增修复。关联的 scene-lifetime safe/separate 和 queued-texture-update 批次边界记录仍按各自范围有效；本轮只有注释修改，不重新构建或重复 GUI 验证。

## 2026-11-11：剩余九个渲染场景及三个原生辅助头文件核对

- 完整核对悬停、Stage、网格变换、RD 翻译、Surface、RenderTarget、Shader 与缓存场景；没有发现新的必改项。Stage 的等待以像素变化为终态，不能与只数旧完成通知的等待混为一谈。
- 生成 Shader 的完整性由包装脚本比较 D3D 变体集合及 SDK 内容，场景自身的数量输出不能独立证明完整覆盖。普通网格变换通过也不能代替可选缓存压力档。
- 核对 custom-format、TabTip 和 Prism mesh 辅助实现及相关调用点；缓存使用完整内容比较和 COW 快照，预算仅计输入数据，虚拟键盘仍保留系统可见性限制。
- 逐项源码结论与哈希写入 `artifacts/review-root-final-audit.json`，累计 73/127 项、剩余 54 项及累计新增修复。本轮未修改生产行为或重新运行 GUI 测试。

## 2026-11-11：RD 诊断及回归场景源码核对

- 核对 rd_spike、rd_direct_spike、rd_lcd_spike、rd_corpus_spike 和 rd_regressions 的判定及资源生命周期。视口成本探针只输出数据，不具有像素验收门槛；TESTS 已明确。
- 直接 RD 桥接预览也需等待新的 pre-draw/post-draw 边界，已补齐；mobile/safe 和 mobile/separate 均通过，日志 `review-direct-fresh-draw-safe.log`、`review-direct-fresh-draw-separate.log`。
- 没有改生产路径、像素阈值或重试规则；其他已有通过记录不重复运行。

## 2026-11-11：性能报告的最大值与 GPU 瞬时值修正

- 切页基准错误地对 max_draw_sync_us 做首尾相减，改为 lifetime_max_draw_sync_us；切页和表格的可选 GPU 最近测量值也改为 last_offscreen_gpu_us/last_window_gpu_us，不再输出无意义差值。普通累计计数和 FPS 公式不变。
- 普通 RD1/LCD1、mobile/safe 68 次切页通过：59.184 Pulse FPS / 56.353 宿主合成 FPS，失焦 0、清理通过，证据 `review-transition-max-counter-full.log`。
- PROFILE_COMMANDS/GPU_TIMING 诊断下切页及表格都通过，并独立解析三份 JSON，确认新字段存在且非负、旧字段不再出现。日志 `review-transition-gauges-full.log`、`review-table-gauges-full.log`。诊断运行不用于替代普通性能测量。
- 未改生产代码、动画负载或长帧策略，TESTS、性能和验收文档同步更新。

## 2026-11-11：十个输入与系统接口场景主体最终核对

- 完整复读原始十个输入/系统场景的就绪、超时、覆盖和退出断言，未发现新增修改项。明确区分场景主体、Java 探针及系统可见性的证明范围。
- 哈希和逐项结论写入 `review-root-final-audit.json`，累计 52/127 项、剩余 75 项；此前 19 个场景资源哈希仍匹配。
- 本轮没有执行 GUI、Robot 或剪贴板操作，没有改变测试阈值和生产代码；根仓库 diff 检查通过。

## 2026-11-11：原始测试入口及场景资源最终核对

- 完整复读原始 18 个入口的失败判定、模式选择及环境恢复，未发现新增修改项；17 个 PowerShell 解析通过，CMD 按源码核对。
- 检查原始 19 个 tscn 的单 Script 引用、目标存在和 ID 绑定，全部成立；脚本主体行为单独审查，不以绑定检查替代。
- 结果与哈希合并到 `review-root-final-audit.json`，累计 42/127 项，尚余 85 项及累计新增修复。本轮未启动 GUI、Robot 或剪贴板交换，diff 检查通过。

## 2026-11-11：根仓库 Shader 与卸载五文件最终源码复核

- 完整复读 Shader 改写、转换、对应头文件和模块注册卸载，并追踪编译及失败释放调用。未发现新增修改项。
- 创建 `review-root-final-audit.json`，固定这五个原始路径的源码哈希、结论和适用证据；其余 122 个原始路径保留待最终核对，累计新增修复也仍在范围内。
- 复核已有 LRU、safe/separate 全部 262 项 corpus、LCD 及带旧通知注入的 shader-cache 结果；本轮没有重跑 GPU 或修改生产代码，不扩大成任意 Shader/所有 GPU 分配失败的保证。

## 2026-11-11：JFX 其余十文件最终源码审查

- 完成 Glass/Application/剪贴板/Bridge/编码器剩余十个原始路径的当前差异及调用边界复核，未发现新增修改项；同时确认此前九个文件的源码哈希未变化。
- `review-jfx-final-audit.json` 现逐路径匹配原始全部 19 项，pending 列表为空。记录对应的 IME 顺序、输入协议、调度退出、剪贴板转换与精确恢复、OLE 超时取消等既有证据。
- 只关闭 JFX 原始路径源码审查，不代表根仓库、累计新增修复或全部系统行为完成；虚拟键盘系统拒绝访问的限制保留。此轮没有重跑测试或修改生产代码，JFX diff 检查通过。

## 2026-11-11：JFX 渲染及图像池九文件最终源码审查快照

- 完成九个原始渲染/图像池路径相对基线的当前差异复核，核对调制批次、LCD 采样边界、失效候选解锁及纹理预算，没有新增生产修改。
- `review-jfx-final-audit.json` 固定逐文件哈希和人工结论，记录既有适用测试日志；其余十个 Glass/Bridge/编码器路径明确保留为待最终核对。
- 此轮是源码与已有证据核对，没有重跑 GUI、改变性能配置或宣称所有失败路径已覆盖。JFX diff 检查通过。

## 2026-11-11：Godot 原始十文件最终源码审查快照

- 逐一复读原始十文件相对基线的当前差异及 GL 关联头文件；核对正常退出时渲染服务器先于显示服务器结束。未发现新增需修改项。
- 固定源码哈希、人工结论及既有窗口立即关闭/OLE/光标日志哈希到 `review-godot-final-audit.json`，原始十文件集合完全一致。后续按内容变化重新打开对应项，不重复已完成的这一组源码审查。
- 日志是已执行测试的复核，本轮没有重新启动 GUI。记录明确不等于所有故障注入、驱动兼容性或全目标完成，也不以哈希自动推断构建来源。Godot diff 检查通过。

## 2026-11-11：旧完成通知导致像素误判的确定性复现

- 在第 274 轮末尾排队八次旧画面绘制、同步读回并积压通知；旧等待方式第 275 轮确实读取上一轮红色，期望为蓝色，截图已保留。相同注入下修正版本完成全部 305 轮。
- 对照日志 `review-shader-queued-notice-old.log`、`review-shader-queued-notice-fresh.log`；原始历史偶发失败没有像素截图，仍不能断言事件同因。
- 将注入保留为 `test-shader-cache.ps1 -Renderer mobile -RenderThread separate -QueuedNotifications`，默认关闭，独立日志并恢复环境；不改变生产代码或性能配置。
- 正式回归入口通过，注入标记与最终 PASS 齐全，日志 `shader-cache-mobile-separate-queued-notifications.log`；包装器日志 `review-shader-queued-notice-wrapper.log`。diff 检查通过。

## 2026-11-11：调度测试失败路径的线程清理

- 复读 GodotEventLoop、GodotPulseScheduler、GodotTimer 及应用停止调用，发现 GlassSchedulerProbe 的独立事件循环只有成功路径释放闩锁；中途超时/断言会遗留非守护线程。
- 独立循环的 stop、闩锁释放和两条测试线程 join 移入 finally，正常路径额外确认同步调用者已退出。生产调度器未改动。
- `test-glass-scheduler.ps1` 通过，完整日志 `review-scheduler-cleanup.log`。从当前测试块生成独立探针，在 held 和 queued 两个位置注入断言，均无新增非守护线程存活；日志 `review-scheduler-failure-cleanup-0.log`、`-1.log`，源码位于 `artifacts/native-tests/scheduler-cleanup/`。

## 2026-11-11：SceneView 输入边界和生命周期复核

- 复读 SceneView 完整实现、Surface 持有/迁移/释放路径及 Java/C++ 场景输入校验；未发现需要改写的生产代码。审查清单补充具体来源与验证范围。
- 当前引擎 mobile/safe、mobile/separate 各 100 轮场景生命周期测试通过，包含父树先销毁而包装对象存活的场景；证据 `review-scene-lifetime-safe.log`、`review-scene-lifetime-separate.log`。
- 直接合成输入不是 Java 编码端或焦点取消的动态验收；未扩大通过结论，未改变性能配置。

## 2026-11-11：同类 GPU 夹具的绘制等待边界

- 检查其他 frame_post_draw 使用点，修正 Surface、生成 Shader、RenderTarget、网格变换及 RD corpus/LCD/translate 的固定轮数等待：每次先等新 pre-draw，再等完成通知。没有增加等待轮数、放宽像素阈值或加入重试。
- 前四个场景 mobile/safe 与 mobile/separate 共八次通过，日志 `review-fresh-draw-<场景>-<线程模式>.log`。普通网格测试未启用缓存压力，不能据此扩大验证结论。
- RD corpus/LCD/translate 的两种线程模式另六次通过，corpus 两次均为 exact=262、edge=0、deferred=0、failed=0；同一日志命名中的场景为 `rd_corpus_spike`、`rd_lcd_spike`、`rd_translate_spike`。本轮合计 14 次 GPU 场景运行通过。
- 宿主状态轮询与信号诊断连接未批量改动；它们的判断条件与像素读取不同。生产代码与性能配置未修改。

## 2026-11-11：shader-cache 等待旧通知的测试同步缺口

- 独立 separate 探针排队八次绘制并同步读回，随后等待三次完成通知，绘制提交计数仍为 9；旧通知确实可满足原测试的整个等待。证据 `review-post-draw-notification-probe.log`。
- 每轮增加等待新的 pre-draw 后，三轮等待使提交计数从 9 增至 13。shader-cache 压力段采用此顺序，保持三轮和原像素判定，不改生产代码、不增加失败重试。
- 此项是已证明的夹具同步修正；历史第 275 轮失败的因果关系仍未证明，不能宣布生产问题已闭环。
- 修正后的 mobile/safe、mobile/separate 完整 shader-cache 测试均通过；日志 `review-shader-fresh-draw-safe.log`、`review-shader-fresh-draw-separate.log`，对应包装器日志以 `-full.log` 结尾。根仓库及 Godot/JFX 的 diff 检查通过。

## 2026-11-11：separate 像素异常的六次有界复现

- mobile/separate shader-cache 六次串行运行全部通过；证据 `review-pixel-repro-1-full.log` 至 `review-pixel-repro-6-full.log`。没有修改生产代码、等待次数或像素断言。
- 确认 separate 的绘制后通知通过延迟调用返回主线程，但尚未证明旧通知导致此前异常，继续保留单次历史失败为未闭环项。
- 更正审查文档中仍把剪贴板完整互操作描述为“未验证”的旧段落，与已完成的引擎交换及精确恢复结果保持一致。

## 2026-11-11：剪贴板阻塞解除与发布序列号修复

- 第三次恢复后只读复核成功，发现四种可备份格式，遂按原“所有测试”授权执行交换。双侧功能 PASS，但首次恢复被序列号保护拒绝；保护未被关闭。
- 逐字节核对当前已发布测试格式后，在当前序列号保护下恢复保存的原内容，恢复校验成功。最初备份 `clipboard-86803022f16245eda0f940b7e240b05f.ready.backup.clixml` 仍保留；未把内容写入日志。
- 有原始备份/精确恢复的独立实验确认 WriteRaw 返回关闭前序列号 101，CloseClipboard 后变成 103，见 `review-clipboard-close-sequence.json`。现发布后重新加锁并验证所有者仍为测试窗口，再记录序列号；外部改写、未知格式和最终序列号不匹配仍拒绝。
- 包装器修复 Invoke 直接抛错时未显示备份路径的问题。guard 检查通过；mobile 引擎完整交换及原始字节恢复都通过，证据 `review-clipboard-postclose-*.log`。此项不再因等待准备回复而阻塞。
- TESTS、审查清单和验收状态同步更新。separate 单次历史像素失败及其他既有验收限制保持原状态。

## 2026-11-11：当前产物 RD 性能与外层命令状态核对

- 当前引擎（原生剪贴板枚举修复后）运行 RD1/LCD1、mobile/safe 切页基准：68 次、1625 Pulse，59.386 Pulse FPS；1616 次呈现 / 28516.743ms = 56.668 FPS，未失焦、资源清理通过。p99=25.469ms、max=108.733ms；不处理偶发长帧。
- 外层 shell 曾返回 1，但测试脚本已通过自身原生退出码/日志门禁。排查排除了诊断 stderr 假设，最小复现确认最后在 finally 中 Remove-Item 不存在的环境变量（SilentlyContinue）会留下失败状态。记录原状态与原因，没有重跑或隐藏失败记录。
- 逐页加权复算、宿主计数复算及当前 Editor/graphics.jar 哈希见 `review-current-rd-transition-rates.json`，完整日志 `review-current-rd-transition-full.log`。验收文档与审查入口同步更新，未修改生产代码。

## 2026-11-11：窗口销毁与输入取消当前证据

- 复核 owned window 递归释放、拖放委托解绑、渲染等待和 held_buttons 清理顺序；失焦先清除按住状态和 IME 组合，再入事件队列，当前未发现新的状态遗留问题。
- 当前引擎的 mobile/separate 输入取消回归通过，包含模态窗口切换、丢失鼠标/键盘释放、触摸取消及下一次正常动作。日志 `review-current-input-cancel-full.log`；Godot 合成输入，不操作真实设备。
- 未修改生产代码。共享剪贴板互操作仍等待用户准备回复，不把该局部限制当作其他审查工作的停止理由。

## 2026-11-11：原生自定义剪贴板格式枚举错误传播

- 同类核对发现生产 custom_formats 也把 Win32 枚举失败当作结束。现由 next_format 区分结束与错误，错误通过 JNI 抛出 IllegalStateException，RAII 关闭剪贴板，避免静默返回部分列表。
- 原生组件以 mock API 覆盖初始/中途失败、正常空/结束和成功结果伴随旧错误码，CLIPBOARD_ENUMERATION_FAILURE_PASS 与所有权检查通过；日志 `review-native-clipboard-enumeration.log`。未访问真实剪贴板或修改 OLE 的不同枚举契约。
- 引擎顺序构建成功，日志 `review-native-clipboard-editor-build.log`、`review-native-clipboard-runtime-build.log`。完整互操作仍等待用户准备完成的回复，不绕过快照保护。
- TESTS、Glass 说明和审查记录已同步。

## 2026-11-11：剪贴板快照拒绝不完整枚举

- 检查发现 Capture 没有区分 EnumClipboardFormats 的正常结束与系统错误。根据 Microsoft 接口契约补齐 SetLastError 与终止时错误检查，失败不返回部分备份、不进入测试写入。
- 委托注入覆盖正常空/完整列表，以及首项/中途失败；同时验证原生声明保留错误码。与原预算、分配失败和保护检查一起通过，日志 `review-clipboard-enumeration-guard.log`。没有访问真实剪贴板或宣称 Windows 故障动态覆盖。
- 已请求用户自行保留现有剪贴板并准备普通文本，以继续完整互操作；当前尚未收到准备完成回复，不绕过私有格式保护。TESTS 与审查说明已更新。

## 2026-11-11：原始脚本入口的失败恢复补查

- 检查 window-drag、scroll-wheel、resize-cursor、render-command-validation 当前入口的编译/启动门禁与环境恢复；与固定原始脚本变化对照。
- 对上述四个及 virtual-keyboard、image-pool-reuse，注入不存在的 JDK，覆盖原环境变量缺失/已有值两种状态。12 次均拒绝启动编译器，工作目录与所检查环境变量正确恢复，没有运行 GUI 或键鼠。证据 `review-wrapper-compiler-failure.json`，不扩大为所有运行时失败路径覆盖。
- 原始范围全部 17 个 PowerShell 文件当前解析通过，哈希及结果保存 `review-current-original-wrapper-syntax.json`；这不代表完整功能验收。未发现本轮需要修改的脚本问题，未修改生产代码。

## 2026-11-10：当前验收入口与审查范围整理

- 重新读取实际基准日志，修正 acceptance-status 开头仍将 57.553/54.325 称为最新的旧描述。分别列出 RD 59.006/55.946 与 Viewport 58.700/56.133，并明确这些测量早于后续非默认同步备用路径修复，不冒充所有当前配置的测试。
- review-open-items 顶部集中列出尚未闭环的 separate 单次像素失败、剪贴板互操作保护、虚拟键盘可见性与全范围完成核对；已修复问题、历史授权撤回/命令拒绝与更广项目验收限制分开记录。
- 从 Git 再次推导固定原始路径集合，与原始范围索引逐项比较。结果保存 `artifacts/logs/review-current-scope-check.json`；集合匹配只证明范围未漂移，不证明源码或测试全部完成。
- 本轮未修改代码或重复执行已通过的 GUI 测试。

## 2026-11-10：跨线程回调所有权复核

- 按当前源代码逐项检查模块的 RenderingServer 派发与帧信号：RID/上传数据按值持有、共享 staging/借用参数在返回前 sync、退出树断开信号。审查清单新增路径与完成边界表；未发现另一处与上一轮备用路径相同的问题。
- 最终 Runtime 的 RD separate 回归通过，包括读回和顶点输入所有权、uniform 退休、pipeline 淘汰、屏幕采样与待绘制源复制。日志 `artifacts/logs/review-render-callback-runtime-full.log`；不把它扩大为所有调度/设备失败保证。
- 本轮未修改生产代码，默认 separate 的单次历史像素失败仍独立保留。

## 2026-11-10：修复 separate 备用路径的迟到对象回调

- 检查发现关闭 ASYNC_PASS_FENCE 且 PASS_SYNC_INTERVAL=0 时，绑定目标对象的回调仍异步入队，却提前读取耗时并返回。新增 128 次提交后立即释放目标，在修复前捕获 Invalid Object id；原 100 轮复制检查的 PASS 不足以掩盖该 ERROR。
- separate 备用路径现在每次返回前完成队列同步，保证对象和成员耗时访问安全；默认异步 RID 路径不增加逐次等待，safe 模式仍保留原节流策略。
- 引擎构建成功。mobile/separate 的 ASYNC_PASS_FENCE=0 和 1、GL/separate 的 0，均通过新增生命周期检查和原像素/资源门禁。证据 `artifacts/logs/review-sync-fallback-*`；修改诊断环境变量后均恢复。
- 同步协议说明、TESTS 和审查清单已更新。这是独立的非默认路径错误，尚无证据解释早前默认 separate 压力检查的单次像素失败。

## 2026-11-10：碰撞条目删除与最终 Media 回归

- shader-cache 碰撞夹具新增删除边界：销毁仅第一组引用的纹理并确认对象释放，第二组连续两轮像素正确、材质缓存由两份降为一份，防止主位置空缺后重复插入。mobile/safe 的该检查及原有完整压力检查通过，日志 `review-material-collision-retire-full.log`。
- 在不可变材质修复后的最终 Runtime 上显式开启 RID 材质缓存，运行 mobile、24 轮 Media `-Providers`。24 个 owned 样本均为 31，退出为 0，AAC 注册检查通过。完整证据 `review-immutable-material-churn-full.log`、`review-immutable-material-churn-aac.log`；没有禁用缓存、强制 GC 或放宽断言。
- 本轮仅扩展回归检查与记录，未修改生产代码；separate 的早期单次像素失败仍未定位，不被本次不同测试覆盖取代。

## 2026-11-10：独立项目缓存与淘汰生命周期复核

- 为 separate 像素间歇失败创建独立临时项目，只复制项目配置与 shader-cache 场景/脚本，未复制或清除原项目缓存。碰撞专项与 305 轮压力检查全部通过，日志 `artifacts/logs/review-cold-cache.log`，路径见 `review-cold-cache-project.txt`；未清理驱动缓存，不能称为完全冷启动。
- 复读 instance uniform 名缓存及调用者：查询返回 COW Vector 所有权，主线程路径使用，没有把缓存条目引用跨淘汰保存；未得到将首次像素失败归因于该缓存的证据。
- 不基于猜测添加生产 fence 或放宽等待/像素阈值，原首次失败与待定位状态继续保留。本轮未修改生产代码。

## 2026-11-10：separate 压力检查间歇失败的诊断补充

- 针对前次第 275 轮像素失败，三个独立进程顺序运行 mobile/separate shader-cache 均完整通过，证据为 `artifacts/logs/review-separate-cache-{1,2,3}-full.log`；未把重复通过当作根因修复。
- 检查 Viewport 自动更新、离屏命令 FIFO 和 shader pipeline 路径，现有证据不足以归因于测试同步或生产渲染缺陷。
- 在原像素失败分支保存同一次读回的图片，文件名含 PID/轮次并报告保存错误；不增加等待、重试或颜色容差。GDScript `--check-only` 通过，日志 `review-cache-diagnostic-parse.log`。此分支尚无新的真实失败截图，不能声称定位完成。

## 2026-11-10：修复 sampler 参数哈希碰撞串色

- 新增实际 Dictionary 哈希碰撞夹具：96 个存活纹理目标，搜索三采样器组合；修复前两次绘制的左侧颜色被第二组覆盖，完整证据 `review-material-collision-before-full.log`。
- 移除就地改写已发布材质的 patch 路径。缓存以完整 shader/参数身份复用，碰撞另存条目；主键未命中时查找已有碰撞条目，保留上一轮失效 sampler 回收。旧 MATERIAL_PATCH 诊断开关不再影响实现。
- 引擎顺序源码构建成功。mobile/safe 与 GL/safe shader-cache 完整通过，包含三轮碰撞像素/两份材质复用、原有 305 轮压力门禁。mobile/separate 首次碰撞通过、后续第 275 轮旧像素门禁失败；增加实际颜色诊断后重跑通过，仍保留第一次失败为待定位间歇现象，不宣称已解决。
- Viewport（RD_DIRECT=0、LCD_SCREEN=1）mobile/safe 的 68 次切页：58.700 Pulse FPS、56.133 宿主呈现 FPS，未失焦、资源清理通过。日志 `review-material-collision-transition-full.log`，不以单次波动声称提速。
- 相关构建及测试证据均为 `artifacts/logs/review-material-collision-*`；TESTS、Prism 和审查清单同步更新。未改业务功能或放宽断言。

## 2026-11-10：修复 Media 循环暴露的材质缓存滞留

- 当前 Runtime 视频控制与 WAV/MP3/AIFF 解码控制通过；TabTip 错误传播/COM 释放组件测试通过。未将这些等同实际听音或系统键盘显示验收。
- Media churn 原断言在第 11 轮失败：owned 从 31 持续增至 51，纹理内存不变。关闭 RID 缓存的诊断对照 24 轮通过、owned=29，证据保存在 `review-final-media-churn-runtime-full.log` 和 `review-media-churn-cache-diagnostic-full.log`。
- 修复 `JavaFXRenderTarget::acquire_material`：缓存未命中时清理已失效采样器的条目及顺序索引，材质沿原 pass 资源路径延迟释放；不再等缓存满才回收。另消除 map erase 后继续读取旧条目指针的风险。未禁用交付缓存、未放宽测试阈值。
- 引擎顺序构建成功。缓存显式开启的 mobile Runtime 24 轮 `-Providers` 通过，owned=31、退出=0；shader 和 mesh-transform 缓存压力像素检查通过。日志 `review-material-retirement-*.log` 位于 `artifacts/logs/`。
- 显式 RD_DIRECT=0、LCD_SCREEN=1 的 mobile/safe 切页 68 次：58.457 Pulse FPS、56.008 宿主呈现 FPS，未失焦，资源清理通过。与之前 RD 结果配置不同，不作因果性能提升声明；偶发长帧仍按用户要求暂不处理。

## 2026-11-10：系统接口补测与结果范围修正

- `test-clipboard.ps1 -Renderer mobile` 在备份检查阶段遇到 Chromium 私有格式而拒绝运行；未进入测试写入，不清空或绕过快照保护。记录 `artifacts/logs/review-final-clipboard.log`，本次不算剪贴板互操作通过。
- `test-virtual-keyboard.ps1` 当前产物运行确认 Java 调用、宿主 tick 推进、探针清理通过，但原生关闭请求返回 HRESULT -2147024891（拒绝访问）；未验证系统键盘显示或关闭。
- 修正虚拟键盘脚本的结果提示，直接输出原生 touch keyboard 警告，并明确成功范围是调用与存活检查。修改后重跑结果符合预期；未改变生产接口或放宽断言。
- 审查清单中旧的最终基准拒绝记录标明为历史，当前 FPS 更新为上一轮实际测量的 59.006 / 55.946。

## 2026-11-10：重新授权后的最终产物与 Robot 回归

- 用户重新明确允许 Robot 及其他测试，本轮 GUI 测试串行执行，没有修改生产代码或放宽断言。
- 最终引擎的 mobile/safe 切页基准，显式 RD_DIRECT=1、LCD_SCREEN=1，关闭采样/性能诊断变量：68 次切页、1613 Pulse，59.006 Pulse FPS；1602 次宿主呈现 / 28634.649ms = 55.946 FPS；unfocused=0，资源清理通过。p99=51.433ms、max=117.829ms；按用户要求不处理偶发长帧。日志 `review-final-transition-full.log`，独立复算 `review-final-transition-rates.json`，均位于 `artifacts/logs/`。
- mobile/separate 引擎的 Robot、外部 OLE 拖放、hover-flicker -Robot、physical-drag -Robot、文件对话框通过。悬停 FusionButton 有效 HOLD/GAP 样本 583/222，资源清零；文件对话框完成六用例。
- mobile/safe 的表格水平 Robot 拖动通过：96 Pulse、60.004 FPS、位移 867px、unfocused_ticks=0；这是有界物理输入回归，不是长期性能保证。完整日志 `review-final-table-robot-full.log`。
- mobile/safe Runtime 的 Robot 和外部 OLE 拖放也通过，覆盖最终原生产物的正常跨进程路径。日志 `robot-mobile-safe-runtime.log` 和 `drag-drop-external-mobile-safe-runtime.log`。
- 这些结果覆盖本轮测试配置，不能替代混合 DPI、真实音频/A-V 同步或全部剪贴板格式验收；宿主呈现计数不等于显示器实际扫描输出。

## 2026-11-10：最终产物核对与测量拒绝记录

- 原始 127/10/19 路径集合与固定索引完全匹配，13 个范围内交付产物哈希匹配；WebKit 依用户要求排除，VFX 无本轮修改。
- 最终引擎、Media SDK 构建成功记录与三仓库 diff 检查通过。
- 自动审批拒绝补跑最终构建的 RD 切页测量，未启动、未绕过或伪称新 FPS；整体完成未宣布，已有测量保留原版本/配置限定。

## 2026-11-10：原始场景绑定与证据定位

- 19 个原始场景的单节点/脚本引用和绑定逐项检查通过，保存 review-original-scenes.json。
- 核对 RD corpus/LCD/回归的后端与像素门禁，复读已有成功日志；没有重新运行 GPU 或物理测试。
- 将功能名记录补齐到场景/协议测试路径，建立 156 路径的证据定位辅助文件；明确它不证明整体完成。三仓库 diff --check 通过。

## 2026-11-10：完成核对的范围澄清与交互夹具审查

- 核对 clipboard、drag-drop、external-drag、menu-click 场景与 Java 观察器，当前 SDK 编译 ClipboardProbe/MenuClickProbe 通过；未运行这些交互测试。
- 修正剪贴板重试注释中过强的占用归因；原内容断言和重试期限不变。
- 验收文档区分历史项目要求与本轮固定范围代码审查，并明确项目待办不构成 Robot 授权；保留物理与兼容性缺口，尚不宣称整体完成。

## 2026-11-10：生产拖放读取的异常释放与 COM 边界

- 组件测试复现生产 read_hglobal 分配失败后锁/介质未释放；修复 scoped 解锁、介质及格式枚举器释放。
- TargetHandler 捕获分配/长度异常，清空旧载荷并拒绝拖放，避免异常穿过 COM 或落入另一消费者。
- 故障组件、引擎构建和 mobile/separate 正常 OLE 注入通过；没有真实键鼠或系统剪贴板写入。
- 补齐 Surface 原始缓存/变换/资源路径的源码对应。测试 helper 的历史修复不再混同为生产读取路径已覆盖。

## 2026-11-10：原始包装脚本审查对应

- 补齐九个原始测试入口的源码检查记录，区分退出码/标记门禁、环境恢复、可选或环境选择的 Robot 模式与剪贴板恢复保护。
- 八个 PowerShell 文件解析通过；没有运行这些脚本的 GUI、Robot 或剪贴板主体，未将解析成功写成运行通过。
- 本组未发现需新增修改的问题，原有实际运行证据及限制保持分开记录。

## 2026-11-10：桥接声明与输入队列核对

- 新 SDK 的 36 个 native 方法与当前 C++ JNI 注册表逐项匹配，两个反向回调描述符一致；结果保存为 review-jni-signatures.json。
- 追踪独立输入唤醒的参数、计数、条件变量与停止路径；协议测试重新编译通过，含输入 tick 和 10000 帧并发门禁。
- 未发现需要新增修改的问题，未调用 Robot/剪贴板接口；签名核对不替代系统行为或 C++ ABI 验证。

## 2026-11-10：剪贴板图片预检避免无效大额复制

- Java 图片转 ARGB 原在分配后才由 native 拒绝超预算尺寸；现分配前应用相同的 16384 单边和 64 MiB（含 DIB 头）上限。
- Media SDK 重建通过；32 MiB 堆下图片边界预检与既有编码测试通过，无系统剪贴板访问。
- 更新 Glass 文档及 TESTS，区分额外 staging 复制预算与调用方已存在的 Pixels 缓冲；未改变格式能力或运行 Robot。

## 2026-11-10：Prism 批次状态原始差异复核

- 对照 GodotContext/Graphics/Shader 原始差异，追踪纹理释放前 flush、状态快照、调制切换、LCD pass 与加载失败路径；未发现需新增修改的问题。
- 当前 SDK 的源码缓存、LCD 加载边界、编码器验证三项离线测试通过；结果不替代 GPU 生命周期和 Media 像素门禁。
- 补齐原始文件到源码检查的对应，未运行 GUI 或 Robot。

## 2026-11-10：基础 GPU 测试补齐几何缓存释放断言

- surface/shader 退出测试原只检查不包含几何缓存的资源计数，现同时要求缓存归零；surface 覆盖 100 次生命周期，clear 命令仍应保留可复用几何。
- mobile 基础绘制和生成 Shader 测试通过（262 份源码），保留原有 GPU 像素门禁。没有修改渲染行为或运行 Robot。
- 对照原始差异补齐 surface/shader/render_target/vfx_demo 四路径的审查对应，区分默认路径与可选 hover 读回诊断。

## 2026-11-10：音频原始路径与失败输出核对

- 核对 MediaAudioProbe、make_audio_fixture 和 test-media-audio 的控制断言、资源释放与失败退出；补齐原始路径对应，本组未发现需新增修改的问题。
- 当前 SDK 重新编译音频探针通过；既有夹具程序在无父目录的 AIFF 输出上正确失败且不打印 PASS。
- 复读已有三格式播放日志；本次没有重新播放、运行 Robot 或验证实际听音。

## 2026-11-10：切页基准清理与当前 Viewport 验证

- TaskManager 终止失败时也尝试注销全局钩子；宿主退出要求资源归零，包装器增加对应门禁及输出目录创建。
- mobile/safe Viewport 配置完成 68 次切页，58.464 pulse FPS / 55.786 宿主合成 FPS，失焦 0；最慢表格切页 36.603 FPS，不能代表每页稳定 60。
- 双侧 PASS 与资源清理通过；没有运行 Robot，未修改 VFX 动画或统计算法。与此前显式 RD 配置分开记录。

## 2026-11-10：着色器转换与共享缓存审查对应

- 补齐 shader_rewrite、shader_translate 各自头文件/实现及 register_types 的原始路径审查记录，追踪 target/pass 调用和退出清理顺序。
- 当前 LRU 组件重新编译运行通过；复读已有 Runtime RD 像素门禁，明确区分离线内存检查和历史 GPU 证据。
- 本组未发现需要新增修改的问题；未运行 Robot、GUI 或系统剪贴板测试，未扩大为通用 shader 语法或全部 GPU 失败场景验收。

## 2026-11-10：审查记录状态与光标测试路径核对

- 将已修复的滚轮打包问题改为历史记录，清除“现已授权”歧义，明确 Robot 授权已撤回。
- 为原始 resize-cursor 四文件补齐路径到源码检查的对应；当前 SDK 编译通过，复读已有 Runtime 日志确认双侧 PASS。没有重新运行 GUI 或 Robot。
- 这组核对不等于全部原始改动已完成审查，也不增加物理设备或 DPI 验收结论。

## 2026-11-10：剪贴板测试快照内存边界

- 快照从单格式限制补齐为 256 MiB 总预算，发布/恢复前校验输入，保持私有格式与序列号保护。
- 原生块交接给 Dictionary 失败时释放，格式键列表提前到清空剪贴板之前分配。
- 离线预算、既有 guard 和临时原生块异常释放测试通过；未读取或改写系统剪贴板，未运行 Robot。

## 2026-11-10：虚拟键盘探针退出与 tick 判定

- 为请求和清理使用有期限的 FX 任务，失败路径也尝试释放输入、关闭 Stage 并退出；PASS 等清理完成后输出。
- 宿主活跃检查要求 tick 实际前进，宿主移除后资源归零。增加 -CompileOnly 供不操作系统键盘的验证。
- 编译与 TABTIP_RESULT_TEST_PASS 原生模拟测试通过；完整系统键盘流程和 FX 超时故障未实跑，文档明确区分。未操作 Robot 或系统剪贴板。

## 2026-11-10：悬停探针退出与资源门禁

- 为可选 Robot 路径补齐原光标保存/恢复，保持 FX 线程执行与既有超时清理。未运行 Robot。
- 合成宿主在移除节点后检查资源清零，包装器要求清理标记并创建输出目录；TESTS 补正 VFX 依赖及悬停描述。
- mobile/separate 合成模式通过八个普通按钮阶段、六轮 Fusion 像素及资源清理；原像素阈值不变，不作为 FPS 测量。

## 2026-11-10：原始范围索引与最新综合切页验证

- 固定原始根仓库/Godot/JFX 的 127/10/19 路径索引及当前文件哈希；索引仅定位，不作整体审查通过证明。
- 最新源码 68 次 VFX 切页通过，1627 pulse、失焦 0，57.553 pulse FPS / 54.325 宿主合成 FPS，独立复算一致；旧 59.125/56.547 标为历史。
- 修正 native-module 的 VSync 保护/恢复遗漏与过强因果表述；整理架构中绘制数据说明的位置。未运行 Robot。

## 2026-11-10：RD 脚本几何入口拒绝非法输入

- 复现 RD 直接调用静默忽略非零 Z 并绘制；补齐形状、精确长度、有限值、65536 顶点上限及 Z=0 检查。
- 新负向脚本逐一核对五类错误及合法 pass 恢复，safe/separate 通过；完整 RD 与 Java 跨批次回归通过。
- 引擎构建成功，测试与架构说明同步。未运行 Robot，不扩展 3D 支持。

## 2026-11-10：环境恢复误判纠正与系统接口审查

- 实测区分 `$env:NAME=$null`（正确删除）与 SetEnvironmentVariable 的 null（当前留下空字符串），撤回对直接赋值的错误缺陷判断和冗余分支；既有 API 修复保留。
- 核对窗口合成诊断、custom format、TabTip 与 Godot DropTarget 原始差异并记录范围；未运行物理输入或系统触摸键盘。
- 滚轮脚本补齐输出目录，mobile/separate 三格约 120 px 合成验证及不存在的 JDK 变量恢复通过。

## 2026-11-10：RD 输入复制与顶点打包

- 去掉 RD 入口对同类型数组的深拷贝，打包循环一次获取可写指针，并以字节复制避免 float 指针别名写入。
- 新增提交前改写调用方数组的像素检查，验证原位置、两组 UV 和颜色保持；separate 引擎、safe Runtime 全 RD 回归及 Java 跨批次验证通过。
- 引擎构建与文档检查完成。没有运行 Robot，没有据减少复制宣称新 FPS。

## 2026-11-10：常量解码减少临时堆分配

- 宿主标量和向量解码使用固定四元素局部存储，数组常量仍用原 PackedArray 表示；保留原位模式与参数类型。
- 协议边界拒绝检查及完整 10000 并发帧测试通过，实际 shader 的 float/int 1–4 分量八类像素检查通过。
- 引擎构建与 Runtime RD Effect 对照通过。测试说明和审查记录同步；本轮不报告新的 FPS 提升，未运行 Robot。

## 2026-11-10：水平负载长测及参数分流分配优化

- 表格测试新增 -Sweeps（3..30），延长到 960 脉冲后确认性能差距不限于启动阶段。保留完整间隔、轴位移、资源检查。
- 宿主实例参数分流直接查缓存名称，去掉每条命令的临时集合与全键数组；复制值后才删除字典条目。
- 引擎构建、默认值/参数删除像素、Runtime RD Effect 与长负载回归通过。修复版平均 53.707 FPS，未据单次数据宣称确定提速或稳定 60。
- 未运行 Robot，未针对偶发长帧修改运行时。相关测试、性能及审查文档同步。

## 2026-11-10：水平表格滚动测试修正

- horizontal 模式选择实际横向可滚动的视口，direct/real 分别沿 X 轴驱动；两轴都验证所选轴位移，修正原有跳过断言及纵向假覆盖。
- mobile/safe 水平 direct/real 各 1500 px、垂直 direct 2325 px，通过资源与结束检查。显式 RD 水平 direct 亦通过。
- 记录不同渲染路径的短样本 FPS，未把 51.819 平均 FPS 的 RD 结果写成稳定 60。未运行 Robot，未修改 VFX 业务代码。

## 2026-11-10：表格探针清理及 Robot 授权撤回

- 补齐表格探针停止计时器、释放按键、恢复光标及独立清理全局服务的路径；包装脚本创建输出目录，环境恢复保留正确的直接赋值。
- direct/separate 与 real/safe 合成测试通过。实际 Robot 运行受到用户操作干扰，不作缺陷或性能证据。
- 用户明确要求停止 Robot，持续授权已撤回。后续真实输入须重新获准；水平断言缺口及短样本性能结果记入审查清单。

## 2026-11-10：原始子模块差异与窗口拖动验证

- 核对 Godot 输入 quiet setter、主循环/渲染诊断计数，以及 JFX 调度、纹理池限额、LCD 分支的原始差异，逐项范围记录到 review-open-items.md。
- 窗口拖动脚本补齐输出目录（此前对直接环境变量赋值的缺陷判断已撤回）；mobile/separate、GL/safe 合成拖动通过，平均约 2.13/2.00 宿主帧。停止调度回归 50 次通过。
- TESTS.md 修正滞后测量与实际门禁的区别。本轮无运行时代码变更，不新增 FPS 或物理设备验收结论。

## 2026-11-10：取消鼠标保持状态及槽默认值回归

- 失焦、窗口销毁、最后一个按钮释放时清理宿主保持状态；取消测试故意省略原窗口释放，旧版意外拖动已复现，新版 mobile/separate、GL/safe 通过。
- 修正此前槽默认值处理引入的空值错误和同步查询：参数减少或着色器切换时重建绘制对象，其余继续复用。mobile safe/separate 四阶段像素检查通过。
- 引擎构建成功；mobile/separate 合成及真实 Robot 拖动通过，测试结束已恢复键鼠使用。测试说明、架构和审查记录同步。本轮不新增 FPS 结论。

## 2026-11-10：当前状态文档一致性复核

- 对照 Windows clipboard 实现、真实外部拖放日志和 Runtime 输入日志，修正架构中“OLE 尚未接通”“图片/文件剪贴板待实现”的旧结论，并明确剪贴板最新阻塞来自私有格式备份保护。
- 验收摘要将旧 FPS 标为较早测量，补充后续真实拖放证据；审查清单修正 Runtime 输入尚未运行的旧描述。
- 整理 TESTS.md 的空标题及测试说明错位。仅文档修改，未重新操作系统剪贴板或宣称新增运行验收。

## 2026-11-10：VSync 回退状态恢复

- 复现 Java 结束后仍遗留回退设置；宿主记录自己安装的 FPS，完成/失败/停止时仅撤销仍与其相同的设置，保留应用后改的不同值。
- 引擎构建、mobile cap/restore/override、GL restore 通过。实际触发回退后恢复 0 FPS/VSync 开启，另测应用改为 47 FPS 后仍保留。
- 性能、测试、架构及审查文档同步；同值外部写入无法由值比较区分，失败与中途停止未单独故障注入。

## 2026-11-10：VSync 回退尊重显式 FPS 限制

- 复现应用设置 30 FPS 被自动改为 60、VSync 被关闭；回退现跳过非零显式帧率限制，切换前重查 VSync，校验刷新率有限值。
- 引擎构建、mobile/GL 限速保护用例通过。修正日志、性能文档与头文件中未经普遍证明的 FIFO 因果/无撕裂表述。
- 新测试和限制写入 TESTS.md；回退触发后的全局状态恢复仍待核对，不据局部修复宣称已完成。

## 2026-11-10：修复绘制槽实例参数残留

- 实际 Java→宿主→Viewport 路径复现省略 tint 后仍使用旧红色。复用槽记录参数名，省略项恢复当前着色器默认值，并跟踪已写入的默认值以正确处理后续换 shader。
- 引擎构建成功，safe/separate 显式值→默认值→新 shader 默认值三阶段像素及资源检查通过；原 separate RD 批次边界仍通过。
- 新增 -ViewportState 用法与证据说明，更新初学者架构文档；未禁用实例参数优化或修改 VFX 行为。

## 2026-11-10：离屏绘制槽改用顺序游标

- 消除每次绘制从零扫描 used 槽的累计平方开销；独立网格槽游标在清理时复位，保留矩形/复制的独立层级顺序。
- 引擎构建、GL 缓存压力、100 轮目标复制生命周期、GL/separate Effect 均通过，日志见 review-open-items.md。
- 初学者架构说明同步；未改变测试入口或资源预算，不据源码优化声明实测 FPS 增幅。

## 2026-11-10：修复离屏网格被缓存淘汰后提前销毁

- 扩展 mesh-transform 压力用例到离屏 target，旧引擎复现空 mesh 和红色区域丢失。持久 DrawSlot 增加强引用，命令清空时释放；不复用槽时由本轮资源列表持有。
- 引擎构建通过，GL/mobile 压力、GL 无槽复用、Runtime mobile/separate Effect 回归通过；失败与修复证据见 review-open-items.md。
- 同步初学者架构说明和 TESTS.md；未提高缓存预算，未改 VFX 行为或追加长帧修复。

## 2026-11-10：Shader 状态与 LCD 原始接口审查

- 对照原始基线核对 GodotShader、GodotGraphics、BaseShaderGraphics 和 GodotContext 关联状态路径，记录快照数组/映射所有权、纹理句柄捕获和 LCD 逐节点采样边界。
- 当前 SDK 源码缓存与 LCD 加载回归通过，日志 review-shader-snapshot-cache.log、review-shader-lcd-load-current.log。不将源码检查扩大为全部销毁竞态动态验证。
- 本轮未发现需要新增行为修改的结论；审查记录已更新，架构与测试入口无需改变。

## 2026-11-10：字节边界 GPU 集成验证

- -BatchBoundary 增加真实 4 MiB 字节上限场景，使用合法纹理上传与裁剪命令，明确确认不是先碰到命令数上限。
- mobile/safe 和 separate 下，命令数/字节两种自动提交的颜色及裁剪像素检查、原纹理版本检查与退出资源归零均通过。
- 更新 TESTS.md 和审查记录中此前未覆盖字节边界的限制；本轮仅测试改动，生产架构无需更新。

## 2026-11-10：命令数边界 GPU 集成验证

- 排队纹理更新夹具增加 -BatchBoundary：合法裁剪命令填满批次，绘制必须自动提交，GPU 逐像素检查跨批次颜色/裁剪状态。
- mobile/separate 边界与 mobile/safe 默认模式均通过；补充宿主移除后资源归零检查。TESTS.md 和审查证据同步。
- 仅新增测试模式，没有生产行为变更，架构说明无需更新；4 MiB 字节边界的实际宿主像素验证未在本轮覆盖。

## 2026-11-10：批次修复后的 VFX 性能复验

- 当前源码 Editor/Media SDK，mobile/safe RD1/LCD1，68 次切换、1625 pulse、失焦 0：59.125 pulse FPS / 56.547 宿主合成 FPS，独立复算一致。
- 核对宿主取批次不重置 shader/clip/target 状态；未将普通 VFX 回归当作强制批次边界像素验证。完整日志 review-batch-boundary-vfx-full.log。
- 更新最新性能记录；偶发长帧仍不修复，不把单轮波动归因于上轮修改。

## 2026-11-10：修复四边形批次预留长度

- 旧 SDK 复现接近批次上限时合法绘制抛错：清屏和普通绘制调用端均少算完整 QUADS 长度。容量检查统一移入编码器，完整绘制/缓存引用/淘汰都检查字节及命令数限制。
- Media SDK 重建成功，新增边界/恰好容纳检查、mobile/separate Effect 和 LCD 两模式回归通过，证据详见 review-open-items.md。
- 协议格式和资源上限未变；TESTS.md、协议文档同步，架构组件分工未变。

## 2026-11-10：Java 编码器缓存及失败状态审查

- 对照 GodotRenderCommands 缓存所有权、碰撞比较、淘汰和提交失败路径；未改运行实现。
- 补齐外线程写入拒绝、拥有者继续可用，以及无 JNI 注册时 submit Error 后禁止复用的负向测试；与已有缓存验证一并通过，日志 render-command-validation.log。
- 测试脚本创建输出目录；TESTS.md 和审查记录同步。没有注入真实宿主背压/停止，架构文档无需变动。

## 2026-11-10：协议跨资源表事务回归

- 核对 frame_protocol.h 原始几何协议、引用校验及双资源表投影提交；补齐纹理分配/几何注册/释放后因非法引用失败的回滚测试，验证无入队、不消耗序号、原序号可重试。
- test-protocol.cmd（含 10000 帧并发）及 mobile 网格缓存压力回归通过，日志 review-resource-transaction.log、mesh-transform-mobile-cache-pressure.log。
- 仅新增测试，没有改变运行协议；TESTS.md 和审查记录同步，架构说明无需变动。

## 2026-11-10：原始宿主声明与场景资源边界审查

- 将 host.h、host_windows.cpp、scene_view.cpp、rd_direct.h 的原始变更与当前调用/释放路径逐项核对，证据及未覆盖边界记入 review-open-items.md；另核对 .gitignore 原始改动。
- 修正 RD 诊断头文件过时的生产路径说明；没有改运行行为，无需重新构建。现有架构说明无需因该注释更正而改变。
- 当前 GodotView mobile/separate Transform 回归通过，日志 godot-view-mobile-separate-transform.log；未将此扩大为全部异常资源路径验证。

## 2026-11-10：快速拖动夹具缩放与清理

- PhysicalDragProbe 真实输入恢复原光标，释放/恢复/销毁分别尝试，错误仍使测试失败。合成 GDScript 按初始窗口实际尺寸换算，移除固定 2 倍坐标；脚本补齐输出目录创建。
- mobile/separate 合成与 Robot、GL/safe 合成通过；真实位移 Y=-14、缩放 740×576、手势连续和资源归零均符合。日志 physical_drag-mobile-separate-robot.log。
- 当前设备为 2 倍 DPI，未动态切换缩放或注入清理失败。TESTS.md 和审查记录同步；仅测试夹具改动，架构文档无需更新。

## 2026-11-10：原生表格拖动对照清理与实跑

- NativeTableDrag 补齐原鼠标位置恢复；launch/后台任务清理失败统一保存，仍尝试注销全局监听器，存在错误不输出 PASS。
- 使用当前源码 SDK，Win Glass、请求 D3D，水平/垂直各 96 间隔通过，分别为 61.873/61.882 pulse FPS；日志 review-native-table-drag-h.log、review-native-table-drag-v.log。
- 此为原生对照的采样和正常退出验证，无表格像素/位移断言，未动态注入清理失败。TESTS.md 和 frame-benchmark.md 同步；没有运行时架构变动。

## 2026-11-10：授权后的真实悬停与跨进程拖放

- mobile/safe HoverDemo 八轮通过，enters=8、flickers=0，稳定像素 hold=861、gap=511；日志 hover-demo-mobile-safe.log。
- mobile/separate 外部拖放首次运行发现辅助日志独占读取回归，改用 _wfsopen/_SH_DENYWR，允许脚本读取同时拒绝其他写入者。重跑通过三阶段出站和一次入站、载荷与拖动图像断言；日志 drag-drop-external-mobile-separate.log。
- 辅助程序 ASan 回归通过 101 次启动失败及 4000 个对象生命周期，日志 review-dnd-helper-sharing-asan.log。仅修改测试辅助日志共享，运行时架构无需更新。

## 2026-11-10：其他脚本环境恢复

- 修正九个脚本将保存的 null 恢复成空字符串的问题，明确移除原本不存在的变量。
- 对实际清理分支验证不存在、空字符串和普通值，共 27 项通过；日志 review-script-env-restoration.log。未据此声称构建/GUI 主体全部重跑，运行时架构不变。
- 用户已授权后续真实键鼠 Robot 测试，不再将等待同意列为本次审查的阻塞项。

## 2026-11-10：音频夹具编译与环境恢复

- test-media-audio.ps1 每轮调用只编译一次 MP3/AIFF 夹具，补齐目录创建；工具链环境在编译后立即恢复，失败时仍由 finally 保护。
- 精确区分不存在与空字符串环境变量，修复 PowerShell/.NET 空值转换导致的恢复偏差。
- mobile 三格式音频通过；正常和模拟编译器失败均验证环境/工作目录恢复，证据见 review-open-items.md。未修改运行时、音频阈值或 VFX 行为，架构说明无需更新。

## 2026-11-10：手动悬停日志报告准确性

- 修正固定 16.7 ms 换算、跨缺帧判跳变及原生失败仍正常返回；静态亮度不再称为已证实冻结，FX 队列空等不直接断言宿主饥饿。
- 增加 -LogPath 只读分析入口，离线连续/缺帧/大编号/错误与环境恢复检查通过，日志 review-hover-log-checks.log。未运行交互 Demo；实时非零退出分支未做动态注入。
- TESTS.md 和 frame-benchmark.md 同步；不改变渲染架构，不处理用户暂缓的偶发长帧。

## 2026-11-10：Godot 原始十文件审查证据

- 对照 Godot 基线与当前工作树逐项核对原始十文件，以及 GL 管理器关联头文件。记录诊断开关、计数含义、窗口表保护、OLE 注册发布顺序与验证限制到 review-open-items.md。
- 当前引擎在 GL separate 各 32 轮窗口立即关闭通过；mobile/separate OLE 合成注入通过。日志 review-godot-scope-close-editor.log、review-godot-scope-close-runtime.log、review-godot-scope-ole.log。
- 本轮未发现需新增行为修改的结论；没有将组件/短循环结果扩大为真实输入、系统失败或所有驱动的证明。未修改代码，架构说明无需更新。

## 2026-11-10：修复 IME 完成时的输入重入

- 定位到 GodotView 完成组合文本后调用通用 drainInput，提前分派队列中的 release。改为当前窗口 IME/Unicode 提交的专用读取，其他输入等待当前回调返回；没有禁止合法模态循环。
- ImeProbe 新增 PR 顺序断言及 IME_MOUSE_ORDER_PASS，默认同帧输入保留。Media SDK 构建通过；mobile/GL 默认 IME、mobile/separate 模态与输入取消回归全部通过。
- 日志与验证边界见 review-open-items.md；架构、IME 文档和 TESTS.md 同步。未操作真实输入设备，未声明物理 IME 验收。

## 2026-11-10：无损滚轮设置与输入记录 V2

- 宿主/Java 改用 12 字段窗口输入，分别传递两轴 UINT32 设置，保留分页 -1；消除旧水平 1000 截断和有符号打包溢出。JNI 入口改名以拒绝不同记录版本；旧九字段低层探针仍保留。
- 修复 IME chunk 长度与路由中九字段截断，复用出队记录减少一次复制。引擎/Media SDK 重建通过。
- scroll-settings 边界与非法值测试、mobile/separate 滚轮、Runtime resize-cursor 通过。IME DPI 坐标已修正，但默认同帧点击发现真实重入顺序问题，保留默认失败夹具；显式 -SpacedClick 隔离模式通过。
- 失败证据、完整日志和下一项重入修复要求见 review-open-items.md。协议、架构及测试文档同步；未修改系统设置或操作真实输入设备。

## 2026-11-10：Glass 拖放缓存与原始变更复核

- GodotDragClipboard 去掉第二份静态缓存，遵循 Clipboard.get/remove 管理的共享对象生命周期；不操作系统剪贴板。此为源码证实的所有权简化，新增临时 assistant 场景旧版亦通过，没有宣称动态复现丢数据。
- Media SDK 源码构建成功；普通/Timeout OLE、Glass scheduler、mobile/separate 合成滚轮均通过，日志与逐项限制见 review-open-items.md。
- 记录滚轮特殊值/整数打包边界为下一项待修；未运行真实输入设备测试。缓存归属内部修正不改变架构分工，architecture.md 无需更新。

## 2026-11-10：基础渲染钩子逐项复核

- 对照原始 JFX 差异复核 GodotTexturePool、BaseContext、GlyphCache、BaseShaderContext，并记录调用方、默认后端行为和验证限制到 review-open-items.md。
- 修正两处源码注释：纹理池构造参数是回收目标与硬上限；目标切换计数包含窗口和相机/深度变化，不等于离屏 pass 或显示帧。
- 当前 SDK 的 `test-lcd-overlap.ps1 -RenderThread separate` 两种 LCD 模式回归通过（review-jfx-core-lcd.log）；无新的 FPS 结论。此次仅注释与文档修改，无需重新构建；架构分工未变。

## 2026-11-10：OLE 注入测试的失败清理

- OleInjectProbe 保留首个 Throwable，启动/Drop 回调失败传回主线程；等待失败仍通过 finally 请求关窗/Platform.exit，清理等待有界并保留中断状态。
- 宿主不再在 Drop 拒绝时立即终止 JVM，等待 Java 终态；成功路径显式移除宿主并断言资源归零。脚本要求双侧完成标记。
- mobile/separate 普通和 Timeout 通过（review-ole-inject-cleanup.log、review-ole-inject-cleanup-timeout.log）。错误载荷期望复现提前停止打断清理（review-ole-inject-negative.log）；修正后负向测试退出 1、无 PASS/清理中断（review-ole-inject-negative-cleanup.log）。临时测试类已恢复。
- 没有物理输入，未替代外部拖放验收；仅测试生命周期改变，architecture.md 无需更新。

## 2026-11-10：图像池失效候选解锁

- ImagePool.checkOut 在发现已加锁候选失效后显式 unlock，再移除池引用；核对 PrTexture/BaseTexture/ManagedResource，isLost 不负责解锁。
- ImagePoolReuseProbe 加入真实锁计数和两种遍历方向的失效候选优先场景；覆盖有效候选 checkout/checkIn 锁配对、再次复用及无额外分配。包装脚本补齐输出目录创建。
- 修复前失败证据：review-image-pool-lock-before-detail.log；源码 Media SDK 构建成功（review-image-pool-jfx-build.log、jfx-media-native.log），修复后 FIFO/LIFO 均 PASS（review-image-pool-lock-after.log）。
- mobile/separate Effect 回归通过（review-image-pool-effects.log、effects-mobile-separate.log）。未做真实设备丢失注入，不宣称帧率提升；偶发长帧仍不处理。内部锁配对不改变架构分工，architecture.md 无需修改。

## 2026-11-10：缩放光标测试坐标

- resize_cursor.gd 将 400×300 逻辑场景的圆心和后续偏移换算到实际窗口像素，避免高 DPI 下偏离透明调整大小把手；中心点击采用浮点坐标。
- test-resize-cursor.ps1 先创建日志/Java 编译输出目录，TESTS.md 补齐 Runtime 参数与合成输入说明。
- mobile/separate、GL/safe 均通过悬停/离开、后续移动光标保持、双侧 PASS 和宿主资源归零；日志 review-resize-cursor-mobile.log、review-resize-cursor-gl.log 及其指向的完整日志。
- 没有改变系统 DPI 或操作真实输入设备；不据此宣称分数 DPI 和 Runtime 变体已复验。测试坐标修正不改变宿主架构，architecture.md 无需修改。

## 2026-11-10：生产拖放对象与 helper 的 COM 输出

- 两者 GetCanonicalFormatEtc 原来只清空 ptd，却返回 SAMEFORMATETC，其他输出字段未初始化；现复制输入后清空设备指针，空指针明确失败。不支持订阅时清空连接编号和枚举器输出。
- 实现依据 Microsoft GetCanonicalFormatEtc 的 device-independent 指引，链接见 glass-godot.md。共享测试同时检查生产 DataObject 与 helper，包含别名和失败输出。
- `test-dnd-drag-image.cmd` 和 `test-dnd-helper-lifetime.cmd --asan` 通过；日志 `artifacts/logs/review-dnd-output.log`、`artifacts/logs/review-dnd-helper-output-asan.log`。无真实输入操作；未替代跨进程拖放验收。
- Godot 引擎源码增量构建均通过（日志 review-dnd-output-editor-build.log、review-dnd-output-runtime-build.log）。架构分工不变，architecture.md 无需修改。

## 2026-11-10：helper 文件列表读取边界

- 移除首项 MAX_PATH 固定缓冲区，复用有界 DROPFILES 解析器；读取完整首项并统计全部文件。空列表单独验证双终止符，保留未提供格式时的 files=-1。
- 对文件介质限制 16 MiB、列表 4096 项、单项 32767 字符；损坏数据和 GetData 错误明确失败，Drop 失败保持 NONE。资源使用原有介质/锁 RAII。
- `test-dnd-helper-lifetime.cmd --asan` 全部通过，新增 FILES 门禁覆盖长路径、ANSI、多字节对齐边界、非法偏移/终止符、空列表和分配失败；日志 `artifacts/logs/review-dnd-helper-files-asan.log`。
- 无真实文件访问或物理输入。只修改测试 helper，宿主架构和公开 API 不变，architecture.md 无需变更。

## 2026-11-10：外部拖放 helper 启动清理

- 用统一生命周期对象回收日志、OLE、窗口类/画刷、窗口及拖放目标；参数不足在打开日志前拒绝。
- 源端窗口回调用 COM 智能指针管理对象，分配异常与 DoDragDrop 失败明确退出 1；GetMessage 的 -1 不再作为普通消息处理。
- `test-dnd-helper-lifetime.cmd --asan` 通过；日志 `artifacts/logs/review-dnd-helper-startup-asan.log`。注册冲突在窗口创建前触发，101 次失败检查 GDI 数量、OLE 配对和日志关闭，回调首处分配失败检查退出 1；已有五组组件门禁继续通过。
- 未操作真实鼠标键盘；尚未动态验证正常窗口退出、实际拖放和消息循环系统错误。架构和公开 API 未改变，无需修改 architecture.md。

# Progress — history through 2026-11-10

## 2026-11-10：实现重审——helper 拖放效果不能超出源端许可

- HelperDropTarget 的 DragEnter/Drop 原来只凭文本返回 COPY，忽略源端输入效果掩码；DragOver 不保留格式接受状态，可能给没有文本的对象返回 COPY。现将目标 COPY 能力与源端掩码取交集，DragEnter 记录格式接受状态，DragLeave/Drop 清除；补齐 effect/object 空参数处理。
- 组件测试覆盖 NONE/MOVE/LINK/COPY|MOVE，进入/悬停/放入、缺文本、离开后的悬停以及空参数；ASan 下 DND_HELPER_EFFECT_PASS 及已有 READ/DATA/ENUMERATION/4000 生命周期门禁全部通过，日志 review-dnd-helper-effect-asan.log。
- 没有窗口、系统剪贴板内容或真实鼠标操作；生产拖放模块未变，外部物理验收仍未重跑。TESTS/未闭环清单同步，diff --check 通过。

## 2026-11-10：实现重审——helper 数据查询与读取一致性

- QueryGetData 原来只检查格式名，可对 GetData 拒绝的介质/内容类型返回成功，且两者均未检查 lindex/目标设备。GetData 现在先清输出并调用 QueryGetData，统一返回 DV_E_DVASPECT/TYMED/LINDEX/DVTARGETDEVICE；保留查询不分配负载。
- 文件列表构造 bad_alloc/length_error 转为 E_OUTOFMEMORY，失败输出保持空介质；空文件列表补齐 DROPFILES 要求的双 NUL 终止符。正常文字/URL/自定义格式和文件负载不变。
- 扩展实际 helper 组件测试：无效字段的查询/读取一致、输出清空、Query 不触发分配、文件列表分配失败、正常 DragQueryFile 计数与空列表结束符。ASan 下 DND_HELPER_DATA_PASS、READ、ENUMERATION 和 4000 次生命周期门禁全部通过；日志 review-dnd-helper-data-asan.log。
- 未启动窗口/修改系统剪贴板/操作真实输入；启动清理、窗口回调和效果掩码仍待继续检查。TESTS/未闭环清单同步，diff --check 通过。

## 2026-11-10：实现重审——helper 外部文本边界及介质 RAII

- read_text 原来从外部 HGLOBAL 直接构造以 NUL 结尾的 wstring，缺终止符会越过分配；read_text/read_bytes 构造字符串抛异常会跳过 Unlock/ReleaseStgMedium。增加不可复制的介质/锁 RAII，按 GlobalSize 限制扫描、16 MiB 大小上限、终止符及格式检查。
- Drop 先清空 effect，检查空参数，转换 bad_alloc 为 E_OUTOFMEMORY、格式异常为 DV_E_FORMATETC；文件列表介质也交由 RAII 持有，覆盖结果字符串构造失败。没有修改系统剪贴板或生产拖放实现。
- 实际 helper 类的进程内伪 IDataObject 测试覆盖未终止 UTF-16/UTF-8、两种字符串的分配失败、正常读取和空参数。自定义 pUnkForRelease 检查释放恰好一次且锁计数为零；ASan 下 DND_HELPER_READ_PASS、枚举器门禁及 4000 次引用生命周期全部通过，日志 review-dnd-helper-read-asan.log。
- 当前未验证启动失败清理及其他 COM/窗口回调异常，继续保留未闭环清单；真实跨进程鼠标运行未进行。TESTS 更新、diff --check 通过。

## 2026-11-10：实现重审——helper 格式枚举器契约与 OOM

- HelperFormatEnumerator::Skip 原来恰好跳至末尾也返回 S_FALSE；改为比较实际跳过数与请求数，避免先加后截断。Next 先清 fetched 并验证参数，count 非 1 时缺 fetched 返回 E_POINTER，不推进游标。
- Clone 先清空输出，捕获 new/格式数组复制的 bad_alloc 并返回 E_OUTOFMEMORY；EnumFormatEtc 同样转换枚举列表构建分配失败，不让 C++ 异常越过这两个 COM 边界。
- 扩展 test-dnd-helper-lifetime.cmd：Next 参数失败后仍读到首项、精确 Skip/末尾/Reset、Clone 保持游标；注入 Clone 两处分配失败及 EnumFormatEtc 每个分配点直到成功，检查 HRESULT 和空输出。ASan 测试 DND_HELPER_ENUMERATION_PASS 与原有 4000 对象生命周期均通过，日志 review-dnd-helper-enumeration-asan.log。
- 不创建窗口、不操作鼠标或剪贴板内容；其他 helper 数据读取和启动失败路径仍在未闭环清单，不宣称整个 helper 已完成。TESTS 同步，diff --check 通过。

## 2026-11-10：实现重审——外部拖放 helper Release 释放后访问

- HelperFormatEnumerator/HelperDataObject/HelperDropSource/HelperDropTarget 的 Release 原来在 delete this 后 return refs，读取已经释放的成员。统一先保存递减后的计数，再按零值删除并返回局部值。
- 新增 test-dnd-helper-lifetime.cmd，复用实际 helper 源码并重命名其窗口入口；验证四类对象 AddRef/QueryInterface/Release，共 4000 次完整生命周期，不创建窗口、不操作鼠标或剪贴板。普通和 --asan 构建均通过。
- 使用 HEAD 中修复前 helper 的独立副本运行相同测试，ASan 明确报告 HelperFormatEnumerator::Release heap-use-after-free；日志 review-dnd-helper-before-asan.log。修复后 ASan 日志 review-dnd-helper-after-asan.log 无错误，输出 DND_HELPER_LIFETIME_PASS objects=4000。
- 仅修复该明确内存问题；helper 的枚举器 Skip/Next 契约、输入数据边界及启动失败清理仍需继续审查，不能据本测试宣称全部安全。未运行跨进程物理拖放。TESTS/未闭环清单同步，diff --check 通过。

## 2026-11-10：实现重审——测试文档参数与当前脚本核对

- 使用 PowerShell AST 提取各脚本参数，将 TESTS 表格 93 个脚本条目、231 个可选参数逐项对照，全部匹配。参数数据保存 artifacts/script-parameters.json；该检查不执行脚本、不证明参数组合或功能通过。
- 修正 review-open-items 中“HoverDemo 没有包装脚本”的过期现状：已存在 test-hover-demo.ps1，仍仅编译/解析通过，实际鼠标运行待许可。没有新增生产代码改动或重复性能测试。
- git diff --check 通过；整体实现/物理验证仍未宣称完成。

## 2026-11-10：实现重审——RD 诊断未执行不能 PASS

- 复现 rd_direct_spike / rd_translate_spike 在 OpenGL 无 RenderingDevice 时退出 0 并打印 PASS rd_unavailable；保留 review-rd_direct_spike-unavailable-before.log / review-rd_translate_spike-unavailable-before.log。这两项未执行 RD，也未检查生产回退。
- 改为缺设备明确报错、退出 1、不输出 PASS；保留全部正常 RD 颜色、桥接及像素差异阈值。mobile/separate 两项通过，无 ERROR/SHADER ERROR；GL 两项均按预期非零拒绝，修复前后行为已动态核对。
- 结果日志 review-<probe>-mobile.log / review-<probe>-unavailable-after.log。TESTS 修正“无设备回退通过”和未经此夹具完整证明的“零泄漏”表述，历史 RD 计划追加更正。生产后端不变，architecture 无需修改；diff --check 通过。

## 2026-11-10：实现重审——Stage 测试不能截断分数 DPI

- 原始 stage_test.gd 的缩放修改用整型 ps 和整数除法：例如 500/400 的 125% 捕获会按 1 倍坐标采样/点击。改用浮点宽度比例，只有 Image 像素、region 和遍历边界显式 roundi；合成输入保留浮点缩放，不改变颜色、文字数量、资源及互动断言。
- 当前 2× 环境 test-stage.ps1 的 mobile 和 gl_compatibility 都通过，包括渲染、Effect、鼠标/键盘合成动作和资源释放；日志 stage-mobile.log、stage-gl_compatibility.log。未改变系统 DPI，125%/150% 的实际显示链路仍未动态验收。
- 逐一检查原始变更中的 19 个 tscn：均为单脚本 Node/Node2D 入口，引用文件均存在，未发现声明不一致。核对 render_target/shader/surface 的缓存资源计数变更与原始 per-pass/缓存分离意图一致；未降低断言。脚本入口检查不是各场景运行通过证明。
- 更新 TESTS/review-open-items，git diff --check 通过；生产窗口和渲染实现未改动。

## 2026-11-10：实现重审——场景纹理等待必须观察实际宿主推进

- SceneTextureProbe 原有固定次数 awaitTick 调用把超时返回相同 tick 也当作进展；resize 两段等待还忽略停止返回值。统一为只统计递增 tick、每段 10 秒总期限、按剩余时间限制单次等待；正常模式遇到停止立即失败，MissingScene 模式保留预期停止语义。
- 第二张场景纹理分配失败现在明确断言，避免后续绘制只报空引用。保留场景别名、CPU 上传拒绝、resize 身份/颜色及纹理池计数断言，不改变生产渲染或资源生命周期。
- mobile 普通、-Resize、-MissingScene 均通过；resize 像素保留蓝/红/透明混合/绿色标记，缺失场景错误及清理门禁通过。日志 scene-textures-mobile[-resize/-missing].log。未动态注入静止 tick，此次实跑证明正常推进和预期失败路径。
- TESTS 表补齐原先遗漏的 -Resize/-MissingScene 参数及等待说明；diff --check 通过。真实鼠标 HoverDemo 许可仍未收到，没有运行该测试。

## 2026-11-10：实现重审——真实 Demo 悬停线程与门禁修复待物理运行

- 重写 HoverDemoProbe 的后台驱动：反射/节点遍历/监听器/目标选择均在 FX 线程，FutureTask 10 秒有界调用并传播异常，间隔 sleep 移到工作线程，取消尚未执行任务；保留真实 LoadingStage 按钮和八轮渐进靠近/保持/移出，不再静默换成其他按钮。
- 失败传到 main；退出尝试恢复鼠标、关闭窗口、interrupt/join 驱动并关闭 VFX 全局服务，成功和清理之后才输出 PASS。新增明确物理运行开关及 test-hover-demo.ps1，默认不能直接操作鼠标；-CompileOnly 只编译。
- 宿主取消固定 2 倍缩放，补齐八轮稳定样本和亮暗门禁，沿用原 0.30 阈值、31 帧过渡，错误比例上限 5%。尚需真实场景验证，不能仅凭解析成功宣称像素通过。
- Java 编译、Godot --check-only、PowerShell AST 解析及 diff --check 通过。已请求真实鼠标运行许可；在收到明确同意前不运行。TESTS/acceptance/review-open-items 同步记录当前限制。

## 2026-11-10：实现重审——入口覆盖审计与遗漏诊断定位

- 原始变更 18 个脚本都在 TESTS 有文件名引用；17 个 PowerShell 脚本通过语法解析，仅证明语法/入口引用，不替代运行。
- 定位未被脚本列表覆盖的 HoverDemoProbe/hover_demo 旧诊断：真实鼠标、无限 latch、跨线程场景访问、FX sleep、吞异常及亮暗统计无门禁。没有运行物理输入；该入口尚未修复，列为下一项，旧 PASS 不视为验收证据。
- 新增 review-open-items.md 并链接到 AGENTS/acceptance，保留原始全量审查范围及物理/故障验证限制。此次进展是发现具体未闭环实现并完成入口覆盖核对，没有声称整体已完成。

## 2026-11-10：实现重审——窗口拖动夹具的被动 Robot 释放

- WindowDragProbe 为避免实际光标落在移动窗口内，创建 Glass Robot 只读取位置；原来 getMouseX/getMouseY 抛异常会跳过 destroy。改为读取放在 try/finally，成功创建后的异常路径也尝试释放，不改变窗口放置、拖动断言或输入方式。
- 核对宿主夹具：15 段共 240 物理像素拖动、每段有等待上限，最终检查 X/Y 位置和宿主资源计数；没有放宽断言。GL/safe 与 mobile/separate 都通过，平均等待分别 2.0 / 2.0667 帧、最大 2 / 3 帧。日志 window_drag-gl_compatibility-safe.log、window_drag-mobile-separate.log。
- 全部输入由 Godot 合成；Robot 只读取位置，不移动真实鼠标或合成 OS 按键。读取失败路径未动态注入；这不是物理拖动验收。未改生产代码，既有 TESTS 命令和架构仍适用；git diff --check 通过。

## 2026-11-10：实现重审——菜单复现探针不能超时仍 PASS

- 检查 WindowDrag/ResizeCursor/MenuClick 观察器；菜单旧实现吞点击异常、无限 latch 等待、在 FX 线程 sleep，忽略最终 pulse.await 的 false 返回，存在未完成仍 PASS 的路径。
- 将菜单探针改为 FX AnimationTimer 状态流程，保持最大化、六页导航、打开菜单及六秒观察；Godot 合成点击替代真实 Robot，无新增物理输入依赖。原菜单回调成功必须恰好一次，主线程等待 Application 退出及 VFX 服务清理后才输出 PASS；宿主检查渲染完成序号和合成提交增长。保留 60 秒宿主期限，Java 流程有 45 秒期限。
- 首次使用 ActionEvent 过滤器观察失败，定位为 FusionButton 直接调用 handler(null)，并非事件冒泡；改为测试内包装并调用原动作记录成功次数，不修改 VFX 源码或业务动作。失败日志 review-menu-action-observer-mismatch.log 保留；修正后 mobile/separate 双侧 PASS、无错误，日志 menu-click-mobile-separate.log。
- 新增 test-menu-click.ps1，补齐 TESTS 与历史 RD 计划说明；没有实际鼠标/键盘输入。验证菜单动作/渲染进展，不宣称全菜单像素验收；git diff --check 通过。

## 2026-11-10：实现重审——音频夹具的错误与成功边界

- MediaAudioProbe 只检查 tracks 非空，无法区分音频轨道；NaN 时长会绕过差值比较。现在要求真实 AudioTrack、有限时长和有效预期/容差；读取用于暂停/seek/结束判定的播放时钟时明确拒绝 NaN/无穷/负值。
- 暂停/结束回调异常统一传回测试失败状态；stop 分别尝试停止 observer 和 dispose player，记录清理失败，避免 Application 捕获 stop 异常后 main 仍输出 PASS。保留第一个失败并附加后续错误。原有播放、暂停、seek 时间和容差不变。
- AIFF 生成器原来忽略 fclose 返回值，补齐关闭/刷新失败判定；不能在文件尚未成功关闭时输出 MAKE_AUDIO_FIXTURE_PASS。
- 最新源码 SDK/Editor 上 test-media-audio.ps1 -Renderer mobile -Codec all 通过，WAV、MP3、AIFF 都完成播放控制和清理；日志 media-audio-mobile[-mp3/-aiff].log，native fixture 由脚本重新编译。全程静音，无真实听感验收；未注入磁盘关闭失败或 MediaPlayer.dispose 异常。生产 Media 实现未修改，architecture 无需更新。
- TESTS 已同步，git diff --check 通过。

## 2026-11-10：实现重审——主循环计时核对与当前帧率复验

- 核对原始 main.cpp HOVER_TAP 变更、GodotEventLoop 计时及 GodotPulseScheduler 的宿主 tick/饥饿合并路径；主循环和事件循环诊断开关关闭时不进行附加计时读取，当前未发现这部分需要新增修复。核对独立窗口关闭时先解除拖放委托再释放 handler/窗口的顺序；未作无依据重写。
- 用最新源码构建执行 Godot mobile/safe、RD1/LCD1 VFX 68 次页面动画基准，关闭诊断采样；通过，1625 pulses，pulse 57.343 FPS、宿主合成 54.538 FPS，失焦 0。原始日志 review-vfx-current-scope.log；独立重算加权 pulse FPS 及 presentations/elapsed_ms 与汇总一致。
- 详细分位数和限制写入 frame-benchmark；按用户更新后的目标保留偶发长帧但不修复，不宣称每个页面稳定 60 或物理刷新 60。本轮没有修改生产代码，进展为审查证据及当前构建性能验证；其他代码审查和物理测试限制仍未闭环。

## 2026-11-10：实现重审——Windows 拖放注册失败与对象析构

- DisplayServerWindows 的新增 JavaFX 委托路径在 RegisterDragDrop 之前发布 DropTarget 指针；失败后留下非空未注册对象，后续调用跳过注册。原有文件拖放路径也有相同发布顺序。两者改为临时对象注册成功后才写入 WindowData；失败 Release 临时对象并输出 HRESULT。
- window_set_drag_delegate 返回 Error，成功后才发布委托/userdata；失败保留旧委托。JavaFX 宿主只在成功后保存 handler，否则明确报告运行时失败。清除委托不创建新 DropTarget。
- DropTargetWindows::Release 最后一次引用释放由 memfree 改为 memdelete，确保执行 C++ 析构、释放 String 等成员持有的存储；正常窗口销毁仍先 RevokeDragDrop 再释放窗口持有引用。
- 源码引擎顺序构建通过；mobile/separate OLE 注入普通档及 -Timeout 档通过（后者含 OLE_TIMEOUT_CANCEL_PASS），未移动真实鼠标或键盘。日志 ole-inject-mobile-separate.log 和 ole-inject-mobile-separate-timeout.log。测试覆盖正常委托收发/取消；没有人为制造 OS 注册失败，失败回滚尚无动态故障注入证据。
- 根仓库及 Godot 子模块 diff --check 通过；更新 glass 文档，测试入口/架构分工未变。

## 2026-11-10：实现重审——触摸键盘原生错误不能被静默丢弃

- windows_tabtip 原来忽略 CoCreateInstance、Toggle 和 PostMessageW 的失败；注释/文档把不抛 Java 异常等同于调用链成功。request/release 现返回 HRESULT；宿主按操作首次失败记录 WARNING，保留错误码且不终止 JVM。没有键盘窗口可关返回 S_FALSE；消息失败但错误码为零时仍返回失败。保留现有 Toggle 策略，不宣称重复 request 等同于幂等显示。
- 新增 test-tabtip-result.cmd，以独立 C++ 测试替换所有触摸键盘相关 OS 调用；覆盖组件缺失、成功却空指针、Toggle 失败/成功、窗口缺失、投递成功/失败和错误码为零，验证取得的 COM 接口恰好释放一次。TABTIP_RESULT_TEST_PASS 通过，不会触碰真实系统键盘。
- 源码引擎顺序构建通过，VirtualKeyboardProbe 重新编译通过；git diff --check 通过。没有运行真实虚拟键盘显示/关闭测试，不据构建及原生模拟宣布物理验收完成。
- 同步 TESTS/glass/acceptance 文档及探针消息，明确旧 PASS 仅证明 Java 调用完成和宿主存活，不能证明 OS 显示成功。组件/线程架构未变，architecture 无需修改。

## 2026-11-10：实现重审——LCD 生成着色器不能静默跳过转换

- 核对 GodotTexturePool 的 512 MiB 目标/1 GiB 最大预算与原生资源账本上限、GlyphCache 的 LCD 分支及 Godot 渲染诊断计时开关，暂未发现新的修改需求。
- GodotShader.loadPrism 在 LCD_SCREEN 开启时，若生成代码未匹配替换标记会静默保留 dstColor 着色器，而 Context 已停止提供 LCDBuffer。改为加载时明确报错并带着色器名称；不是回退到不完整的画面路径，也不关闭 LCD 功能。
- 新增 test-lcd-shader-load.ps1：普通/AlphaTest 两个变体，分别在两种 LCD 模式加载原资源及独立 patch 资源（仅在 dstColor 声明分号前加合法空格）。正常资源两种模式成功；变化资源在旧 LCDBuffer 模式成功、屏幕采样模式必须明确拒绝。该测试不启动窗口/操作输入，不修改 SDK 资源。
- 用 HEAD 中修复前 GodotShader 单独编译并 patch 到测试进程，复现旧实现静默接受变化资源，日志 review-lcd-shader-before.log。最终源码 SDK（含 Media，关闭 WebKit）构建成功；新测试四组通过；mobile/separate 的 lcd-overlap 两次 Godot 渲染及像素差异门禁通过。没有将该检查当作 Media 播放或帧率验收。
- 已同步 TESTS/prism 文档；本轮无架构变化，无需修改 architecture。偶发长帧继续排除在当前修复范围外。

## 2026-11-10：实现重审——外部拖放驱动的失败传播与清理

- ExternalDragProbe 原驱动 FX 步骤的 finally 只通知 latch，步骤异常未传回驱动，后续步骤仍可能运行；清理回调异常也可能被 latch 隐藏，驱动线程未回收。改为有 10 秒期限的 FutureTask 调用，启动/事件回调统一记录失败，断言失败立即结束该处理，退出设置 stopping、取消待执行步骤并中断/join 驱动。
- 清理逐项尝试停止延迟动画、释放鼠标/ESC、恢复鼠标位置及关闭窗口；即使 join 失败也执行输入清理，清理异常附加到原失败，退出检查晚到的驱动错误后才输出 PASS。不改变三阶段负载、拖放步骤或 VFX 行为；超时取消不会强行中断已经执行的 FX 回调。
- test-drag-drop-external.ps1 恢复原 helper 坐标环境变量，避免删除调用者已有配置。修正文档 helper 可执行文件路径及 Java 注释中逻辑/物理坐标的混淆。
- 本仓库 SDK + JDK 25 javac、PowerShell AST 解析及 git diff --check 通过。未获得真实鼠标键盘测试许可，本轮没有运行外部拖放；历史通过不能替代修改后的物理验收。生产模块未改动，架构文档无需同步修改。

## 2026-11-10：实现重审——悬停探针异步异常与退出清理

- 按更新后的目标，FPS 接近 60 即可，偶发长帧暂不修复；继续审查实现正确性、明确的性能浪费及资源生命周期。
- HoverFlickerProbe 原来多处 CountDownLatch 无限等待，Fusion FX 回调仅打印异常后继续，且未在失败时停止动画和关闭窗口。改为 FutureTask 有界调用（每次 10 秒），传播异常，超时/中断取消尚未执行的任务并保留线程中断状态；统一 finally 清理，清理异常附加到原失败，只有正常完成及清理后才输出 PASS。取消不强行中断已执行的 FX 回调，宿主保留 120 秒总期限。
- Theme/场景操作均在 FX 线程，删除工作线程读标题后跳过阶段的路径与重复 Robot 创建；默认合成输入、阶段次数、停留时间和像素断言保持不变。没有修改 VFX 业务行为。
- source SDK 编译及 mobile/separate 合成档通过：普通按钮 1428 帧/28 缺色，Fusion 稳定 hold 583/583 亮、gap 223/223 暗。日志 artifacts/logs/review-hover-fx-lifecycle.log；未运行真实鼠标 Robot 档，未注入 FX 卡死。逐帧读回测试不作为性能数据。

## 2026-11-10：实现重审——Fusion 悬停只统计未判定

- 复验 hover-flicker 基线通过，但静态核对发现 Fusion 阶段未参与最终判定，且固定 2 倍坐标、未检查 JVM failed/超时、包装器忽略 ERROR/SHADER ERROR。保留 review-hover-gate-before.log，不据该旧 PASS 宣称 Fusion 像素已验收。
- 补齐六轮 HOLD/GAP 稳定样本及亮/暗错误比例门禁（沿用普通按钮的 5% 容忍）、新增 HOVER_FUSION_PIXEL_PASS；读取当前屏幕缩放，宿主失败/120 秒超时明确失败，包装器检查完整错误日志。生产行为及 VFX 控件不变。
- mobile/separate 默认合成档通过：普通按钮 1432 帧/28 缺色，Fusion 稳定 hold 588/588 亮、gap 224/224 暗；日志 review-hover-fusion-gate.log。同后端 resize-cursor 合成档也通过。仅当前 2×/60Hz，未运行 Robot 或其他 DPI；逐帧读回夹具不是性能基准。

## 2026-11-10：实现重审——顶点更新排队数据的重复复制

- 检查 RD 缓存与更新路径时发现 queue_vertex_buffer_update 对已有顶点向量再次 resize/memcpy 整批数据。确认 Godot PackedByteArray 是 Vector<uint8_t>、绑定 Variant 持有 COW 存储后，改为共享所有权排队；后续生产者写入自动分离，任务执行前不会引用已销毁的临时缓冲。保留原有 ring epoch、FIFO 次序和退休机制。
- 引擎源码构建通过，引擎 separate / Runtime safe RD 回归通过，覆盖每 pass 48 次绘制跨 16 槽、多轮清空/保留及旧图像像素。真实 VFX 大表 direct / RD_DIRECT=1 / mobile / separate / 无栈采样通过，日志 `review-vertex-upload-cow.log`，96 pulses、位移 2325、失焦 0；本次 55.785 pulse/s、p95 25.364 ms 仅为单次观察，不据此宣称提速或稳定 60 FPS。
- 此改动消除一次明确的整批 CPU 分配/复制，不声称降低 GPU 顶点缓冲容量或覆盖真实设备分配失败。

## 2026-11-10：实现重审——RD 翻译诊断释放次序与 PASS 后错误

- 继续核对原始 javafx_rd_direct 诊断实现，LCD spike 实跑得到 max_diff=0 和 PASS，却随后报 Attempted to free invalid ID，退出码仍为 0。保留 `review-rd-lcd-release-before.log`。原因是 release_cycle 先释放 screen stand-in 纹理，设备连带销毁 uniform set，之后又显式释放该 set。
- 将 uniform set/sampler/value buffer 退休任务排在所有引用纹理和 shader 释放之前；清理 set 时检查设备有效性，兼容外部输入先被释放的情况。该实现是诊断 probe，独立于生产 OffscreenPass，不能把两者的生命周期证据混用。
- 新增严格包装器 test-rd-lcd.ps1（safe/separate、Runtime），检查完整日志中的错误；旧产物被此包装器拒绝。无 RenderingDevice 不再输出成功标记。引擎源码构建通过，引擎 separate 与 Runtime safe LCD 检查通过、像素最大差 0、无释放错误；引擎全 262 Shader 严格语料仍通过。

## 2026-11-10：实现重审——累计原生与调度约束复验

- 核对测试入口后运行当前源码单元测试：test-protocol（含 10000 帧并发、畸形输入、原子接收、背压、停止及三种通知时钟隔离）、test-bounded-lru（容量/字节预算及分配失败回滚）、test-clipboard-ownership（私有 HGLOBAL 生命周期和 DROPFILES/DIB 边界）、test-dnd-drag-image（OLE 数据对象/分配失败和拖动图像存储）全部通过。日志保存为 artifacts/logs/review-test-*.log。
- 当前源码 SDK 的 render-command-validation 及真实 Godot 承载的 glass-scheduler 通过；后者日志明确为 GL compatibility，覆盖线程隔离、嵌套事件循环、异常、定时器、取消及接收线程终止。相关根仓库和子模块 diff --check 通过。本轮没有新增实现修改。
- 这些测试不读写系统剪贴板、不注入真实键鼠；OLE shell 图像存储通过不代表跨进程拖放或屏幕预览通过。仍保留此前记录的物理夹具、系统剪贴板互通及完整范围收尾审查限制，没有据单元测试汇总宣告整体完成。

## 2026-11-10：实现重审——拖动夹具 FX 调用异常与跨线程日志

- PhysicalDragProbe 的 latch 仅通知完成，不传播 action 的异常；超时后排队动作也可能迟到执行。改为 FutureTask.get，异常传给驱动线程，超时/中断取消尚未执行任务。运行中的 FX 动作不会被强行中断。
- trace 改为同步容器并取稳定快照再检查，消除 FX 写入/驱动 stream 与 subList 并发；完成/失败状态可见性明确，失败聚合同步。关闭中断驱动，main 在 launch 返回后 join，防止遗留线程。Robot 创建移到 FX 线程，跟踪按键状态并在关闭/失败时尝试 release/destroy。
- 仅运行默认合成档：最终代码 mobile/separate 与 gl_compatibility/safe 均通过，拖动 10 事件到 -180、缩放 8 事件到 740×576，trace 56 条且无手势中断。未运行 Robot；没有以正常路径成功冒充超时故障注入或物理投递验收。测试和文档改动，不需要重建宿主。

## 2026-11-10：实现重审——原生物理拖动对照的并发与退出

- NativeTableDrag 原先在后台线程等待共享完成标记/列表，30 秒轮询结束未强制检查完成；FX 动画异常和初始化异常缺少统一鼠标释放，部分错误只打印后继续，可能输出 PASS。移除后台驱动、latch 和共享可变列表，改为 FX 线程上分阶段等待、选择页面、按下、96 次采样、释放和退出。
- 加入原生 Windows Glass 标记及失焦失败；超时/提前关闭/异常不通过，stop 同样执行清理。只有 launch 返回、无失败且完整采样后打印 PASS；后台 VFX TaskManager/GlobalScreen 生命周期在 finally 结束。45 秒期限依赖 FX 脉冲，不声称防住完全卡死的 UI 线程。
- 使用源码 SDK/JDK/VFX 产物编译通过；没有运行 Robot 或操作真实键鼠。TESTS.md 增加编译/须授权后运行命令、前置和验收限制，物理行为验证仍未完成。

## 2026-11-10：实现重审——大表宿主观察窗口和增长横坐标

- 宿主夹具 measured_ticks/unfocused_ticks 只统计空闲，却被用于拖动报告；pollCount 永远为 0，导致每帧调用 get_render_stats，GROWTH 中间横坐标重复、末项用数组长度。保留旧运行 `review-table-growth-before.log`。
- 空闲与拖动分别计数，资源数据改为每 8 个拖动 tick 采样且包含首尾，增加严格递增断言。累计 max_draw_sync_us 不作差，改为 lifetime_max_draw_sync_us，避免把两个累计最大值相减伪装为区间最大值。旧后台拖动和时间轴结论在文档中明确撤回对应证据。
- direct / 显式 RD_DIRECT=1 / mobile / separate / 无栈采样运行通过，日志 `review-table-host-counters.log`；独立 JSON 验证 61 空闲 tick、95 拖动 tick、各自失焦 0、13 项增长样本与 0/8/.../88/95 横坐标一致。只改诊断夹具和文档，无需源码重建，不宣称后台/物理输入或总体无泄漏。

## 2026-11-10：实现重审——大表采样器重复旧实现与统计顺序

- VfxTableScrollProbe 仍使用无界 synchronizedMap、停止不 join、吞 Throwable 的旧采样器。替换为已经独立测试的 ThreadStackSampler，统一正间隔校验、有界栈键、异常传播和停止快照，并在 main finally 覆盖失败退出清理；构建脚本显式编译共享类。
- 修正空闲分位数从未排序序列取索引，以及拖动 GAPS_MS 在排序后输出的两个诊断错误。前者排序后计算；后者先保留时间顺序再排序计算分位数，不改业务拖动行为。
- test-stack-sampler 通过；direct / RD_DIRECT=1 / mobile / separate / 20ms 采样的真实大表运行通过、丢弃 0，保留 review-table-sampler-positive.log。独立重算 96 项原始间隔与 p50/p95/p99/max 在 0.1ms 日志舍入范围内一致。0ms 配置明确失败且没有 PASS，日志 review-table-sampler-invalid.log。诊断运行不作 FPS 验收。本轮只改 Java 测试及脚本，无需重建宿主/SDK。

## 2026-11-10：实现重审——滚轮夹具观察过早与脚本复验

- 审查原始测试脚本/夹具时发现 ScrollWheelProbe 在第三次 ScrollEvent 的 filter 内测量位移，早于 ScrollPane skin 处理第三次事件。原样实跑三次 delta=-40，却把 pixels=80 标记为三格 PASS；保留 `review-scroll-observation-before.log`。
- 改为 Platform.runLater 在事件分发完成后检查，保留每事件原生换算断言，再按三次 delta 累加并夹到可滚动范围，要求最终误差 ≤0.01 px。取代与系统滚轮行数无关的 moved>=60；包装器要求完整测量行并拒绝 Shader 错误。未修改实际产品滚轮行为、业务代码或系统偏好。
- mobile/separate 与 gl_compatibility/safe 均通过，pixels=120.00000000000001、expected=120。仅证实当前三行设置；未通过改系统设置验证零行/整页档。FIFO/LIFO ImagePool 测试和 mobile 源码 Media WAV/MP3/AIFF 播放控制测试亦通过；音频探针静音，不是物理声音验收。此次只改测试和文档，无需重建原生产物。

## 2026-11-10：实现重审——累计切页复验与模块退出阶段

- 当前 Shader/缓存修复后的无诊断 VFX 全部 68 次切页通过，显式 RD_DIRECT=1 / LCD_SCREEN=1、mobile/safe、失焦 0、无绑定错误。日志 `review-vfx-post-shader-fixes.log`：57.296 pulse/s、54.614 次宿主合成/s、p95 20.486 ms、p99 45.996 ms、最大 188.866 ms。启动后 FIFO pacing 被检测为平均 32.967 ms 并切为 CPU pacing；不宣称稳定 60 FPS 或整段 VSync。该性能测量在本节下述退出修复之前。
- 核对 Godot main.cpp 卸载顺序，模块 uninitialize 在 EDITOR/SCENE/SERVERS/CORE 多阶段调用，而 JavaFX 原先无阶段过滤。RD_PROFILE=1 的引擎回归实际输出四份相同汇总，保留 `review-module-teardown-before.log`。现只在与注册一致的 SCENE 阶段做全局资源清理与汇总，避免后续渲染服务已销毁阶段再次进入清理。
- 引擎源码构建通过；带 RD_PROFILE=1 的 separate / safe RD 回归通过，包装器要求恰好一份汇总。根仓库与相关子模块 diff --check 通过。另复核 JFX EventLoop/PulseScheduler/View/Window/TexturePool 与 Godot viewport 诊断改动的差异；本轮未据此新增兼容性或物理输入验收结论。

## 2026-11-10：实现重审——全局 instance-uniform 名称缓存有界化

- 将 shader_rewrite 的无界源码→名称 HashMap 替换为已有 BoundedLruCache，限制 256 项 / 4 MiB 源码及名称数据；完整 String 键比较保留哈希冲突正确性。超预算源码仍正常处理而不缓存，空名称也受同一预算限制，退出时清空。名称列表按 COW 值返回，避免淘汰后引用悬空；移除多余的空名称分支。
- shader-cache 夹具显式使用 viewport，包装器强制开启 instance uniforms 并恢复环境。扩展为 305 轮 / 301 份不同源码，先验证达到 256 项，再加入长注释触发字节淘汰；仍检查逐轮颜色、64 项目标 shader 缓存和溢出资源释放。mobile/separate 通过，最终名称 memo 为 31 项 / 4,079,724 字节。
- 引擎源码构建通过；显式 RD_DIRECT=0 的引擎 mobile/separate Node Shader 测试、Runtime mobile Effect 与原生 D3D 对照通过。后者日志另存 `review-instance-memo-runtime-effects.log`。预算不是总进程/驱动内存，正常测试也不证明所有异常分配路径无泄漏。

## 2026-11-10：实现重审——RD 初始化结果检查与剩余缓存范围

- OffscreenPass::initialize 未检查 snapshot_texture 创建结果，可能以缺失屏幕快照的状态成功；framebuffer 失败后仍继续分配并安排 bridge 初始化。现按 color texture、framebuffer、snapshot、bridge 顺序逐项检查并报告具体失败，失败即停止。调用端已有 unref → 析构 release 路径回收部分分配，然后走既有 viewport fallback；不再无日志地把不完整 RD 目标视为成功。
- 引擎源码构建及 separate / safe RD 回归通过。未注入驱动分配失败；这里的失败分支结论来自代码审查，不将正常回归当成设备 OOM 验收。
- 重新枚举 9ae5a635（不含）至 HEAD 原始变更，继续核对 host_windows、register_types、shader_rewrite 等范围。发现 javafx_shader_rewrite.cpp 的 process-global HashMap<String, Vector<StringName>> 没有条目/字节上限，独立于已修复的 RD pipeline LRU。host 与 target 编译路径都会调用，当前 shader-cache 夹具只检查目标自身的 64 项 shader 缓存，不能证明该全局 memo 有界。此项仍待修复；需同时考虑返回名称列表在淘汰后的生命周期。

## 2026-11-10：实现重审——读回数据所有权和无效读回

- RD readback 原来先取得完整 RGBA8 向量，再创建空图、取出并修改其数据、memcpy 整图；静态 staging 还保留最后一张图至下次请求。现同步后通过 Image::create_from_data 的写时复制存储接收数据，并立即清空 staging 引用，去掉重复整图分配/清零/复制与静态持有。
- 入口明确要求主线程和存活目标，长度不符时报错并返回空 Image；宿主已有空值检查会使 Java 请求失败。旧实现会返回看似成功的空白图。未注入真实设备读回失败，因此不将正常测试扩大为设备故障恢复证明。
- 新增 RD_READBACK_OWNERSHIP_PASS：17×9 目标先红后绿，保留三次读回 Image，修改第一张一个像素，销毁目标后逐像素检查各图仍独立有效。引擎源码构建与 separate / safe RD 回归通过；引擎 separate 的 Java→协议→RD→读回 queued-texture-update 测试也通过。此优化针对显式读回，不宣称改善正常渲染 FPS。

## 2026-11-10：实现重审——屏幕采样器声明与引用不一致

- 继续检查翻译器发现：hint 采样器一律声明为 dst_color_snap，但仅替换 header 中 SCREEN_TEXTURE 字符串，fragment 直接引用和其他合法变量名均未同步。新增 helper / fragment 直接采样 / scene_snapshot 三种写法；旧产物报 undeclared identifier 并丢弃绘制，保留 `review-rd-screen-sampler-before.log`。
- 保留原始采样器名，只移除 Canvas hint、添加 RD descriptor binding，并保持声明在 helper 前；省掉不必要的字符串替换，也避免名称不一致。同步更正头文件中“pass 前快照”的过期注释。
- 加强屏幕像素断言：旧 pass 品红，本轮蓝/绿背景，采样后交换红蓝通道，必须得到红/绿；没有背景则要求透明。这样丢弃绘制后原背景不变也无法通过，而非只依赖日志 ERROR 门禁。
- 引擎源码构建通过，引擎 separate / Runtime safe RD 回归通过，真实 JavaFX LCD 重叠文字 separate 双路径对照通过。相关日志为 `rd-regressions-separate.log`、`rd-regressions-safe-runtime.log`、`lcd-overlap-separate-0.log` 和 `lcd-overlap-separate-1.log`。此验证覆盖上述声明/引用及 LCD 路径，不代表所有 Canvas Shader 语法均可翻译。

## 2026-11-10：实现重审——像素坐标翻转与 corpus 宽松门禁

- 完整语料原样复验仍为 186 strict / 76 edge。核对 Godot canvas.glsl 的 gl_FragCoord.xy 与正数 screen_pixel_size，新增实际 RD 坐标渐变断言，首行预期 0.03125 却读 0.9686；日志 `review-rd-pixel-coordinate-before.log`。
- SCREEN_UV / SCREEN_PIXEL_SIZE 改为 gl_FragCoord.xy。引擎构建和 separate RD 回归通过；完整语料变为 262 项全图每通道最大差不超过 2/255、0 edge、0 deferred、0 failed。
- 删除 corpus 的 40% 差异字节容忍和 deferred/GLES 跳过路径；新增严格包装器 `test-rd-corpus.ps1` 并运行通过。旧“两个近似”的解释已在文档更正，不把历史宽松 PASS 当作当前验收。Runtime 构建和 RD safe 回归通过。实际 Effect/D3D 对照随后暴露 ADD/MULTIPLY 失败，日志 `review-rd-blend-mode-before.log`。
- 另定位到 blend_mode 用整份源码的子串判断，Blend_ADD 的 blend_add 辅助函数、Blend_MULTIPLY 的函数名前缀会错误改变管线混合因子。改为复用 Godot ShaderLanguage 解析结果中的 render_modes；新增带同名 helper 的半透明回归。整份语料仅覆盖固定参数/纹理，不能替代实际效果合成。
- 修复后引擎源码构建、引擎 separate / Runtime safe RD 回归、262 项严格语料均通过。新增夹具首次运行的 GDScript 局部类型推断错误已改为显式 String 声明。显式 `GODOT_JFX_RD_DIRECT=1` 的引擎 mobile Effect 与原生 D3D 对照均通过：Blend 和 Blend_ADD 平均差 0，Blend_MULTIPLY 约 0.000000123，PerspectiveTransform 约 0.0000598，各项 bad=0。保留 `review-rd-blend-mode-editor.log`、`review-rd-blend-mode-runtime.log`；检查 Runtime GPU 截图 `godot-effects-mobile-runtime.png`。这些证明本夹具的效果输出，不扩大为所有 Shader 参数或稳定 60 FPS。

## 2026-11-10：实现重审——END_PASS 后纹理引用标记过早清除

- 最小复现将“红色纹理画入 A、END_PASS、更新同一纹理为蓝色、画入 B”放在一个 Java 传输批次中。原实现读回 A 为蓝色，保留 `review-queued-texture-update-before.log`。它不依赖 VFX 时序，证实旧纹理在 RD 消费前被原地改写。
- Surface::clear_draw_resources 原来在每个 pass 完成后无条件重置 referenced，但 RD 路径仅把绘制追加到 pending batch。现仅在没有待提交 RD 批次时重置；存在待消费绘制时保留引用，后续上传生成新版本，退休纹理仍按已有提交后释放规则处理。不会为了重置标记而每个 pass 强制同步。
- 新增实际 Java→协议→RD→读回夹具，检查两张目标完整红/蓝及正数批次计数。引擎构建通过；新夹具 safe/separate 通过，LCD separate 对照仍通过。显式 RD_DIRECT=1、LCD_SCREEN=1、无调试/采样的 68 次切页通过且无绑定错误，日志 `review-vfx-texture-reference-fence.log`：58.183 pulse/s、55.530 次宿主合成/秒、p95 19.964 ms、最大 158.954 ms、失焦 0。Runtime mobile 视频回归通过；不将该单次性能结果扩大为稳定 60 FPS。夹具显式启用 RD batching/direct offscreen 并恢复环境，避免环境覆盖绕过待提交状态。

## 2026-11-10：实现重审——LCD 文字节点快照边界

- 新建真实 JavaFX 文字夹具，将蓝/红和绿/黑文字错开重叠，比较同一 Godot 后端的 LCDBuffer 与 SCREEN 两种路径。修复前有 3813 个像素通道差大于 2/255，最大 255/255；保留 `review-lcd-overlap-before.png`，确认原注释提到的重叠差异确实可见。
- 在 BaseShaderGraphics 已有 lcdSampleInvalid 的文字节点边界调用可选 prepareLCDScreenSample；默认后端不变，Godot 刷新当前顶点并结束/重新选择同一目标，使每个节点的首次采样包含前面的文字。继续使用批量命令，不增加每节点 JNI 同步调用。启用 Media 的 SDK 构建通过。仅此改动后对照仍有 5552 个差异像素，继续定位出 RD SCREEN_UV 额外 Y 翻转：分色背景顶部应蓝却读绿，保留 `review-rd-screen-coordinate-before.log`。改用实际 framebuffer 方向后，引擎 separate RD 回归通过，LCD safe/separate 均为 0 个超容差像素（文字像素 31885）。Runtime 源码构建与 RD safe 回归通过。但无采样、显式 RD_DIRECT=1 的完整切页基准报一次 recorded uniform binding was invalidated before submission，包装器正确失败，日志 `review-vfx-lcd-node-snapshot.log`；其 FPS 数值不作为通过证据。两页 RD 调试 smoke 通过。另一次诊断切页未显式启用 RD，rd_batch_commits=0，只能作为 Canvas 路径观察，不能用于排除该 RD 故障。下一步检查 END_PASS 后 Surface 重置 referenced，而 RD 批次尚未消费时纹理是否被原地更新；此为待最小复现验证的假设。

## 2026-11-10：实现重审——RD 屏幕快照早于本轮清空和背景

- 复查 Prism LCD 屏幕采样优化时，发现 RD 实现与“首次屏幕采样时取快照”的文档不符：实际在整个 pass 开始前复制，因此读到旧帧。新增实际 GPU 回归，上一 pass 红色、当前清空并画蓝色，采样错误返回红色；保存 `review-rd-screen-snapshot-before.log`。
- 改为首次屏幕采样前结束初始 draw list，执行 texture_copy，再以保留现有内容的方式继续；这使清空和前序背景先进入快照。测试另覆盖当前 pass 只清空时必须采样透明。
- 同一 pass 后续采样仍共用首次快照；原有“每 pass 与每文字节点取快照”的重叠差异没有因此消失。引擎源码构建通过；引擎 separate、safe 禁用批量提交、Runtime safe 的 RD 回归均通过；RD/mobile/safe 原始 VFX 全 35 页通过，日志 `vfx-intro-mobile-safe-all-pages.log`。根仓库及两个子模块差异检查通过；本次改变快照位置后的性能尚未重测。

## 2026-11-10：实现重审——自定义剪贴板编码的分配边界

- 复现修复前行为：64 MiB 直接 ByteBuffer 在 32 MiB Java 堆下，customBytes 尚未检查最终大小就复制，抛 OutOfMemoryError；日志 `review-clipboard-encoding-before.log`。此测试仅调用编码帮助方法，不访问系统剪贴板。
- 原始缓冲区先检查大小，序列化 String 先核对 header/声明长度与实际剩余字节，以及 modified UTF-8 最大扩张；解码后的 UTF-8 仍执行既有 16 MiB/NUL 规则。String 在编码分配前检查字符长度。反序列化采用 try-with-resources，仅捕获 IOException/ClassNotFoundException，不吞 VM Error。
- 新增 clipboard-encoding 低堆内存夹具，覆盖常规/序列化短长字符串、位置范围保持、NUL/空值/伪造长度和超大输入；启用 Media、关闭 WebKit 的源码 SDK 构建通过；修复后低堆编码测试通过，日志 `clipboard-encoding.log`。根仓库与 JFX 差异检查通过；系统剪贴板互操作仍未验证，本轮未读取或修改用户剪贴板。

## 2026-11-10：实现重审——完整范围核对与缺失性能计数

- 重新读取 Git 范围：根仓库 9ae5a635（不含）至 04e4ba1 共 127 条变更路径；子模块需另查，JFX 从 4f673a0 至当前工作区共 19 个文件，Godot 从 420dfdc 至当前工作区共 11 个文件。工作区后续修复与新增文件也属于审查范围，不能用根仓库 submodule 指针 diff 代替内部补丁。
- 复查 JFX 事件循环、pulse 调度、LCD/顶点 alpha 扩展及原生宿主模块导出，发现 TARGET_SWITCHES 虽存在且递增，但所在 impl.ps 包没有导出，基准反射读取一直输出 unavailable。补充宿主导出，Godot 基准要求正整数计数；保留历史 FPS 数据但不将缺失项宣称为已测。
- 计数为进程累计值（含启动/结束），不是切页计时区间差值，也不是 GPU 提交或物理显示次数。引擎构建与实际 mobile/safe 基准通过，累计计数 33412。日志 `review-vfx-target-switch-counter.log`：57.436 pulse/s、55.033 次宿主合成/秒、p95 24.324 ms、p99 57.498 ms、最大 255.111 ms、失焦 0；依然存在长帧，不宣称稳定 60 FPS。Runtime 源码构建也通过；整体审查仍未完成。

## 2026-11-10：实现重审——输入协议与独立时钟验证

- 核对 SCENE_INPUT 解码及资源账本：按钮编号限制为 1–9，输入类别/标志/Unicode/有限坐标有校验，输入必须引用仍存活的场景资源；现有单元测试覆盖非法参数、普通图片/已销毁场景不能接收输入。不因未确认的缺陷改写该处理路径。
- FrameQueue 新增的独立 input_tick 原先没有对应时钟断言。补充输入到达不推进 frame/capacity 时钟、帧/队列唤醒不推进 input_tick、两个输入 tick 合并返回、等待超时不制造新 tick，以及 stop/finish 后返回 -1。测试验证时钟和终止状态契约，不将其宣称为系统调度延迟上限。
- `test-protocol.cmd` 在 MSVC /W4 /WX 下通过，含 10000 并发帧；当前 SDK 的 `test-render-command-validation.ps1` 通过，覆盖 Java 几何验证、内容碰撞、缓存容量和退休。此轮只修改原生测试与文档，无需重建 Godot/JFX。

## 2026-11-10：实现重审——GodotView 父节点销毁与缩放复验

- 核对 JavaFXSceneView、Surface 的场景纹理登记/销毁、dispose_texture 和 resize_scene_texture。正常 Surface 释放先移除 textures 中 RID 的存活登记，再释放场景引用；包装对象通过 ObjectID 查找节点，父树已销毁时不会解引用旧指针。没有据此确认新的生命周期缺陷，未为猜测改写实现。
- 最新引擎的 `test-scene-views.ps1 -Renderer mobile` 与 `-Renderer gl_compatibility` 都通过：每种后端 100 轮加载/缩放/合成保留/合成输入/释放，包含父节点先销毁而包装对象仍存活的检查。日志 `scene-views-mobile.log`、`scene-views-gl_compatibility.log`。测试检查节点/包装对象和宿主自有资源计数，不等同于完整 GPU 驱动内存泄漏证明。
- `test-scene-textures.ps1 -Renderer mobile -Resize` 通过，验证跨 Java/协议/宿主的场景状态保留、纹理版本、图像与退休资源清理。查看 `godot-scene-textures-mobile-resize.png`，左侧状态保留为蓝色，右侧仍为红色，透明混合区和缩放位置标记均存在；像素断言通过。此处未运行 Robot，也没有替代物理输入验收。

## 2026-11-10：实现重审——有界管线性能复验与合成诊断开销

- 无调试/采样的 mobile/safe 68 次切页完成，日志 `review-vfx-bounded-pipelines.log`：58.242 pulse/s、55.604 次宿主合成/秒、p95 24.686 ms、p99 39.301 ms、最大 212.925 ms、失焦 0。平均和分位数优于前一份退休修复记录，但最大值更高，非受控 A/B，不能归因于缓存提速或宣称稳定 60 FPS。
- 原始变更中的 JavaFXWindowSurface::composition_finished 每次都读取计时器与 RD_DEBUG 环境变量。改为首次进入时缓存开关，关闭调试不执行额外计时；draw/sync 始终执行。上面的基准早于这项小修复，不作为其性能证据。
- 引擎构建通过；mobile/separate 原生窗口像素测试在默认配置与显式 RD_DEBUG=1 下通过，诊断日志保留为 `review-window-compose-debug.log`。Runtime 源码构建也通过；根仓库及 Godot/JFX 子模块差异检查通过。本次未新增 Runtime 窗口像素运行证据。

## 2026-11-10：实现重审——共享 RD 管线缓存有界化

- 原先成功编译的 pipeline 和源码身份表一直保留到进程退出。改为共享 LRU：最多 256 项，源码/翻译文本/默认参数载荷最多 16 MiB；超过预算的单项照常绘制但不缓存，完整源码比较仍防止哈希冲突画错内容。
- RecordedDraw 持有独立的 PipelineLifetime 引用；缓存淘汰只放弃缓存所有权，不提前释放开放 pass 或已排队绘制使用的管线。最后一个引用消失时，带 RID 值的渲染线程调用按 pipeline、shader 顺序释放。release 同时清除尚存记录的引用，避免目标对象跨引擎关闭保留资源。
- 热缓存命中刷新 LRU，插入前清空 8 项源码备忘，避免隐藏保留已淘汰资源。uniform 绑定复用当前绘制已取得的 pipeline，省去第二次源码查找，也避免超预算源码重复编译。
- 新回归让红色目标保持开放，在另一个目标绘制 260 个不同源码，检查缓存容量、旧红色像素，以及旧源码重新编译后的绿色像素。首轮修正测试输入为翻译器采用的分行声明及 Vector4 参数后，引擎 separate 通过。最终引擎源码构建通过；引擎 separate、safe 禁用批量提交、Runtime safe 的 RD 回归通过；RD/mobile/safe 原始 VFX 全 35 页通过，日志 `vfx-intro-mobile-safe-all-pages.log`。根仓库及 Godot/JFX 子模块差异检查通过。预算不包含驱动内存和未完成绘制持有的资源，性能影响仍待无采样基准验证。

## 2026-11-10：实现重审——退休修复后的性能与管线失败清理

- 无调试/采样的 68 次 VFX 切页：pulse 56.744/s、宿主合成 53.972/s、p95 26.212 ms、p99 60.800 ms、最大 181.025 ms、失焦 0。日志 `review-vfx-transition-retirement.log`；与之前单次运行不可当作受控 A/B，尚未达到稳定 60 FPS，详见 frame-benchmark.md。
- 源码检查发现 RD shader 成功创建后，pipeline 创建失败会直接返回，shader 尚未进入共享缓存，因此退出时也无法由该缓存释放。失败分支改为向渲染线程提交带 RID 值的释放调用并等待完成，兼容 separate 模式，同时明确报告创建失败。该分支不增加成功路径的同步；构建与正常回归不能代替真实设备分配失败注入。

- 本轮引擎源码构建通过；引擎 separate 与 Runtime safe RD 像素回归通过；根仓库和两个修改过的子模块 `git diff --check` 通过。管线创建失败的设备故障分支尚未直接注入，不能将正常路径通过等同于故障验证。

## 2026-11-10：实现重审——退休纹理早于 RD 批次提交

- RD_DEBUG 增加绑定/采样视图/退休/目标释放编号，前两页即可复现多次失效。`review-vfx-rd-texture-trace.log` 将首个失效 set 的 engine texture 与 RD_SURFACE_RETIRE_TEXTURE 对应，证明 Canvas 清空释放旧纹理时，引用它的 RD 批次还未提交。
- free_retired_textures 在列表非空时先 commit_batches，再释放旧 engine RID，避免设备视图连带销毁已排队的 UniformSet；空列表不增加提交。诊断只在 RD_DEBUG 开启时输出，不作为性能样本。
- 两页诊断复现通过（`review-vfx-rd-retire-fence.log`），关闭调试后的 RD/mobile/safe 35 页 VFX 通过，引擎 separate RD 像素回归通过。Runtime 源码构建与 RD safe 像素回归也通过；当前集成失败已在该引擎工作负载上消除，不扩大为全设备/帧率验收。

## 2026-11-10：实现重审——uniform buffer 退休后的绑定缓存

- 定位到依赖缓存失配：uniform buffer 淘汰后仍延迟物理释放，但依赖它的 UniformSet 保留在缓存且暂时通过 RD 有效性检查；绘制先取出这个绑定，再因顶点环形缓冲耗尽提交前批次，退休缓冲区使手中绑定失效，导致后续绘制漏画。
- UniformEntry 记录 value_buffer。缓冲区碰撞或容量淘汰时，同步移除引用它的绑定缓存项并延迟退休，禁止再取出即将失效的绑定；已排队绘制仍先于实际释放完成。
- 最小复现用 129 个不可变 Mesh 参数版本耗尽 uniform buffer 缓存，再用 17 个可变顶点批次强制提交；最后一次必须改变可见区域。修复前 Runtime 同时报绑定失效与像素错误（`review-uniform-retirement-before.log`），修复后引擎 separate 完整 RD 回归通过。VFX 全页与 Runtime 更新验证继续进行。
- 后续引擎构建和 Runtime safe RD 回归通过。但 VFX 35 页复验仍报一次绑定提前失效，日志 `review-vfx-rd-invalidated-set-after-buffer-fix.log`。本次修复解决了可独立复现的 buffer 依赖缓存缺陷，并未证明消除了 VFX 的全部失效来源；下一步需要绑定/纹理 RID 生命周期诊断。

## 2026-11-10：实现重审——主线集成复验暴露 RD 失效绑定

- 最新源码产物的 mobile Media video 在引擎都通过，包含 seek/end/stop/replay 和 Godot 宿主标记；不是原生 D3D 对照，不作为帧率或物理音画同步证明。
- RD/mobile/safe VFX 全 35 页完成导航并打印 SMOKE_PASS，但日志出现 `recorded uniform binding was invalidated before submission`，包装器正确判为失败。保留 `review-vfx-rd-invalidated-set.log`；首次截图后即出现错误，后续页面完成不能覆盖此失败。
- 下一步追查原生资源更新/退休与开放 pass、批量提交之间的时序。保留新增错误门禁，不通过恢复静默漏画获得 PASS。acceptance-status 已区分历史结果与当前失败，整体重审未完成。

## 2026-11-10：实现重审——退出后的静态拖入回调

- GodotBridge.dragTargetHandler 保存绑定到 GodotApplication 的方法引用，原来 Glass 退出后未清除，仍强引用旧应用。扩展 scheduler 探针后修复前失败，日志 `review-drag-callback-before.log`。
- 应用保存自己注册的回调身份，finishTerminating 解除仍属于本实例的桥接引用。测试同时验证运行时已注册、退出后为 null，避免以禁用功能通过退出断言；不依赖 GC 调度。
- 保留 Media 的源码 SDK 构建、Glass scheduler（含接收线程停止）、mobile/safe OLE Timeout 注入通过。该证据证明这条静态强引用已解除，不等于所有 Java 对象均已回收。整体重审仍未完成。

## 2026-11-10：实现重审——OLE 替换语义与释放重入

- 新增内置文本替换检查后，原实现原生测试失败：SetData 成功但 GetData 优先返回 SourceData 旧值，格式列表同时包含源格式和 extra 的重复项。现 extras 优先读取，枚举去重。
- 替换原来先 ReleaseStgMedium 再写 entry.second，外部 pUnkForRelease 回调可重入追加格式使 vector 引用失效。现先安装新 medium、将旧 medium 复制到局部变量，再释放旧值，回调之后不再访问 entry。
- 新增释放观察器，在回调中读取新值并追加 64 个格式强制容器扩容；检查只释放一次且重入成功。/W4 /WX 原生测试（含原有分配失败和 shell 拖放图像）及引擎构建、mobile/safe OLE Timeout 注入通过。

## 2026-11-10：实现重审——缺失 RD 纹理视图的实际回归

- 新增 rd_missing_view 夹具，使用现有绘制接口传入空 sampler RID，不增加生产故障开关。相同参数连续排队两次绘制，第二次必须新建绑定；两次都入队后才读回，覆盖旧临时绑定延迟退休。随后绑定有效绿色纹理并验证全部像素。
- safe/separate 两档通过，包装器要求恰好一条预期缺失视图 ERROR、无其他错误、PASS 标记和正常退出。初版夹具误用 Color.distance_squared，已改用实际存在的颜色比较 API 后运行通过。
- 该证据覆盖临时回退重试、排队旧绑定存活和有效纹理恢复；不覆盖 GPU 分配失败或真实设备丢失，整体重审继续。

## 2026-11-10：实现重审——RD 绑定失败与临时回退

- 代码审查发现白色回退创建的 UniformSet 没有记录临时性质，若引擎 RID 存活且设备绑定有效，缓存可继续命中，不符合原注释所述“下次 pass 重新解析”。现记录 provisional 标记，下一次 acquire 强制重新解析，旧绑定仍按排队绘制的延迟释放路径退休。
- 必需 sampler/value-buffer 的绑定创建失败时，在两个几何路径都明确拒绝绘制；合法的无 uniform shader 仍允许无绑定。提交时已失效的 UniformSet 继续避免绑定死 RID，但现在输出 ERROR，而非仅在 debug 开关开启时记录漏画。
- 引擎构建、引擎 RD separate 与 Runtime RD safe 像素回归、RD GodotView Transform 通过。上述正常路径通过不等于异常路径全部验证；临时视图缺失和创建失败仍需针对性故障夹具。

## 2026-11-10：实现重审——剪贴板恢复序列与持久备份

- 删除按文本白名单判断恢复权限的逻辑。Capture/WriteRaw 记录持锁状态下的序列号，Restore 在同一次 OpenClipboard 锁内核对后才清空并恢复，外部图片/文件变化不再因为同为无文本而被覆盖。
- 测试首次写入前保存包含原格式字节和注册名称的 CLIXML；只有恢复后逐字节检查成功才删除，恢复拒绝/失败时报告并保留。早期失败尚无可信发布完成点时不冒险自动恢复，备份留供人工处理。
- guard 测试验证相同序列号接受、变化/零序列号拒绝，C# 编译、PowerShell 解析和 diff 检查通过。
- 尝试 mobile 完整互操作，在 Capture 阶段遇到 `Chromium internal source RFH token` 而拒绝，未运行测试写入/清空，未绕过保护。真实备份恢复及格式互操作仍未验收；此项不阻止继续 RD 等独立审查。

## 2026-11-10：实现重审——剪贴板测试保护层

- 系统互操作测试运行前审查发现 Capture 把任意注册格式视为可按字节恢复，无法保证私有/进程相关元数据的生命周期。现仅允许已知 HTML/RTF/URL 和项目自定义格式，未知注册格式在任何测试写入前拒绝。
- WriteRaw 原来用空窗口 owner 打开后清空并发布，不符合 Windows SetClipboardData 合同；改为传入同一 STA 上创建的 Control.Handle，并在空 owner 时先拒绝。
- 新增无剪贴板访问的 C# guard 测试，验证已知格式允许、Ole Private Data/DataObject/任意未知格式拒绝及空 owner 拒绝，测试通过。
- 尚未运行系统互操作：恢复前仅比较文本不足以识别外部图片/文件更新，需继续修复并验证；不能宣称备份恢复已经安全验收。TESTS 已明确该限制，本轮未读取或更改用户剪贴板。

## 2026-11-10：实现重审——CF_HDROP 列表边界与对齐

- 剪贴板/OLE 文件列表原解析器在最后一条路径终止后耗尽负载时仍接受，未要求额外列表终止符；UTF-16 路径通过外部偏移强转宽字符指针，还依赖地址对齐。
- 两个消费者共用 windows_dropfiles.h 的按字节扫描器，要求完整双 NUL 终止，逐次读取均检查剩余字节，使用 memcpy 读取可能未对齐的 UTF-16 单元。路径转换结果只在整份负载有效后交付；保留数量/长度上限。ANSI 转换直接写最终字符串，减少临时 wstring 分配。
- 私有内存测试覆盖 ANSI/UTF-16、奇数偏移、单 NUL、路径截断、半个 UTF-16 终止单元、越界偏移、空列表及数量/长度边界；/W4 /WX 测试与原有 DND 原生测试通过。未访问系统剪贴板或操作真实输入设备。
- 引擎源码构建与 mobile/safe OLE 注入（含 Timeout 取消）通过；各仓库 diff 检查通过。首次集成编译暴露公共头文件缺少 shlobj.h，已补齐直接依赖后重新构建成功。剪贴板全格式互操作和 RD 异常路径的整体审查仍待完成。

## 2026-11-10：实现重审——DIB 可选颜色表

- 对照 Microsoft Bitmap Header Types 确认 24/32 位 DIB 也可以有颜色表。原实现将 biSize 后的数据直接当成像素，忽略 biClrUsed，导致有表时读错位置，也可能把不完整像素负载判为有效。
- 布局校验先用剩余字节数限制 RGBQUAD 表项数量，再计算像素起点并验证完整行存储；实际解码使用这个经过校验的偏移。
- 独立测试覆盖 24/32 位、普通/V4/V5 头部长度、两项颜色表、表后像素截断和 DWORD_MAX 表项数量；/W4 /WX 测试与引擎构建通过。未访问系统剪贴板；不代表完整 V5 色彩配置支持。文件列表终止符/对齐与后续 RD 审查仍未完成。

## 2026-11-10：实现重审——剪贴板 DIB 有符号尺寸边界

- 图片解析原来在验证尺寸前计算负高度的绝对值，LONG_MIN 会触发有符号整数溢出。提取生产布局校验函数，先限制宽高与头部范围，再计算绝对值、补齐行跨度和像素存储边界。
- JNI 分配图片失败时保留原先的异常，不再覆盖为“不支持的布局”。独立原生测试覆盖正/负高度、24 位行补齐、截断最后一行、LONG_MIN、零和超限高度、超大宽度与头部；/W4 /WX 测试及引擎构建通过。测试不访问系统剪贴板。
- 文件列表的双 NUL 终止和 UTF-16 偏移对齐、DIB 可选颜色表布局仍需进一步检查；本轮不将整个格式解析审查标记完成。

## 2026-11-10：实现重审——剪贴板分配异常的所有权

- 审查发现 full-format 准备阶段的 vector/string 分配异常可以绕过 HGLOBAL 手工释放，文件列表/ANSI URL 读取中的异常可以绕过 GlobalUnlock；相关 JNI 入口未捕获 std::bad_alloc。
- 新增不可复制的 PreparedExtras 和 LockedGlobal 作用域守卫；发布列表先预留最多 34 个条目，再取得 Windows 内存，每块取得后立即纳入所有权。成功转交的句柄置空，异常仅释放未转交块。五个会分配 C++ 容器的 JNI 入口捕获 bad_alloc 并报告 Java OutOfMemoryError。
- 独立 `test-clipboard-ownership.cmd` 以 /W4 /WX 编译通过，验证抛出异常后的两块私有内存释放、转交块保留、借用块解锁且不释放；未访问系统剪贴板。引擎源码构建通过。此证据不覆盖全部 JNI 内存不足、格式互操作或畸形输入边界，仍需继续审查。

## 2026-11-10：实现重审——输入取消夹具的多余移动

- 上轮输入取消失败已定位：夹具的 mouse(false) 在发送松开前总是注入 MouseMotion；按键尚按下时这会合法地产生 MOUSE_DRAGGED，即使坐标不变。调用栈来自 GodotView 普通鼠标派发，不是 cancelInput；日志 `review-input-cancel-drag-trace.log`。
- 夹具改为仅在按下前定位，松开只发送按钮事件；保留全部取消、零意外拖动、后续激活和资源断言。Java 探针增加失败时事件详情，移除临时调用栈输出。没有更改生产输入语义，也没有放宽断言。
- 修正后的 mobile/safe、mobile/separate、gl_compatibility/safe 三档均通过；使用模块内合成事件，不操作真实输入设备。此前输入取消失败的待查项至此关闭，整体重审仍需继续剪贴板和 RD 异常路径。

## 2026-11-10：实现重审——Glass 输入接收线程退出

- 扩展 GlassSchedulerProbe：终止 Glass 后保持原生宿主运行，检查输入与帧接收线程都在 2.5 秒测试期限内退出。修复前稳定报 `Receiver survived Glass termination: Godot input receiver`，日志 `review-input-stop-before.log`。
- 输入接收循环增加 volatile 运行标记，Glass 退出时清除；原生等待返回后及已排队输入任务执行前检查。保留原生等待的 1000 ms 超时，不增加空闲轮询频率，也不在 FX 线程阻塞 join。线程退出还取决于操作系统调度，不承诺严格一秒期限。
- 保留 Media 的源码 SDK 构建、扩展 Glass scheduler 测试、50 轮 PulseStop 测试通过。文档与 TESTS 同步更新。
- 补充输入取消回归发现 mobile/safe 和 mobile/separate 都在 phase 5 报 `Cancellation generated a drag gesture`。将 JFX HEAD 的旧 GodotApplication 编译为临时模块补丁后，mobile/safe 仍复现同一失败（`review-input-cancel-baseline.log`）；该问题不由本次退出标记引入，但仍需查明原因，不能将输入取消回归记为通过。未操作真实鼠标/键盘，未放宽断言。

## 2026-11-10：实现重审——Windows GL 窗口竞态

- 32 次原生 Window 创建、切换 VSync、立即销毁复现异步 GL 回调使用已销毁 HWND/HDC，日志反复报告 Error 6（句柄无效），且仍打印 PASS。保留 `window-immediate-close-before.log`，测试包装器明确拒绝任何 ERROR。
- Windows GL manager 用递归互斥保护窗口表和当前上下文读写；延迟操作查找失败直接取消，不再通过 map 下标插入空窗口。切换失败不更新 current；销毁与交换缓冲区同步，空 current 不解引用。
- 检查引擎清理顺序为 RenderingServer finish/delete 后再销毁 DisplayServer，因此排队 callback 所持 manager 指针在该生命周期内有效。
- 引擎构建、立即关闭 safe/separate 两档、OpenGL separate 的 12 轮 Native Exit 均通过。后续仍需完成输入停止、剪贴板及 RD 异常路径的剩余重审。
- 补充验证：Runtime 源码构建与 OpenGL/separate 立即关闭通过，引擎 mobile/separate 立即关闭和 OpenGL/separate 原生多窗口像素验证通过。Runtime 夹具首次运行因缺少全局脚本缓存被错误门禁拒绝；脚本现先调用源码引擎导入项目，再执行 Runtime，不忽略该错误。多窗口像素探针改用当前 drawQuads 接口的单位变换，原有颜色、隐藏/恢复、关闭后不复活及资源释放断言保持不变。

## 2026-11-10：实现重审——Godot 诊断热路径

- 重查 Godot 基线 `420dfdc1..0b19501` 的 10 个变更文件和 Java 输入/调度线程。确认 Canvas / RD 资源阶段计时原来在未启用诊断时仍执行，且资源阶段会定期输出日志。
- 将这些额外时钟读取、累计计数和日志统一受已有 `GODOT_JFX_OFFSCREEN_PROFILE` 开关控制；正常资源更新调用保留。
- 引擎源码构建通过。Viewport/mobile/safe 的两轮 VFX 各完成 68 次切换：关闭时 27198 次离屏绘制且无阶段日志；开启时 24518 次并包含 OFFSCREEN/RES 两类阶段报告，两轮开关断言均通过。日志 `review-offscreen-profile-0.log` / `review-offscreen-profile-1.log`。开启轮有 548 个失焦样本，且不是同条件改前对照，不能据此宣称 FPS 改善。
- 待继续核对的范围：Windows GL 上下文异步调用与窗口立即销毁的时序、输入接收线程的终止保障、剪贴板新增格式的所有权与边界、RD 异常/资源失效路径和最终整体验证。已完成的缓存/OLE/诊断改写证据见以下记录；不能据这些局部结果声称整体重审完成。

## 2026-11-10：实现重审——原生 Mesh LRU 与绘制所有权

- Prism Mesh 缓存改为单次内容哈希加完整 COW 顶点/颜色比较；淘汰由全表扫描改为链表 LRU，预算为 48 MiB 输入负载与 4096 条目。预算不覆盖 ArrayMesh/驱动对象或仍被命令保留的资源。
- 共享 `BoundedLruCache` 处理替换计费、超大条目拒绝、插入失败回滚和加法溢出边界；`test-bounded-lru.cmd` 以 /W4 /WX 编译并通过资源释放、碰撞、淘汰及故障注入检查。
- 容量压力测试复现命令引用已被缓存淘汰的 Mesh：屏幕绿色图形消失，GLES 报 mesh null，日志 `review-mesh-retention-before.log`。窗口绘制列表现按 RID 去重持有 Mesh 引用，清空/销毁命令后释放，缓存淘汰不再破坏待绘制内容。
- 引擎构建、OpenGL/mobile 两种 `mesh-transform -CachePressure` 及 RD separate 回归通过。测试提交 4097 个不同屏外图形，强制淘汰最早可见图形的缓存项，再验证它仍正确显示。整体重审仍未完成。
- Runtime 源码构建和 RD safe 回归通过；mobile render-targets、OpenGL shader-cache、OpenGL M1 Surface 生命周期测试也通过，后者日志 `review-surface-lru.log`。

## 2026-11-10：实现重审——Mesh 解码身份

- RD Mesh 解码 memo 由裸地址键改为 ObjectID。每次解码 miss 先撤销该地址的 GPU 顶点身份缓存，覆盖对象地址复用及 memo 淘汰后的重建路径；不通过增加 Mesh 强引用延长 GPU 对象寿命。
- 读取属性前检查单个表面、四顶点批次范围及 UV/颜色/custom 数组长度，避免不完整输入导致越界。注册 Mesh 保持既有不可变约定。
- 将无实例参数的 Mesh 绘制入口与宿主实例参数入口分开，增加脚本绑定以直接验证生产 RD 解码路径。
- 新增 96 个短生命周期 Mesh、每个重复绘制两次、全图颜色读回与对象销毁断言。引擎构建、引擎 safe/separate/no-ring/no-batch 与 Runtime safe RD 回归、OpenGL mesh-transform 均通过。本轮 Runtime 夹具导入正常。整体重审仍未完成。

## 2026-11-10：实现重审——离屏纹理存活登记

- 检查 RD 纹理失效路径，`test-godot-view.ps1 -Renderer mobile -Transform` 在 RD/debug 下通过；记录一次底层视图变化，未记录 `RD_BATCH_DEAD_SET` 或白色回退。这是该场景证据，不证明所有更新/销毁场景安全。
- 修复直接创建的 JavaFXRenderTarget 未登记存活纹理的问题：RD 和 Viewport 初始化成功后登记，销毁时在释放 RD 对象前移除正确的纹理身份。过去只有通过宿主 sampler retain 的纹理才会登记，直接 copy_target 会重复重建绑定。
- 增加 RD UniformSet 创建计数诊断，并在四轮完整像素复制回归后断言只创建一个绑定；继续验证短生命周期源的保留和释放。
- 引擎构建通过；引擎 safe/separate/no-ring/no-batch 和 Runtime safe 的 RD 回归通过。Runtime 首次夹具导入在引擎退出阶段报 `EditorNode::is_cmdline_mode` singleton null，日志归档 `review-runtime-import-failure.log`；确认进程结束后重跑，同一导入和 GPU 回归通过，尚未确定该导入退出问题的根因。
- 下一步仍需检查 RD mesh 解码 memo 的裸指针键生命周期、原生 Mesh 内容缓存和跨线程交接；整体重审尚未完成。

## 2026-11-10：实现重审——性能采样器

- 将 VFX 翻页探针中的采样器提取为独立 `ThreadStackSampler`：仅工作线程修改统计，停止时中断睡眠并等待退出，之后才生成不可变报告。避免旧的同步 Map 内可变计数与无等待报告读取竞争。
- 拒绝非正间隔和非法环境值；采样异常终止并报告，不再吞掉异常高速重试。最多保留 4096 种调用栈，额外观察计数明确输出；排序使用 long 比较，移除每帧正则类名处理。
- 报告保留栈顶八层与观察到的线程状态，包括 Java 等待/休眠帧；这是墙钟采样，不是 CPU 利用率，线程状态和栈的两次观察也并非原子快照。启用采样明确标记 `diagnostic_only=true`。
- `test-stack-sampler.ps1` 检查非法间隔、可中断停止、报告稳定性、种类预算、异常传播与栈顶/等待帧保留，已通过。VFX 启动失败也会执行采样线程关闭。整体重审仍未完成。
- 最终采样器在 RD/mobile/safe 下完成 68 次原始 VFX 页面切换并正常退出，100 ms 采样、全程前台、丢弃 0；包含栈顶和等待帧的报告归档 `artifacts/logs/review-stack-sampler-transitions.log`。此次启用诊断，不作为无采样性能改善证据。

## 2026-11-10：实现重审——OLE DataObject

- `QueryGetData` 改为元数据查询，不再复制负载；自定义 MIME 前缀检查移除临时字符串分配。
- 修复 `SetData(..., TRUE)` 插入分配失败时错误释放调用方介质的路径；复制模式仍清理自己的副本。补齐不支持的 lindex 校验。
- `GetData`、格式枚举和克隆的 STL 分配失败转换为 HRESULT，枚举输出失败时清空，Next 缺少必要计数输出时拒绝且不前进。
- `test-dnd-drag-image.cmd` 以 /W4 /WX 构建并通过新增故障注入、所有权计数、复制隔离和枚举测试，原 shell 8×6 拖放图像注册仍通过。未操作真实输入设备。
- 引擎源码构建通过；`test-drag-drop-ole-inject.ps1 -Renderer mobile -Timeout` 通过。Windows 自定义模块启用 /EHsc，故障处理不只在独立测试的编译配置中生效。整体重审仍未完成。

## 2026-11-10：实现重审——Java 几何缓存

- 以拥有顶点/颜色快照的明确条目类型替代 `long[]`。哈希候选必须通过完整数组比较；不同内容的哈希冲突发送未注册的普通几何，不覆盖已有句柄。调用方复用数组不会改变缓存快照。
- 顶点验证与哈希合并为一次扫描；缓存关闭时仍做完整验证，但不计算哈希。
- 缓存硬性限制为默认 1024 条目（可配置）及每编码器 32 MiB 数组数据，另有对象/Map 开销。保留 64 次提交闲置期限；无法淘汰时拒绝接纳新缓存项，继续正常绘制，避免旧软上限在持续新几何下膨胀。
- 注册条目在完整命令写入后添加；释放旧条目也先成功写入释放命令，再修改预算和索引。
- 编码器测试扩展确定性碰撞、可变数组所有权、条目和字节预算、闲置退休。旧 SDK 在碰撞断言处失败，保留于 `artifacts/logs/review-geometry-cache-before.log`。此测试通过反射检查编码状态，GPU 生命周期仍需宿主测试。
- 最终源码 Media SDK 构建通过；`test-render-command-validation.ps1` 全部断言通过。将容量设为 4 项后，RD/mobile/separate 的 Node Shader GPU 测试通过（`review-geometry-cap4-node-shaders.log`），覆盖容量不足时继续发送普通几何。
- 同样 4 项容量下 OpenGL Node Shader 测试通过（`review-geometry-cap4-node-shaders-gl.log`）。完整 VFX 68 次切换通过，RD/mobile/safe、2560×1600、60 Hz、`unfocused=0`：Pulse 57.255 FPS、宿主呈现 54.730 FPS、P95 21.072 ms、P99 75.116 ms、最大 191.007 ms。上传 43668 次、引用 41689 次；硬容量会增加未缓存传输，不能声称总体性能提升或稳定 60 FPS。归档 `review-bounded-geometry-transitions.log`。整体重审尚未完成。

## 2026-11-10：实现重审——批量绘制记录

- `FlushList` 不再拆分出八个并行数组，改为通过 COW 引用共享 `RecordedDraw` 数组。提交时不再逐字段追加、分配并维护一致的索引；渲染线程直接消费完整命令，屏幕采样快照扫描找到首项后即可结束。
- 保留原有同步完成点及延迟回收时序。COW 共享减少此处的数据装配工作，但仍需实际基准才能判断整体 FPS 变化。
- 调试参数读取改为先检查对应 float 的真实字节范围，再用 `memcpy` 读取，避免旧的长度判断不足与对齐假设。
- 原始 VFX 页面切换基准（RD / Vulkan mobile / safe，2560×1600，60 Hz）完成 68 次切换：Pulse 57.808 FPS，宿主呈现 53.937 FPS，P95 20.842 ms，P99 57.010 ms，最大 328.540 ms。`unfocused=497`，且没有同条件改前配对数据，不能据此认定性能提升或通过帧率验收。日志归档 `artifacts/logs/review-rd-shared-draws-transitions.log`。
- 引擎源码构建以及引擎 `safe`、`separate`、`-NoBatch` 和 Runtime `safe` GPU 回归通过。整体重审仍在进行，后续继续检查 Java 几何缓存和跨线程任务所有权。

## 2026-11-10：实现重审——RD 数据缓存与延迟回收

- 顶点/Uniform 缓冲区缓存增加完整字节比较；顶点数组比较缓冲区与顶点数量，Uniform 绑定比较 Pipeline、主纹理和完整参数。哈希只定位候选项，不再决定资源身份。
- 修复 Uniform 参数哈希冲突时仅移除缓存项、丢失仍有效 GPU UniformSet 所有权的路径。替换项进入延迟回收队列，已排队绘制结束后才释放；已被设备级联销毁的绑定跳过重复释放。
- 缓冲区字节采用 COW 引用保留；现有条目容量上限保留，但这不是固定字节预算，也未测量新的 FPS 或长期内存趋势。
- 扩展 RD 回归：合法 Uniform 名 `Ab`/`BA` 产生相同 Dictionary 哈希，384 次交替绘制同时超过 128 项 Uniform 缓冲区容量，逐像素检查结果。此场景验证替换/淘汰时序，不等价于穷举 64 位字节哈希碰撞。
- 当前引擎构建通过；GPU 回归 `safe`、`separate`、`-NoRing`、`-NoBatch` 全部通过。Runtime 源码构建及 `-Runtime` 回归也通过；RD 模式下 `test-node-shaders.ps1 -Renderer mobile` 通过，截图为 `artifacts/reference/godot-node-shaders-mobile-safe.png`。整体代码重审尚未完成。

## 2026-11-10：实现重审——RD Shader 身份缓存

- 在此前整体审查范围上继续检查性能和资源安全；本条不是整个重审完成声明。
- 已复现等长、同 `String.hash()` 的两个不同 Shader 被缓存混同：期望绿色的实际 GPU 读回为红色，旧产物日志为 `artifacts/logs/review-shader-collision-before.log`。
- 源码身份改为完整字符串比较后分配编号；八槽快速缓存持有 COW 字符串引用，避免依靠已释放地址及首尾字符猜测内容。共享 Pipeline 清理时同步释放源码缓存。重复绘制仍走指针命中路径；尚未重新测量帧率，不能宣称 FPS 提升。
- 扩展 `test-rd-regressions.ps1` 的场景，三轮交替绘制哈希冲突的红/绿 Shader，并检查完整读回图像。
- 验证：引擎源码构建通过；RD GPU 回归引擎 `safe`、引擎 `separate`、Runtime `safe` 均通过。日志分别为 `rd-regressions-safe.log`、`rd-regressions-separate.log`、`rd-regressions-safe-runtime.log`；本轮未运行真实键鼠测试。
- 后续重审仍包括顶点/Uniform 缓存的完整键比较、批量提交数据和线程所有权、Java 几何缓存、Windows OLE/输入及 Godot 子模块改动；现有共享 Pipeline 缓存仍无固定容量上限。


## 2026-11-09：审查补充——图片池 FIFO 回退

- 继续核对同一整体 diff，发现 ImagePool 在 FIFO 模式删除空引用或丢失图片后仍递增索引，跳过右侧移入的可用图片。修复两处删除分支，保持默认 LIFO 与同尺寸选择顺序。
- 新增无 GPU、无 GC 时序依赖的 test-image-pool-reuse；修复前 FIFO scenario=0 稳定失败（review-image-pool-before.log），重建 Media SDK 后 FIFO/LIFO 四场景均通过，编码器校验回归仍通过。
- 同步 TESTS、Prism、验收记录。该结果证明回退模式的复用正确性，不证明新增帧率收益；前轮 RD 性能和物理验收限制保留。

## 2026-11-09：整体 diff 审查后的缺陷修复

- 范围：9ae5a635（不含）到 b0bed86 的整体变更及子模块。首轮只审查，随后修复；未改 VFX 业务代码，未运行真实键鼠测试。
- RD 顶点环：纠正循环条件，复用前将开放 pass 的 recorded 绘制提交，再更新纪元；buffer_update 通过渲染线程 FIFO 传递拥有独立生命周期的数据，修复 separate 的线程拒绝错误。
- 恢复 initialize 的脚本默认参数；矩形/复制顶点补齐 z，矩形颜色预乘 alpha，允许 RD 目标作为复制源。复制源保留到提交结束并释放，避免早退分支长期持有源引用。
- uniform 默认值由 Godot ShaderLanguage 解析后按 std140 布局保留，再应用显式参数；修复单元素数组和 ivec2/3/4 参数打包。新增生产路径像素测试覆盖默认值、覆盖、array[1]、ivec3。
- Java 编码器先校验顶点及 float 范围再更新缓存，重复非法输入不再生成未注册 QUADS_REF。OLE 使用可取消排队任务，超时后跳过未开始的 Enter/Drop，并排队清理旧目标状态；已开始的用户回调不强行中断或撤销。
- 引擎、Media SDK 源码构建通过；RD safe/separate、ring off、batch off、Runtime 专项通过；编码器、OLE 正常及 Vulkan/OpenGL 超时恢复通过；原 render-target、node-shaders 双渲染器及 RD node-shaders、protocol 通过。新增语料完整性检查后 corpus 为 186 exact / 76 edge / 0 failed。
- 更新 TESTS、初学者架构、当前验收、RD 计划及 Glass/Node Shader 文档，将历史结论与当前修复结果分开。未重新测量性能，历史 P95 27.6ms 仍不满足 <25ms 目标。

## 2026-11-09（Robot 测试改造）：三个物理夹具转为默认合成输入

- 起因：用户确立规则——尽量不新编写 robot 操作键盘鼠标的测试，运行此类测试前须经用户同意（已写入 AGENTS.md 约束节）。随后对全部 Robot 依赖夹具做可改造性分析并落地转换。
- **test-window-drag.ps1**：拖拽输入本就全是合成注入；Glass Robot 仅在物理光标碰巧停在拖拽路径时把它挪开（防止窗口在静止光标下移动产生无按键 MOUSE_MOVED 打断手势）。改为反向避位：探针只读光标位置（被动，不构成输入抢占），把测试舞台放到光标所在的屏幕另一半，窄屏兜底再垂直分离。Robot 调用完全移除。
- **test-hover-flicker.ps1**：默认改为合成模式——GDScript 按探针发布的 HOLD/GAP 标题注入 motion 事件（HOLD 指向按钮中心，FUSION GAP 指向窗口外 (-120,-120)）；`-Robot` 保留物理档（GODOT_JFX_HOVER_ROBOT=1）。关键实证：注入事件坐标是**物理像素**空间（FX 逻辑 ×2），与采样器的 ×2 约定一致；逻辑坐标注入会落在半位（首跑 enters=4/8 即此原因，坐标修正后 enters=8/exits=7 精确符合预期）。合成模式 flicker 25/1446=1.7%（阈值 5%，与 robot 档 1.3-1.4% 基线同档）。
- **test-physical-drag.ps1**：默认改为合成模式——探针把手势命令（SYNTH DRAG/RESIZE）发布为窗口标题，GDScript 注入按下→10/8 步快速移动（按当前窗口位置换算局部坐标，复刻"窗口跟不上光标"）→释放；断言拖动/缩放精确跟随路径和（合成坐标无 OS 屏幕钳制，期望即路径和 -180/740×576，实测完全相等）及无 gesture-killer 事件。`-Robot` 保留物理档（GODOT_JFX_PHYSICAL_DRAG_ROBOT=1），独占 OS 投递语义覆盖（光标屏幕边缘钳制、WM 进出通知抑制）。合成模式的同步协议教训：探针必须等待手势事件计数而非几何稳定——按下后窗口保持静止，朴素 settle 检查会在首次注入前误判完成（本轮首败即此竞态，与事件投递无关）。
- 不转换项及理由：test-robot.ps1（被测对象就是 Robot 实现本身）、test-drag-drop-external.ps1（跨进程 OLE 模态循环本质需真实拖拽；负载路径已有非物理的 ole-inject 覆盖）、test-drag-drop.ps1 `-Robot` 与 test-vfx-table-scroll.ps1 robot 档本为可选物理档，默认即合成。
- 验证（全部默认合成模式，不触碰输入设备）：window-drag gl/mobile 双渲染器（avg lag 2.0 帧）、hover-flicker mobile safe+separate 双线程、physical-drag gl_compatibility。物理 `-Robot` 档本轮未运行（按新规需用户同意）；该路径仅被 `if(ROBOT_MODE)` 包裹，编译覆盖、逻辑未动。
- TESTS.md 三分类与三条目、AGENTS.md 约束示例列表同步更新。

## 2026-11-09（菜单扫过 hover 结案）：对照实验证伪前提——非 Godot 缺陷，实验改动已回退

- 用户报：demo menu 页快速扫过按钮，原生 JavaFX 每个按钮微微亮起，Godot 版可能完全无反应，疑与"事件帧率"有关。引擎侧确证 Godot 默认 use_accumulated_input=true（input.cpp:1654），一帧内连续 MouseMotion 合并为最新位置一个事件，中间按钮收不到 enter/exit；遂实验性在宿主初始化时关闭积累（GODOT_JFX_ACCUMULATED_INPUT=1 可退回）。
- 证伪：带该实验改动的 Godot demo 实测依旧无微亮；继而用原生 JavaFX（Win Glass + D3D 管线，同一份 vfx 类）对照，同样无微亮。结论：该菜单页的 hover 过渡在快速扫过的极短停留内本就不可见，与平台/事件分发密度无关——最初"原生会微亮"的观察不成立（可能来自不同页面或扫速）。
- 处置：实验改动三处（宿主输入配置、javafx_host.h 字段）全部回退，宿主恢复引擎默认输入合并；引擎重建，protocol、hover-flicker(mobile/safe)、vfx 冒烟验证通过。若未来在其他场景确证 Godot 与原生 hover 密度有差异，调查起点：Input 积累模式 + FX 脉冲批处理（一帧内多个事件在同一脉冲消费，过渡进度为零即不可见）。

## 2026-11-09（悬停冻结结案）：宿主主循环停顿定性 + 脉冲饥饿补救

- 用户报两个悬停缺陷（按钮快速移入停住后变亮闪回/冻结、菜单扫过残留）。先修正 zcode 遗留的 FX_GAP 探针缺陷（计时起点被清零、永不打印，其"末轮零命中"不具结论性），再补 HOST_GAP/HOST_PHASE/HOST_SYNC 宿主探针（GODOT_JFX_HOVER_TAP=1），四轮人工复现采集（repro-hover-manual.ps1）闭环：每个 FX 线程空等（FX_GAP 队列空、124-580ms）都有等长的宿主主循环停顿（HOST_GAP）配对——断流点在引擎 draw 段（管线编译/显存分配突发随热身衰减；另有零分配零编译的呈现等待类 100-264ms），FX 与渲染线程无辜。
- 修复（Java 侧调度韧性）：GodotPulseScheduler await 超时 1000→100ms，超时时投递合并补救脉冲（原路径丢弃），动画在宿主停顿期间按墙钟推进；补救投递上限 3 次/段停顿，与有界渲染队列容量对齐，防止模态级长停顿顶到 submit 10s 死线。
- 验证：修复后宿主停顿仍在（7 次）但 FX_GAP 归零；回归 protocol/hover-flicker 双线程（flicker 1.3-1.4% 持平 ea840f1 基线）/pulse-stop/glass-scheduler/vfx 冒烟全绿。顺路修复：test-hover-flicker.ps1 缺 vfx classpath（dba34a5 起即坏）与探针舞台未置顶导致的 enters=0 假败。菜单扫过残留六轮零复现，按同族处理；如再现需单独捕获查 hover EXIT 丢弃分支。详见 rd-direct-backend-plan.md 结案章节。

## 2026-11-07（第三批补遗）：求值顺序缺陷复盘与修复后诚实数字

- 第三批首测 44.4fps/22.9ms 系错误行为下测得：set_material 跳过条件先把局部 slot.material 赋为新值再比较——比较恒假、fresh path 上重绑全部被跳过，复用槽位 item 沿用前任住客的材质→跨用例传色（composite-edges 154 像素差异、effects/stage/render-targets/shader-cache/mesh×2/godot-view/intro 十项连锁失败）。二分（env 关 RID 缓存 / 关跳过）定罪跳过；RID 缓存无缺。修复：赋值前捕获前任 material 再比较。
- 修复后完整回归 16/16 全绿（含 composite-edges D3D 逐像素对照）。诚实数字：翻页 42.5fps（维持 42-43 区间，跳过收益被真实材质切换抵消）；真实输入拖拽 p95 26.0→23.6ms、p99 67.0→63.8ms（8 事件/帧）；纯渲染地板历史最优（59.9fps/p50 16.7/p95 18.4/p99 41.2）。另把材质缓存键升级为全量身份校验（哈希仅分桶，命中时深比较 shader RID + 参数字典，碰撞旹盐化键共存）。引擎重建。
- 经验教训落档：性能数字只有在像素回归全绿后才可采信；首个 44.4fps 就是在渲染错误的二进制上测的。

## 2026-11-07（第十批）：最后杠杆 API 阻断定论——逐 item 多纹理与共享纹理数组在公开渲染 API 中不可实现

- 对最后杠杆（效果输入移出材质参数）做引擎 API 勘察：① canvas_item_add_mesh 仅接受单一纹理（rendering_server.h:850，单采样器绘制已走此路径，即我们的 QUADS 纹理），效果链着色器同时绑定 2-4 个采样器，无逐 item 机制；② 画布着色语言支持 sampler2DArray，但公开 API 无法创建“数组层渲染目标”（离屏视口只渲染 2D 纹理），效果 pass 无法填充数组层而不进入 RenderingDevice 级渲染（即已被 P0 spike 证伪前提的 RD 直连项目）；③ 实例 uniform 不支持采样器，最后的标准旁路关闭。
- 结论：多纹理画布材质在纹理变化时的描述符集重建（~120µs/pass 主项）是平台成本；翻页 ~44fps 地板现由九个已实施杠杆的同二进制 A/B、视口周期成本 spike、GPU 再归因与本 API 勘察四类证据共同支撑。剩余路径均为引擎级工作（RD 直连或 API 扩展），已在立项文档与本记录中完成证据链闭环。

## 2026-11-07（第九批）：材质补丁杠杆落地——实施正确但收益噪声级，机制定位到描述符集重建

- 实施：acquire_material 新增补丁路径——同 shader 同参数形状、仅纹理 RID 不同时，对缓存材质 material_set_param 变更项（一次纹理仅透明的 uniform-set 重建代替“创建+全量参数+排队”），材质 RID 稳定使槽位 item 同时跳过重绑依赖更新；命中前校验新 RID 存活；GODOT_JFX_MATERIAL_PATCH=0 可退。
- 验证：像素门六项全绿（含 composite-edges 对 D3D）；翻页 44.5/44.5 开 vs 44.0 关——在 42-45 噪声带内，远低于估计的 5-8fps；重建计数仅 4.70→4.50s。机制定位：~120µs/次的主体是 update_parameters_uniform_set 内部的描述符集重建，纹理 RID 真变化时无可避免——补丁消除的只是对象创建与 UBO 更新。表格拖拽真实输入历史最优（p50 16.6/p95 22.7/59.9fps）。
- 彻底消除该成本需把效果输入移出材质参数（逐 item 纹理或共享纹理数组）——协议/渲染路径级变更，已记录为本杠杆之外的剩余路径。引擎重建，完整回归后台验证中。

## 2026-11-07（第八批）：GPU 时间剖析完成再归因——呈现管线排除，单 pass 提交 CPU ~314µs 为主项（材质重建 ~120µs 为其最大分量）

- 落地 GODOT_JFX_GPU_TIMING=1：宿主窗口视口经 viewport_set_measure_render_time 按 tick 采样（过渡夹具输出 VFX_TRANSITION_GPU 汇总）；离屏目标的逐视口时间戳因 ~18 pass/帧 溢出引擎时间戳池而无法回收（记录为测量限制）。JavaFXRenderTarget/RenderSurface/Host 增 量测接口与 offscreen_gpu_us 统计。
- 数据：窗口 GPU 均值 0.50ms/帧（p50 0.505/max 2.8，1492 样本）——呈现管线占帧预算 3%，**排除**；批量围栏后 draw_sync_us 已为纯 CPU 提交墙钟（7.72s/24,580 次 = **~314µs/pass**），分解：材质 uniform 重建 ~120µs（4.5s）、canvas 脏处理 ~45µs、编码 ~30µs；~18 pass/帧 → 提交 CPU ~5.4ms/帧；process_us 68%。帧数学：5.4ms + 合成/呈现 + Java 脉冲 ≈ 23ms ≈ 43fps，与实测一致。
- 修正：此前“材质重建常量 ~13%”的表述低估了其占位——它是单 pass 成本的最大分量；下一杠杆已明确（未启动）：纹理 RID 变化时不再重建效果材质——对缓存材质做参数补丁（material_set_param 一次重建代替创建+N 参数+排队）或将效果输入移出材质参数；上限 ~3s/运行，估匼 5-8fps。

## 2026-11-07（第七批）：P0 spike 证伪 RD 直连立项前提——视口周期单价 6-38µs，重写收益上限 ~30µs/pass

- 两次架构决策询问未获回答后，选择了不替用户做决策、但能改变决策质量的 P0 可行性 spike：新增 JavaFXHost.benchmark_offscreen_cycle(items,count)（ClassDB 暴露，自建视口/画布/K 个绘制项，2016x928 效果分辨率，400 次循环批量围栏）。rd_spike 场景驱动，不测试不运行。
- 实测：0/1/4/16/64 个绘制项的单周期成本 5.9/6.7/8.2/18.3/37.5µs——比立项评估的 ~440µs 低两个数量级。修正归因：440µs 是含逐 pass 全设备同步等待的墙钟时间（与相位计时 draw_us~30µs/pass 、批量围栏不改变 fps 的两个早期证据一致）。
- 结论落档：RD 直连重写的可回收上限 ~30µs/pass CPU，不足以关闭 17-20fps 的翻页差距——立项文档已改为“前提已证伪，按原定理由不启动”，原评估保留为历史与参考。剩余差距需按新候选归因（效果 pass 的真实 GPU 工作量、呈现管线、材质常量）重新立项。此批同时保护了用户免于一个 4-6 周级无收益重写。

## 2026-11-07（第六批）：逐 pass 同步流水化——可实施切片落地，量化如实为噪声级

- 实施：每 pass 全设备 rs->sync() 改为 GODOT_JFX_PASS_SYNC_INTERVAL 可调（默认 0 = 依赖帧尾批量围栏；k>1 每 k 个 pass 等一次）。第三批时的 39.1fps 负结果在实例参数/材质修复落地后不再复现；今日六次运行 42.4-45.2fps 全部落在同一噪声带。像素门与回归全绿（composite-edges 对 D3D、effects×2、render-targets、shader-cache、stage、intro -AllPages、table-scroll）；引擎重建。
- 诚实结论：同步间隔的差异在运行间方差之内，未产生可复现收益。验证器要求的完整 RenderingDevice 直连路径（用自建 draw list 替换视口渲染周期，把单 pass 降到 render-pass begin/end + draw 的价格）是渲染器重写级工程，六轮数据链（Java 空闲、pass 数低于原生、视口渲染单价主导、材质重建稳定 ~13%）足以立项但无法作为桥接层补丁落地。翻页 42-45 vs 原生 62、拖拽真实输入 p95 22.5-24.7 vs 地板 18.4-18.7 的差距在当前架构下已到实际地板。

## 2026-11-07（第五批）：效果图像池帧亲和——实施完毕，量化证据将剩余差距锁定在引擎级视口渲染单价

- 实施第四批记录的杠杆：ImagePool.checkOut 从队头优先（FIFO，等尺寸图像逐帧轮换位置）改为最近归还优先（LIFO 帧亲和），GODOT_JFX_IMAGE_POOL_LIFO=0 可退；修复编译错误（迭代器变量残留）。jfx 重建；像素门六项全绿（composite-edges 对 D3D、effects 双渲染器、render-targets、shader-cache、stage）。
- 诚实量化：翻页 42.7（LIFO）vs 41.8（FIFO）——落在近四个杠杆所有配置的 41.8-44.4 区间内；queued_materials_us 未降（4.81 vs 4.69s/37s）。原因由 sampler-RID 追踪 + 池量子化可见：滑动过渡期效果链图像尺寸籷级（32px 量子下的移动脏区）逐帧变化，尺寸类进出池使键无论 tie-break 如何都保持新颉。拖拽地板 direct p95 18.6/real p95 24.3 与前批持平。robot 模式本轮 displaced=0（窗口未在前台，环境不满足其前置条件，非代码回归）。
- 五批优化的总结论（数据链完整）：Java 侧空闲（栈采样）；离屏 pass 数已低于原生（27,675 vs 70,428）且低于帧预算；值常量材质重建已消除（实例参数迁移）；采样器驱动的重建在尺寸轮换下无法用 tie-break 消除；剩余差距（翻页 42-44 vs 原生 62；拖拽真实输入 p95 23.6-24.7 vs 地板 18.4-18.6）主项是每次离屏 pass 的视口渲染单价（引擎架构级，需 RenderingDevice 直接路径），次项为每帧真实重绑的 ~13% 常量。后续动作若继续压温翻页，应直接立项 RenderingDevice 渲染后端而非再调桥接层。

## 2026-11-07（第四批）：实例参数材质迁移——实施完毕，归因升级到效果链图像池的 RID 轮换

- 落地预定杠杆：新增 javafx_shader_rewrite.{h,cpp}，目标路径着色器编译时把值 uniform 改写为 instance uniform（按源串 memo 名单；采样器保留在材质级；>16 个值 uniform 不改写）；SHADER_STATE 常量分流到 target_instance_params，槽位绘制经 canvas_item_set_instance_shader_parameter 直写实例缓冲（无队列无重建）；共享 item 的立即模式 surface 路径保留原始源（同 item 多绘制无法逐绘制实例态）。GODOT_JFX_INSTANCE_UNIFORMS=0 可退。过程中修复两个工程问题：ClassDB 绑定方法不接受 HashMap 指针参数（拆出 draw_prism_quads_with_instances 内部函数）；状态分流块替换后残留重复 else。
- 正确性：像素门全绿（composite-edges 对 D3D、effects 双渲染器、render-targets、shader-cache、mesh、m1、composite、drag-drop、vfx-table、intro -AllPages、table-scroll 共 13 项）。引擎重建。临时诊断（miss 分类计数、sampler RID 追踪、rewrite dump）用完即删。
- 诚实量化：值常量驱动的 uniform 重建已消除（_update_queued_materials 5.47→4.56s/37s），但翻页 fps 不变（43.2 开 vs 43.3 关）、拖拽分位数不变。归因：miss 分类 cold=100%（同键 RID 变分类不可达，因 RID 变会改键），且 sampler RID 追踪证据确凿：字形图集/掩码纹理 RID 完全稳定，而效果链 inputTex 每条命令指向不同的池化 RT——材质冷 miss 全部由此驱动。下一杠杆已升级并记录：Prism 效果图像池（ImagePool）的帧间亲和复用，使同一效果位置跨帧拿同一块 RT，从而让材质键跨帧稳定。剩余与原生 62fps 的差距仍由视口渲染单价与每帧真实换绑主导。

## 2026-11-07（第三批）：单价瓶颈实施优化——逐 pass 成本相位剖分与两项修复

- 承接定位结论实施实际优化。给 Godot 子模块加相位计时（GODOT_JFX_OFFSCREEN_PROFILE / RES_PHASES，env 门控）：每 pass ~500µs 中 canvas->update() 占 225µs、实际渲染 96µs；update 内部 _update_queued_materials（排队材质 uniform 重建）占 4.4s/37s，脏 item 遍历仅 12ms（3.1 万项）——材质风暴而非几何。
- 修复一（槽位重绑）：材质 RID 未变时跳过 canvas_item_set_material（每次重绗都把 item 入依赖更新队列）。实测 draw 相位 96→34µs/pass（-65%）。
- 修复二（RID 材质缓存）：acquire_material 恢复缓存含 RID 参数集（上一轮因“悬空 RID 白屏”禁用的路径）：条目记录其 RID 并在命中时对照静态存活集校验（由 surface dispose/版本换代/release、RT与 scene view 析构共同维护；RID 值不复用，退休条目自然失效）；缓存压力时先清扫失效条目再按插入序淘汰。命中即证明所有绑定纹理仍存活——以构造方式消除旧隐患。
- 实测：翻页 42-43→43.8-44.4fps；真实输入拖拽收益最大（hover 重绘场景）：p95 26.0→22.9ms、p99 67.0→59.6ms（8 事件/帧），与纯渲染地板的差距从 +40% 缩至 +19%（地板 p50 16.5ms/59.9fps）。几何缓存 256→1024（上传 -7%，fps 不变）。
- 如实登记无效实验：safe 模式跳过逐 pass sync 更慢（39.1 vs 42.9，该等待兼任 CPU/GPU 节流）；突发预算 10ms/64 批次噪声内。剩余 4.4s uniform 重建由真实每帧变化的效果/裁剪链常量驱动（~4.4 万次/运行，每次 ~100µs）——属 Prism 材质级 uniform 模型，下一个架构杯杆是映射到 Godot 逐实例参数（需重写生成着色器）。
- 引擎重建；完整回归批后台验证中。

## 2026-11-07（第二批）：原生对照定位翻页/拖拽差距——单价缺口定论

- 用户实测反馈：翻页仍有较大差距、表格远不如原生、滚轮相对流畅但按住拖动卡顿。本轮完成定位而非盲目优化，数据链完整可复现。
- 同基准原生对照：VfxTransitionProbe 直接跑 D3D 管线（同一份 SDK 源码）——原生 62.0fps/p50 16.0/p95 16.9ms；Godot 端 43.1fps/p50 17.9/p95 59-61ms。重页 R19（50 行表格页）：原生 p50 16ms vs Godot p50 72.7ms（持续性 4.5 倍每帧成本，非尖峰）。
- 决定性证据一（Java 无罪）：嵌入式 JNI JVM 无法 jcmd 附加（尝试失败），探针内建进程内栈采样器（GODOT_JFX_STACK_SAMPLE）：过渡期 QuantumRenderer ~88% park、FX 线程 ~97% 空闲——瓶颈不在 Java侧。
- 决定性证据二（pass 单价）：BaseShaderContext 新增 TARGET_SWITCHES 计数器，两条管线同基准打印——原生 70,428 次目标切换（~30/帧） vs Godot 27,675 次（~19/帧，LCD 优化后更少）：**pass 数更少却更慢**。每次切换宿主付 ~440µs（draw_offscreen_2d 完整视口渲染，Vulkan 命令编码），D3D SetRenderTarget 为 µs 级——即 kimi 会话预言的“每次重绘单价”架构差距，量级比 30-50 倍。宿主主线程 71% 忙（render_offscreen 9.5s+几何 5.6s+纹理 2.0s+目标 2.3s / 37s）与此一致。
- 排除项：separate 渲染线程更慢（35.2 vs 43.1，同步开销无补）；宿主突发预算/批次上限 env 化（GODOT_JFX_PASS_BUDGET_US 默认 4000、GODOT_JFX_BATCH_CAP 默认 16）A/B 提到 10ms/64 仅噪声内——队列排空也不是约束。收窄需渲染后端每 pass 低于视口渲染的成本（RenderingDevice 级路径或 Godot 引擎轻量视口），属引擎架构级工作，如实登记。
- 拖拽三层定位：夹具新增驱动模式（GODOT_JFX_DRAG_MODE=direct/real/robot，real 可配 GODOT_JFX_REAL_EVENTS/帧；robot 走 Glass Robot 真实 OS 光标，诊断用需前台）。实测：direct p95 18.5ms；real 1/8/32 每帧 24.1/26.0/25.7ms；robot 25.2ms——p50 全不变，事件速率非主因；真实输入比 direct 多 ~1500 次全量上传：指针移动合成 enter/exit，VFX hover 高亮随指针移动，批次内容真变化——这是真实重绘工作（原生同样做，单价低）；滚轮不动指针故流畅。Glass-Godot 输入本身合并正确（批量 drain + 帧锁脉冲，无每事件脉冲风暴）。
- 回归：本轮改动为诊断工具与 env 化参数（无默认行为变化），引擎重建，关键回归批后台运行中。

## 2026-11-07：架构级修改落地（绘制调制协议 + 编码器连续状态抑制）

- 应用户要求实施“架构级修改”（kimi 会话方案 C 的可落地形态）。前置分析：VFX 翻页动画每帧同时平移 + setOpacity 淡入淡出（VScene.applyAnimation），opacity<1 时 Prism renderOpacity 把 extraAlpha 烹进每个顶点颜色字节——颜色每帧都变，几何内容哈希全部未命中，淡入淡出期每帧全量重编码+重建网格。
- 协议：QUADS/TEXTURED_QUADS/QUADS_REF 负载各加 4 字节 f32 绘制调制（校验有限且 0..1）；Java 端 BaseShaderContext 新增 vertexColorModulation 钩子，Godot 管线返回 1 并记录批次调制值，调制值变化时先 flush（不变式：一个 flush 批次恰好一个调制值）；顶点颜色不再含 opacity→淡入淡出期内容字节稳定→命中 QUADS_REF。宿主端用 canvas_item_add_mesh 的逐命令 modulate（预乘缩放，与烹焙同数学，差一次舍入，在 D3D 对照±2/255 容差内；复用槽位命令本就逐 pass 重录，无需槽位键变更）。GODOT_JFX_DRAW_MODULATE=0 可回退烹焙行为做 A/B。
- flush 不变式会在调制值切换处拆分批次（实测批次总数 +6%），拆出的新批次要重发完整着色器状态——补上编码器连续状态抑制：完全相同的背靠背 SHADER_STATE(11)/CLIP(12) 发送被跳过（宿主本就把它们当持久状态）；追踪在 TARGET_SELECT/END_PASS/发布/帧开始/clear/纹理销毁处失效（对齐宿主侧状态重置点），进程内出现第二个编码器则永久禁用（两流在提交点交错）；GODOT_JFX_STATE_SUPPRESS=0 可关。新增 quads_uploaded/quads_referenced 常驻计数器。
- 实测（同二进制交替 A/B，全部 unfocused=0）：68 页翻页基准新架构 41.6fps 均值 vs 旧行为 42.2（p50 17.4-18.5ms 两者重叠）——如实报告为帧率中性；命中率实打实升（引用 44868/上传 23565 vs 41514/25659，全量上传 -8%）；表格拖拽 59.9fps 持平，p95 19.4→18.5ms、p99 42.4→41.1ms 略优。翻页帧率的真实约束再次确认为每 presentation ~15 个圆角裁剪离屏 pass（原生 D3D 同款），编码侧工作不改变该天花板。早期单次对比曾出现 32 vs 44fps 的差距，经交替重跑证明为环境噪声（用户在机器旁、窗口失焦采样不平衡），已用 unfocused 计数作有效性门槛重做。
- 修复两个实现过程缺陷：ClassDB 绑定未给新参数 DEFVAL（add_prism_quads/draw_prism_quads 报参数数不匹，m1/mesh×2/render-targets/shader-cache 五项连锁失败，补 DEFVAL(1.0f) 后全过）；协议负例测试误用 1.0f 作越界值（合法边界，改 2.0f）及 QUADS alpha 字节偏移算错（176→196）。
- 验证：FRAME_PROTOCOL_PASS（含 alpha 解码断言与越界/非有限负例）；像素正确性——stage、effects×2、composite、composite-edges（源码构建 D3D 管线逐像素对照）、shader-state、readback 及最终全量回归批均通过；引擎/JFX 三端重建。

## 2026-11-06（夜）：大表格拖拽与翻页深度优化（LCD 文本目标采样改走渲染器后台缓冲）

- 用户反馈大表格 demo（_06c，50 行×7 列）拖拽仍卡顿、翻页仍有卡帧。新建免前台夹具 `scripts/test-vfx-table-scroll.ps1`（VfxTableScrollProbe 直接驱动视口自身 DragHandler，无 OS 输入、无焦点依赖）：空闲窗口 + 96 脉冲锯齿拖动，输出帧间附加分位数、宿主计数器快照与原始 gap 序列。实测 62/62 个测量 tick 在其他窗口持焦点（Notepad 前台）时完成，fps 58.0。
- 定量剖析（临时 createRTTexture 调用栈插桠 + 命令级 Profile）：拖拽时 117 个离屏 pass/脉冲，其中 ~97 个来自 Prism LCD 文本的每文本节点 lcdBuffer 往返（initLCDSampleRT 拷贝目标背景→画字形采样，每次往返 = 一次目标切换 + 一次 draw_offscreen_2d）；其余 ~20 个为 VFX 圆角裁剪（形状组合，Prism 原生同样走离屏）。`-Dprism.lcdtext=false` A/B（117→20）确证归因。
- 优化（保留 LCD 亚像素抗锯齿，非关闭）：`GodotShader.loadPrism` 加载时改写二段 LCD 着色器（dstColor → hint_screen_texture，采样 SCREEN_TEXTURE/SCREEN_UV，坐标由 fragment() 传入）；新增管线能力位 lcdScreenSample（BaseShaderGraphics 跳过 initLCDSampleRT 拷贝，GodotGraphics/GodotContext 置位，GlyphCache 不再需要 lcdBuffer 尺寸）；readback 路径不变。Godot 渲染器对 hint_screen_texture 材质每个渲染过程只在首次使用时快照一次后台缓冲（material_screen_texture_cached）。`GODOT_JFX_LCD_SCREEN=0` 可回退原行为做 A/B。
- 同二进制实测（GODOT_JFX_LCD_SCREEN=0 为对照）：拖拽离屏 pass 11420→1900（-83%），fps 54.6→59.6，p95 25.0→19.4ms，p99 97.4→51.2ms；256 脉冲长拖中实际滚动 sweep 全部 ≤17ms（满帧率）。四种渲染器/线程组合全部显著改善：mobile/safe 54.6→59.6、mobile/separate 51.1→55.2、gl_compatibility/safe 25.9→47.8（p50 32.9→16.8ms，GL 的后台缓冲拷贝远比其逐往返视口渲染便宜，获益最大）。翻页基准 30.9→35.0fps、p50 25.5→20.3ms、最差页（同一张大表格页）7.5→11.5fps。字形正确性：表格页截图目视检查无彩色镬边/重影，test-vfx-intro -AllPages（逐页像素变化断言）、test-vfx-table、四组合 table-scroll 夹具全通过。
- 语义差异如实登记：目标快照从每文本节点一次变为每渲染过程首次 LCD 绘制时一次；仅同一过程内后续文本叠写先前文本像素时似低读旧背景（非重叠文本像素一致）。其余已知成本不动：圆角裁剪离屏（原生同款）与翻页期真实变化内容的 Java 侧重编码；着色器状态协议级去重（SHADER_REF）经评估不实施——实测它在完整翻页基准中仅占 0.16s/37s，收益不抵协议复杂度。另登记：合成拖拽末段“顶部钳制保持”的 no-op 脉冲存在 18→50ms 单调爬升（仅出现在夹具自身的尾部钒齿段，真实滚动段不受影响；GC 日志证明拖拽期间仅 1-1.5ms Young GC，20-29ms Full GC 均为 VFX 启动期 System.gc()）。
- 回归：protocol、dnd-drag-image、stage、effects×2、mesh-transform×2、m1、render-targets、composite、shader-cache、drag-drop、glass-scheduler、scroll-wheel、godot-view 全部通过（drag-drop 首跑一次出于“Done action differs in case 0”，与改动路径正交且单跑/二跑均稳定通过，判定为串行批量下的时序偶发）。JFX 一端重建（本轮无宿主 C++/protocol 改动）。

## 2026-11-06（晚）：kimi 遗留三问题收尾 + 渲染几何去重协议

- kimi 会话（11-06 08:30）遗留三问题处置完毕。问题3 滚轮速率（kimi 已修，scroll-wheel 回归本轮再次通过）。问题2 拖动/缩放鼠标移出窗口：kimi 的加固（held_buttons 按位掩码重放 + 按住期间抑制进出通知）首次完成物理验证 `test-physical-drag.ps1` PASS——标题栏拖动与右下角缩放在光标高速逃出窗口后精确跟随（finalY=-14=期望、740x576=期望）。探针两处断言修正：期望值按 Windows 屏幕钳制后的实际光标位置推导（物理光标停在 y=0，不可能是 -166）；带按键 MOUSE_EXITED 是 Quantum 拾取变化的标准合成（原生 JavaFX 同款、经三处插桩证明不来自 Glass 层任何 EXIT 生产者），只有无按键 MOUSE_MOVED 才终止手势，事件记录窗口限定 press..release（释放后 OS 补发移动不算）。
- 问题1 父级容器移动卡帧：命令级剖析（GODOT_JFX_PROFILE_COMMANDS）显示宿主几何命令应用 11.2s/36s（encode 的 65%），kimi 的内容寻址网格缓存 A/B 无效证明成本不在网格重建。本轮实施协议级几何去重：帧协议新增 QUADS_REF(29)/GEOMETRY_FREE(30)，QUADS/TEXTURED 携带几何句柄；Java 编码端按内容哈希（256 项 LRU、64 次提交闲置后退役）对未变批次只发句柄引用；宿主 GeometryLedger 与纹理账本同款的提交期投影校验（引用必须存活、句柄至多注册一次、退役恰好一次）；离屏 target 增加跨 pass 持久绘制槽（CanvasItem+材质复用，仅命令列表与 draw_index 刷新）与无 RID 参数材质缓存。实测宿主几何应用 11.1s→5.2s（-53%），vfx-frames 59.93fps 满帧不退化；68 页翻页整体帧率持平（38.9 vs 39.2，噪声内）——剩余瓶颈为 Java 侧 Prism 每帧全量重编码与每 presentation 30-70 个离屏 pass，属已记录的架构级限制，如实登记不虚报。
- 过程中修掉四个真实缺陷：QUADS 声明长度少 4 字节（新句柄字段）；材质缓存把采样器纹理 RID 固化在键里导致命中悬空 RID、效果链全白（修复：含 RID 参数的材质不缓存）；`canvas_item_set_visible(false)` 与待渲染的 UPDATE_ONCE 离屏 pass 竞争导致效果输出白屏（修复：退役槽改用 canvas_item_clear 清命令列表）；canvas_item_clear 会重置已录制的 clip 状态导致复用槽越界覆盖（修复：复用槽重录时补 set_custom_rect/set_clip）；另有 shader 首建未置 persistent 标志使首材质进 per-pass 生命周期。
- 测试不依赖置顶：按用户要求梳理并落档。既有两种免前台模式（Godot 合成输入；模块测试钩子 ole-inject）延续为首选；物理输入夹具（external/physical-drag/-Robot/robot/file-dialog）保留置顶并在 TESTS.md"前置"列注明。TESTS.md 新增三分类说明（可后台/需前台焦点/需物理桌面空闲）。实例改造：drag_drop.gd 的 phase-0 门槛移除 has_focus()（合成输入按窗口 ID 投递、与 OS 焦点无关）——此前用户在前台使用其他应用时该夹具会停在 case 2（本轮实测复现，前台为 ZCode），移除后在其他应用持焦点时七用例全 PASS；input_lifecycle/input_cancel/native_stage_input 的 focus 检查是焦点语义断言本身，保留不动。
- 回归全绿：FRAME_PROTOCOL（含新几何账本与线格式用例）、effects×2、mesh-transform×2、m1、render-targets、composite、shader-cache（资源清点公式计入槽+材质，暴露 get_draw_slot_count/get_cached_material_count）、stage、stage-churn、scroll-wheel、glass-scheduler；引擎/JFX 三端重建。

## 2026-11-06：拖放预览图（setDragView）接入 shell 拖拽图像助手

- 承接 11-04 中断批次（usage limit 截断）遗留的"拖放预览图未完成"项。此前 `Dragboard.setDragView` 一旦在拖动离窗后触发 OLE 交接即抛 UnsupportedOperationException（`application/x-java-drag-image` mime 被 startExternalDrag 拒绝）。
- 实现：Quantum 发布的拖拽视图缓冲（大端 w/h 信封 + BGRA、大端偏移对）经 `dragStartExternal` 新增参数传入宿主；`run_dnd_source` 在 `DoDragDrop` 前用 `IDragSourceHelper::InitializeFromBitmap` 注册 32bpp HBITMAP 预览（偏移缺省取图像中心，对齐 Win Glass setDragImage 路径）；OLE `DataObject` 补齐 `SetData`（仅 HGLOBAL，接受 shell 写回的 DragImageBits/DragContext，替换同格式旧值并在枚举/GetData 中暴露）。指针仍在宿主窗口内的本地段不绘制预览（架构限制，已记录）。
- 验证：引擎/JFX/Media 四项源码构建通过；新增 `tests/native/dnd_drag_image_test.cpp` + `scripts\test-dnd-drag-image.cmd` 原生组件测试通过（shell 助手写入的 DragImageBits 尺寸/偏移与发布的 8x6@5,3 完全一致，SetData/GetData/EnumFormatEtc 往返成立）；`test-drag-drop-ole-inject.ps1` Vulkan/safe、`test-glass-scheduler.ps1` 通过。`test-drag-drop-external.ps1` 观察器设置拖拽视图，helper 端在 DragEnter 断言 `image=8x6@5,3`。
- 环境一度再次阻塞 GUI 夹具（锁屏前台 + ~60ms/帧平台期，SendInput 不达应用；bisect 证明 case-2 停滞在变更前二进制上同样复现，属环境性）。用户解锁后串行重跑全部通过：`test-drag-drop-external.ps1` Vulkan/safe、gl_compatibility、-Runtime 三组合 PASS（helper 日志 `DND_HELPER_ENTER ... image=8x6@5,3 bytes=216`，即跨进程观察到 shell 写入的拖拽图像位），`test-drag-drop.ps1 -Renderer mobile` 七用例 PASS。经验：Runtime 夹具的 headless 导入在残留旧版 `.godot` 缓存时报 `EditorNode::is_cmdline_mode` null singleton，删除 `artifacts/runtime-dnd-external/.godot` 后恢复。
- 顺带：windows_dnd.h 自定义格式名窄化改为显式转换（/W4 /WX 下无警告，行为不变）；核查 system menu —— Win 参考实现同样不提供（仅 Mac 覆盖 `_supportsSystemMenu`），维持显式报错即为平台一致行为，不算缺口。

## 2026-11-05：VFX 交互四问题修复（悬停光标/拖拽跟随/帧率平台期）

- resize 把手悬停光标不变：JavaFX 光标命令只设置 OS 光标，Godot Viewport 在每次鼠标移动时用 Input 默认光标（箭头）重新断言，把 JavaFX 光标刷掉。godot 子模块新增 `Input::set_default_cursor_shape_quiet`（只改默认值、不合成假移动事件），宿主在每条光标形状/图像命令后同步默认值，JVM 停止时恢复原形状。顺带标注上游 BDIAGSIZE/FDIAGSIZE 字形与枚举名互换的现状。`tests/reference/ResizeCursorProbe.java` + `scripts/test-resize-cursor.ps1`，gl safe/separate 通过。
- 标题栏拖拽窗口跟不上鼠标：输入事件在帧间到达却要等下一个 host tick 才被排空，窗口移动命令再等下一帧 NOTIFICATION_PROCESS 才应用；且 Quantum 的 press-drag-release 手势因按钮事件修饰位不含 post-event 状态而在 press 时即建即毁。三件套修复：(a) `javafx_host.cpp window_input` 对鼠标按钮事件归一化修饰位（press 置位/release 清位，1→32、2→64、3→128、8→256、9→512，对齐原生 wParam 语义）；(b) `frame_protocol.h` 新增 input_tick/pulse_input/await_input_tick，六个输入入队点 pulse，`GodotBridge.awaitInputTick` JNI，GodotApplication 新增 "Godot input receiver" 守护线程即时 drainInput（AtomicBoolean 防重入，先复位再 drain 保证不丢 pulse）；(c) host command 增加 frame_pre_draw 第二应用点（两种渲染线程模式下都在主线程触发，separate 由渲染线程自守卫）。`tests/reference/WindowDragProbe.java` + `scripts/test-window-drag.ps1` 实测四种渲染器/线程组合平均滞后 2.0–2.07 帧、最大 3；探针会用 Glass Robot 短暂挪动物理光标保持其在标题栏上（日志带 `DRAG_CURSOR_WARPED` 标记）。
- 翻页/动画帧率低（~33 Hz 平台期复现）：动画基准掉到 32.75（文档记载 11-03/04 同机同管线 59.95）。证据链定位到机器级 present 节流而非 FX 桥：裸 Godot 探针（host_frame_probe.gd，不加载 JavaFX）Vulkan 32.83、GL 32.43 同病；同机原生 D3D JavaFX 62.5 正常；vsync-off 4774 fps、vsync-off+max-fps-60 干净 60.10。宿主新增一次性节奏健康检查 `check_vsync_pacing`（RUNNING 后跳过 2s 启动期、采样 2s 帧间隔，窗口非全屏且 vsync=ENABLED 且平均帧间隔 >1.4× 刷新周期时）切到 `VSYNC_DISABLED` + `Engine.max_fps=refresh`（窗口模式 present 由 DWM 合成，不撕裂），打印 `JAVAFX_VSYNC_FALLBACK`，`GODOT_JFX_VSYNC_FALLBACK=0` 可关闭。动画基准 32.75→58.05（旋钮关闭回到 32.75，证明检测生效）。
- 翻页内容成本单列：新增 `scripts/benchmark-vfx-transitions.ps1`（VfxTransitionProbe，68 次翻页逐页统计）。回退生效后轻页 40–55 fps，重表格页仍 10.8（冷）/31.2（暖）：每帧全量重编码（encode ~13 ms/帧）、逐 draw batch 重建 ArrayMesh、每 presentation 30–70 个离屏 pass，单帧成本超帧预算，列为已知限制，属架构级重构暂不动。
- 回归（回退生效后）：window-drag×4、resize-cursor×2、image-cursor、godot-view(mobile/Transform)、drag-drop、glass-scheduler、run-vfx-demo -Smoke 全部通过，window-drag 滞后不变。
- 遗留：非 borderless `window_set_size` 存在 +4px 框架差值怪象（op2 先于 op15）；次级窗口移动仍每帧应用；平台期触发源未确定（机器环境，建议排查虚拟显示适配器/驱动状态）。

## 2026-11-05：环境解锁后收尾，拖放/剪贴板批次全部验收通过

- 两大环境阻塞解除（用户解锁/重启后会话恢复正常）：`test-clipboard.ps1` 在 Vulkan/safe 连跑 6/6 通过、打包 Runtime 通过；`test-drag-drop-external.ps1` 在 Vulkan/safe、OpenGL/safe、打包 Runtime 全部通过（含 OLE 自定义格式双向断言）。打包 Runtime 二进制在自定义格式 JNI 签名变更后曾过期，已重建。
- 重跑暴露并修复四个真实缺陷：`ClipboardSnapshot.cs` 的 `WideCharToMultiByte` P/Invoke 缺 `CharSet.Unicode`（字符串被按 ANSI 封送，ANSI URL 对照字节全错；Java/原生侧经诊断证明无误）；`dnd_helper.cpp` 未实现 `EnumFormatEtc`（入站自定义格式靠枚举源 IDataObject 发现，.NET/OLE 标准对象都实现它，测试端点补齐）；`QuantumClipboard.hasContent` 查 IMAGE 时在 HTML mime 上提前返回（上游式修复，继续扫描其余 mime，修复富写"图片丢失"）；两处 Windows 剪贴板瞬态按原断言加重试吸收（peer 的 `GetDataObject()` 空返回、GD 场景 `DisplayServer.clipboard_get()` 最长 2 秒）。
- 文档同步：acceptance-status 解除两条"会话阻塞"记录并登记修复清单；glass-godot 更新剪贴板备份保护（注册格式按名快照）与瞬态重试说明；bridge-protocol 补自定义格式 String 解包语义与入站枚举要求；TESTS 更新备份范围。目标全部七项完成，触屏键盘出现效果与拖放预览图仍归物理/后续验收项。
- 新增免物理输入的 OLE 组件测试 `test-drag-drop-ole-inject.ps1`：JavaFXHost 增加 `simulate_external_drop` 测试入口（模块自产 OLE 源 DataObject 直接喂给真实入站委托 DragEnter→Drop），OleInjectProbe 断言 text/URL/文件/自定义格式 Dragboard 读回一致；mobile/gl/separate 三组合通过，应用内拖放回归保持通过。它覆盖 OLE 负载路径（含自定义格式枚举发现），跨进程 COM 封送与模态 OLE 循环仍由 Robot 夹具负责。

## 2026-11-04：拖放/剪贴板/输入/媒体/渲染补齐批次

- 系统剪贴板补齐：CF_HDROP 文件列表（复用 windows_dnd.h 的 DROPFILES 编解码）、CF_DIB 图片（BITMAPINFO+像素，Java 侧 PixelReader/WritableImage）、ANSI-only URL 读取回退（ACP 转换，与 OLE extract 同款）、`application/x-godot-custom-*` 自定义格式（RegisterClipboardFormatW 双向，16 MiB 上限与 NUL 校验沿用）。新增 `clipboardWriteFull`/`clipboardReadFiles`/`clipboardReadImage`/`clipboardReadCustom`/`clipboardCustomFormats` JNI；拖放侧 OLE DataObject/extract 同步支持命名自定义格式。测试备份保护（ClipboardSnapshot）扩展到能备份/恢复 CF_HDROP 与 CF_DIB。
- 验证被环境阻塞：本机会话 `OpenClipboard` 对所有进程持续 ERROR_ACCESS_DENIED（无属主窗口，锁屏态），脚本停在备份阶段、未写入任何系统内容；需解锁后重跑 `test-clipboard.ps1` 收尾。
- 另一环境阻塞：explorer 持有的全屏 topmost `LockScreenBackstopFrame` 吞掉所有注入指针（SendInput 点击实测到达数为 0，LogonUI 在跑而会话名义未锁；重启 explorer 后该窗口被原样重建）。test-robot、`test-drag-drop.ps1 -Robot`、`test-drag-drop-external.ps1` 因此不可验证；`.gd` 合成输入、渲染与像素读回全部正常，证实非代码回退。期间曾结束后重启 EcoPaste/ShareX/CmdPal/cbdhsvc/explorer，均已恢复。
- 虚拟键盘：`_requestInput/_releaseInput` 不再抛 pending，走宿主命令 26/27 到原生，经 ITipInvocation 调起 TabTip、release 关闭 `IPTip_Main_Window`。新增 `test-virtual-keyboard.ps1`（VirtualKeyboardProbe 经 WindowHelper.getPeer → TKStage.requestInput/releaseInput）验证链路不抛异常、宿主持续 tick，PASS；真实触屏出现效果归入物理验收。
- 媒体冒烟：`test-media-audio.ps1` 新增 `-Codec wav|mp3|aiff|all`；`tests/native/make_audio_fixture.cpp` 本地编码 2 秒 440 Hz 样本（Media Foundation MP3；手写 AIFF 容器，Python 3.14 已无 aifc）。MediaAudioProbe 的时长断言改由 `GODOT_JFX_MEDIA_EXPECT_MS`/`GODOT_JFX_MEDIA_TOLERANCE_MS` 驱动，MP3 实测 2058 ms（编码器 padding，容差 300）。三编码全 PASS。
- GL/separate error 170 修复：separate 渲染线程持有全局唯一共享 GL 上下文时，主线程 `window_set_vsync_mode` 与子窗口创建尾部的 `wglMakeCurrent` 报 ERROR_BUSY。把这两处编组到渲染线程执行（`RenderingServer::call_on_render_thread`，Variant 无指针类型故打包 int64；单线程/safe 自动转同步直调，ANGLE 分支不动），`gl_manager_windows_native.cpp` 的 `window_create` 不再自行 make_current。`test-drag-drop.ps1` 四种 渲染器/线程组合全部 PASS 且无 ERROR 行。

## 2026-11-04：跨应用 OLE 拖放落地

- Godot 已为每个窗口注册 `DropTargetWindows`，二次注册会被 Windows 拒绝；改为在 `DisplayServerWindows` 注入拖放委托，模块在既有 IDropTarget 回调内接管，不支持的格式回退 Godot 文件拖放。
- 拖出：离开全部托管窗口后由 Godot 主线程运行 `DoDragDrop`，IDataObject 暴露 Unicode 文本、HTML、RTF、URL 与 CF_HDROP 文件列表；完成事件以 kind 20 输入记录返回执行效果。拖入：OLE 回调经有界等待转发 FX 事件线程，卡死降级为 DROPEFFECT_NONE。
- 调试发现并修复三个问题：测试环境为 3120×2080@200%，Robot 坐标是 FX 逻辑坐标（×2 物理），helper 窗口改为按系统 DPI 缩放放置；Quantum 层文件列表是 String[] 路径而非 List<File>；OLE 上调会 Attach 调用线程，必须配套 Detach，以释放 JNI 线程关联。
- `test-drag-drop-external.ps1` 以真实 Win32 OLE 端点验证双向 text/URL/文件与 Escape 取消，Vulkan/safe、OpenGL/safe、打包 Runtime 均通过；应用内七用例（注入与 Robot）和调度回归保持通过。
- 拖放预览图、自定义格式、系统菜单、虚拟键盘、image/file/custom 剪贴板格式仍未完成；剪贴板集成测试重试仍被备份保护挡住（用户剪贴板含图像格式），未修改系统内容。

## 2026-11-04：Unicode URL 剪贴板接入

- URI_TYPE 映射为 Windows UniformResourceLocatorW，UTF-16 保留中文及补充字符。URL 与文本/HTML/RTF 可共同发布；所有数据在清空系统剪贴板前完成校验与分配，非法 NUL 不替换原内容。
- 扩展剪贴板观察器及 Windows Forms 对照端，覆盖 URL-only、格式发现、双向 Unicode 交换、清空和拒绝非法参数。源码引擎与 Media SDK 构建通过，Java 测试编译通过。
- 系统互通测试在写入前的备份阶段被 Windows error 5 拒绝，未启动测试宿主、未修改剪贴板；日志 clipboard-url-preflight.log。增加原生错误码诊断，不绕过保护、不把构建成功视为互通通过。
- 图片、文件列表、自定义系统剪贴板格式和 ANSI-only URL 输入仍待实现，其余拖放与 Glass 工作继续。

## 2026-11-04：Windows 原生文件对话框及 owner 链模态修复

- 接入 Windows IFileDialog：单选、多选、保存、目录、扩展名过滤器及取消；Godot 主线程提供 Stage HWND，独立 COM 线程显示系统界面，FX 等待期间继续处理事件。
- 对照 FileChooser 源码契约，将直接 owner 禁用扩展为完整所属窗口链，平衡 Glass 禁用计数；测试检查祖先窗口禁用、对话框关闭后恢复。
- 宿主停止时关闭对话框，并在等待 COM 线程结束期间处理同步 Windows 消息，避免恢复 owner 时相互等待。测试脚本使用随机标题和进程校验限定操作对象，失败只终止本轮测试进程。
- Media SDK、Runtime 源码构建通过。六用例在引擎 Vulkan/OpenGL safe、Runtime Vulkan safe 通过；Runtime Vulkan safe 的 StopHost 用例也通过，取消返回、停止返回和资源清零断言成立。
- 同步 README、TESTS、架构、Glass 与验收文档。一次一个选择器仍是明确限制；跨应用 OLE、拖放反馈、其余 Glass 缺口与最终验收继续进行，不将本轮通过视为整体完成。

## 2026-11-04：Robot 与系统输入拖放验证

- 实现 GodotRobot：复用源码 WinRobot 的键盘/按钮/滚轮，按宿主屏幕模型转换坐标，Windows GDI 按需桌面截图与 cursor JNI；未新增 Glass 窗口或事件循环。
- 引擎、Media SDK 源码构建通过。Robot 桌面测试在 Vulkan/OpenGL safe、Vulkan Runtime safe 通过，2× DPI，截图已检查；输入 A 经 Enter 提交并在 Escape 后保留。
- 初次测试暴露前台拒绝和 Windows 输入体验候选窗口遮挡；最终夹具置顶、提交/关闭候选后继续，不修改输入法配置，不以宿主注入代替桌面输入。
- test-drag-drop 新增 -Robot，七个既有断言在 Windows 系统合成输入下通过，默认同批输入注入模式仍通过。失败路径也安排释放按键、恢复鼠标并关闭窗口。
- 外部 OLE 数据交换、拖放预览/反馈、文件对话框、其他 Glass 缺口和最终 VFX/物理验收仍未完成；总体目标保持进行中。


## 2026-11-04：拖放应用内流程与输入回归迁移

- 当前目标为补齐拖放、Glass 兼容性与最终验收；本轮尚未完成整个目标。
- 新增 GodotDragClipboard，接入 Glass 标准 enter/over/leave/drop，保留手势数据、COPY/MOVE/LINK 和独立完成条件的 FX 事件泵。已轮询输入批次中的剩余事件可在拖放等待期间继续执行。
- 修复 DRAG_DONE 与松键/Scene 拆除的顺序，拒绝、Escape、源/目标窗口隐藏都只完成一次。系统剪贴板不受影响。
- test-drag-drop 七用例在 Vulkan safe/separate、OpenGL safe 通过。OpenGL separate 的断言完成，但原生上下文切换报错 170，因此仍失败，未放宽错误门槛。
- 源码 Media SDK 构建、native-stage-input、Glass scheduler、host-stop 通过。旧 input-cancel/lifecycle 注入器仍依赖嵌入窗口，迁移到原生窗口 ID、局部坐标/DPI、焦点与原生窗口计数后，保留 Java 断言且串行回归通过。
- 仍需完成 Windows OLE 跨应用交换、拖放预览/光标与 OS 遮挡目标判断，以及 Robot/文件对话框/系统剪贴板格式等 Glass 缺口；物理设备和最终交付验收未关闭。具体日志与范围见 acceptance-status.md、TESTS.md。


## 早期英文实施记录（历史）

This is a reverse-chronological implementation log. Statements such as "pending",
"unverified" or "unsupported" describe their entry's stage and may be superseded
by newer entries above. Use acceptance-status.md for current scope and status;
do not interpret the historical entries as an outstanding TODO list.

FINAL MEDIA/VFX REGRESSION CHECKPOINT: Current compact/R8 SDK completes 120
Vulkan/safe players plus 30 seconds idle. Pictures/AAC checks pass, resources
stay 23, texture memory 4,644,864 bytes, final zero, ETW 313, empty AAC deltas.
Handle block medians 928/920/918.5/919/917; private-MB block medians
792.062/803.066/809.497/807.342/809.798, latter-half OLS +0.196 MB/minute within
787.751–826.208 MB variation. Idle ends at 812.556 MB/900 handles. No forced GC.
Packaged Runtime 24 cycles also pass. This is bounded stability acceptance,
not arbitrary-duration/all-codec certification. Current frame/interaction/35-page
results below complete this regression scope; physical A/V and broad Glass
compatibility remain separate limits. The prior 120-cycle RGBA logs/reports are
preserved with -rgba suffix; current analysis uses the full current 120 samples.

ENCODED 1080p60 / BACKEND IDENTITY: A locally built MF encoder/independent reader
verifies 960 distinct 1920x1080 H.264 frames at 60/1 FPS. Compact command 27
transfers alpha/plane bytes without Java RGBA expansion; command 28 allocates
R8 media planes, with correct ledger accounting and YV12 red-channel sampling.
Full-plane replacement avoids old-shadow clone/blit. Source engine
and Media SDK builds pass; protocol and GL/Vulkan color/alpha/padding tests pass.
After early 23/33-FPS stages, observer off/on/off repeats reach
60.140/60.163/60.145 FPS; packaged Runtime reaches 60.037, all focused with zero
backpressure. The same-build 33-FPS plateau's trigger remains unresolved, so the
cadence recovery is not attributed solely to R8. Original VFX Vulkan/safe now
measures 59.907 compositions/s, 59.990 pulses/s, p95 18.229 ms, max 43.165 ms.
Frame runners print/verify actual Glass/Prism classes, default to Godot, and
native60 rate-1 acceptance requires >=55 draw/composition FPS. Native D3D is
explicit comparison only. See media-godot.md and bridge-protocol.md.

MEDIA TEXTURE LIFETIME FOLLOW-UP: Lower Java allocation exposed GC-dependent
cached plane retention (R8 churn fails at cycle 7, 72 resources). MediaPlayer
dispose now removes its PrismMediaFrameHandler and schedules plane disposal on
the render thread; detach alone does not free another view's shared planes.
The churn picture check reuses a WritableImage instead of creating a snapshot
RTT cache every cycle; all player/view/decoder lifetimes and assertions remain.
Rebuilt-SDK packaged Vulkan/safe completes 24 cycles, 23 resources and 4,644,864
texture bytes at every checkpoint, final zero, stable AAC registrations, no
forced GC. Video controls, VFX table/window controls and GPU motion pass. A fresh
Runtime 1080p60 repeat reaches 60.137 FPS. VFX repeats at 58.654 compositions/s,
p95 18.535 ms, max 128.103 ms: near-native average, with occasional long frames
still present. All 35 pages capture at scale 2, final zero; the contact sheet
was inspected. See the current log stems in media-godot.md/frame-benchmark.md.

AAC DECODER REFERENCE LEAK FIX: Read-only provider enumeration attributes MP4's
per-player ETW growth to Microsoft-Windows-MSMPEG2ADEC. The DirectShow pin search
leaked IEnumMediaTypes on a successful match (retaining its decoder) and IPin on
EnumMediaTypes failure. Both releases are fixed; source Media SDK rebuild passes.
Godot Vulkan post-fix 24 cycles plus 30 seconds idle pass picture checks/final
zero resources: EtwRegistration stays 313 and provider changes stay empty after
cycle 1, versus +23 AAC registrations before the fix. The handle analyzer's
--require-stable-aac rejects pre-fix evidence and accepts post-fix evidence.
The 120-cycle follow-up below passes bounded stability validation.

POST-FIX 120-CYCLE MEDIA VALIDATION: Godot Vulkan/safe completes 120 fresh players
plus 30 seconds idle, with picture checks and final zero GPU resources. ETW stays
313; provider deltas after cycle 1 are empty. No forced GC. Process handle medians
over 24-cycle blocks are 928/924/920/921/919. Private-memory medians are
800.821/827.601/837.978/832.385/834.902 MB; latter-half OLS is -0.916 MB/minute.
After 30 seconds idle private memory is 834.933 MB and handles 905. The earlier
per-player retention is no longer reproduced in this bounded workload; this is
not arbitrary-duration/codec leak certification. Packaged Runtime and OpenGL
24-cycle provider checks also pass, with no retained AAC registrations. The
runner now enforces the AAC check when Providers is enabled.

POST-FIX MEDIA/VFX REGRESSIONS: Packaged Vulkan/safe video controls (seek/EOS/
stop/replay, clip/opacity), PCM audio controls, VFX window controls, table editing
and GPU motion all pass. Fresh focused VFX Vulkan/safe is 59.917 compositions/s,
59.984 pulses/s, p95 18.175 ms, max 43.110 ms; D3D is 62.498 pulses/s, p95
16.728 ms, max 19.754 ms. Zero focus loss on both. Fresh Godot media rate-2
benchmark draws 599 frames in 10.000016 s (59.900/s), 600 callbacks, no
backpressure/focus loss. This uses a 30-FPS source at 2x; native 60-FPS encoded
content remains unverified. Latest Runtime video/table GPU images were inspected.
Computer Use initialization still fails importing @oai/sky; no alternate desktop
automation or physical audio/display measurement was used.

PCM ISOLATION: Added explicit AudioOnly churn mode with generated silent PCM,
audio-track/duration checks and playback progress; default MP4 picture checks
remain. Godot Vulkan 24 cycles plus 30 seconds idle pass. ETW registrations stay
227 at every census, unlike MP4's +1/player. Latter-half private memory spans
781.541–781.738 MB; tracked resources stay 15 and final teardown reaches zero.
This narrows the unresolved ETW growth to MP4 demux/compressed decoding paths,
without proving a specific DLL or long-run stability. No speculative native fix.
Default MP4 regression also passes 24 cycles and reproduces ETW 314 to 337.
Standalone balanced MFStartup/MFShutdown 24-pair probe keeps ETW at 103 throughout;
next isolate actual reader/codec object lifetime rather than bare MF initialization.

MATCHED HANDLE CENSUS: Native D3D and Godot Vulkan each completed 24 media-player
cycles plus 30 seconds idle using self-process PSS/NtQueryObject type counters.
EtwRegistration grows 329/340/352 on D3D and 314/325/337 on Godot at cycles
1/12/24; both retain the final count through idle. Thus each additional player
retains one registration in both backends. Provider and private-memory causality
remain unknown; resource-stability acceptance remains open. Godot decoded-picture
checks pass and final_owned=0. Added handle analyzer and an explicit backend banner
to the runner; ordinary JavaFX is a comparison, not the deliverable backend.

MEDIA GROWTH REPRODUCED WITHOUT GODOT: Added NativeD3D mode, monotonic process
sample time/Java thread count and optional post-dispose idle observations to churn.
72 cycles pass decoded-picture checks on native D3D. Private-memory block medians
501.8/511.1/537.9 MB and handle medians 861.5/908.5/929.5 grow; Java threads stay 13.
A 30-second idle drops handles 941 to 923 but private memory only 541.659 to
541.450 MB. Some delayed cleanup exists, but unresolved retention remains.
Godot is not necessary to reproduce. Analyzer supports absent Godot counters for
native runs and preserves idle data. Next inspect retained handle types/backend
lifetime; no speculative source fix has been applied.


MEDIA PROCESS GROWTH FOUND: Added test-only read-only current-process FFM counters
(private bytes, working set, handles), verified engine PID, and configurable
24-240 churn cycles. No external process control or antivirus changes. A 24-cycle
sampler check passes. The 120-cycle Vulkan run completes 336.447 s with 51 natural
GCs and final GPU zero, but process stability is NOT accepted: latter-half private
memory slope +4.716 MB/minute; 24-cycle handle medians 956.5/973.5/993.5/1018/1040.
Godot GPU/static counters recover while process resources grow. Added deterministic
report analysis; raw and analysis JSON retained. Next isolate native D3D/media
versus Godot and distinguish delayed cleanup from resource retention.


MEDIA SOFTWARE CLOCK CHECK: Added opt-in -ClockSkew diagnostic with balanced
native frame hold/release, no pixel readback. Focused ten-second Godot measurements
have median selected-frame/native-clock offsets 104.082 ms at 1x and 64.082 ms
wall-equivalent at 2x; matching D3D medians are 94.082/64.082 ms. Godot first/last
half means are 103.382/103.583 and 65.682/64.370 ms, without growing backlog in
these samples. Draw rates remain 29.999/59.907. These are software sample offsets,
not physical audio/display synchronization. Computer Use initialization was
rechecked per skill and still fails with Module not found: @oai/sky; OS desktop
capture remains unavailable. No alternative UI automation was used.


VIDEO PULSE-BOUNDARY DROPS FIXED: Timing histograms linked two callbacks in one
pulse interval to overwritten pending frames. MediaPlayer now keeps at most two
pending frames, consumes one per pulse, drops oldest on overflow and clears them
on seek/release; publication/consumption use renderLock instead of the racy dirty
flag. Media SDK rebuild passes. Focused 2x Vulkan samples 9/10/11 achieve
59.710/59.911/59.990 draws/s (zero backpressure), including 182 double-callback
intervals with all 600 frames drawn. Same-source D3D sample is 60.066. Controls
pass Vulkan/GL/Runtime, PCM passes, and 24-player Vulkan churn ends with zero
resources. Extra decoded-frame retention is bounded; A/V latency is not measured.
Earlier low-FPS logs remain as before-fix evidence. See media-godot.md.


60-FRAME VIDEO LOAD INVESTIGATED, NOT ACCEPTED: Added 2x-rate and numbered samples
to the Media benchmark. Godot varies from 40.135 to 59.615 Prism draws/s despite
roughly 60 pulses/s, zero focus loss and zero backpressure; native D3D trials are
53.047-53.699. Added raw VideoRendererListener callback counting. Instrumented
Godot runs receive 601/600/601 frames but forward/draw 597/469/417. Media clock
advances about 20 s per 10 wall seconds. Loss is before Prism drawing; callback
burst/pulse alignment/frame replacement/concurrency cause remains unresolved.
All samples retained; do not select the best run as acceptance. See media-godot.md.


MEDIA STOP/REPLAY BUG FIXED: Extended real MP4 control coverage to pause, seek
near EOS, resume/end, stop and replay with a decoded-picture check. Both native
D3D and Godot reproduced a stuck end timestamp: upstream MediaPlayer retained
isEOS after confirmed stop. onStop now clears isEOS on the FX thread before
STOPPED notification. Source Media SDK rebuild passes. The full regression passes
native D3D, Vulkan engine, GL engine and packaged Vulkan Runtime; PCM audio also
passes. Replay screenshot inspected. Test waits for the actual restarted clock
before sampling rather than treating an asynchronous PLAYING status as enough.


MEDIA CHURN MATRIX COMPLETE: Extended the direct runner with packaged Runtime
support. Vulkan Runtime and OpenGL engine each pass 24 new-player render/dispose
cycles, alongside prior Vulkan engine. Both new runs have 11 natural GCs,
tracked resources 32-52 after warmup/repeated recovery to 32, and final zero.
Runtime completes in 66.7 s, GL in 67.3 s. Runtime static-memory zero is explicitly
marked unavailable, confirmed by Memory::get_mem_usage without DEBUG_ENABLED.
Reports and media-godot.md record ranges and limitations; whole-process native
memory and long-duration workloads remain unverified.


MEDIA CHURN PASSED: At the user's request, simplified test-media-churn.ps1 to
ordinary direct invocation, removing process polling/forced termination. File
remained present. Vulkan/safe completed 24 fresh-player render/dispose cycles in
about 67 seconds, with 11 natural GCs and a 256-MiB heap. All decoded-picture and
GPU cleanup checks pass; final owned resources zero. Warm recovered checkpoints
repeatedly return to 32 resources and approximately 65.56 MB Godot static memory.
Whole-process memory is not sampled; longer native decoder leak acceptance remains
open. Detection cause is unknown; no antivirus settings were changed.


MEDIA FRAME RATE MEASURED: Added independent steady-playback benchmark using
upstream MediaView delivered/drawn counters, with no snapshots during sampling.
Same 30-FPS MP4 at 640x360: native D3D 30.099 draws/s, Vulkan/safe 29.957 draws/s
over ten seconds; both focused, delivered counts match draw counts. Godot has
zero backpressure, 300 JNI submissions/95.496 ms total, zero launch upcalls.
MP4 timing tables independently confirm 30 FPS. This is bounded source-rate
parity, not 60-FPS video or display scanout proof. Churn remains separately blocked
by antivirus diagnosis. See media-godot.md and media-frame-benchmark logs.


PACKED VIDEO EDGE FIX VERIFIED: New regression reproduced encoded padding being
exposed as logical packed-video bounds. Allocation now uses the visible extent,
with source stride retained during upload, and leaves the first upload to the
media handler. Media SDK source rebuild passes. GL/Vulkan packed and planar GPU
checks pass, including exact packed edge color and failed-allocation frame hold
balance; real Vulkan MP4 regression passes. Churn fixture remains unexecuted:
antivirus removed its runner, confirmed by user; no protection bypass attempted.


MEDIA VIDEO VERIFIED: Prism-Godot now allocates YCbCr 4:2:0 MultiTexture planes,
uses the stock GPU YV12 shader and binds the unused alpha sampler for opaque
video. Source Media SDK rebuild passes. Synthetic plane GPU checks pass GL and
Vulkan (color, alpha, padding/crop, three/four-plane transitions). Real Oracle
MP4 MediaView passes GL/safe, Vulkan/safe and packaged Vulkan/safe, including
pause/resume, picture readback, resize/clip/opacity pixels and final host resource
cleanup. GPU snapshots inspected. Media soak, frame-rate and codec breadth remain
unverified; see media-godot.md.


MEDIA SDK AND AUDIO VERIFIED: build-jfx-media.ps1 completes upstream SDK with
COMPILE_MEDIA=true / COMPILE_WEBKIT=false. jfxmedia.dll, glib-lite.dll,
gstreamer-lite.dll and fxplugins.dll are source-built and staged. Workspace
makedepend wrapper is verified; explicit Gradle WINDOWS_VS_PATH includes it while
keeping MSVC linker before MSYS link.exe. Silent PCM audio passes GL/safe,
Vulkan/safe and packaged Vulkan/safe: track/duration, clock, pause, seek while
paused, resume/end and dispose; final Godot resources zero. engine had
built with javafx.media in the module list. Follow-up engine builds also
enable native access for javafx.media; both audio retests pass without those warnings. Video
and planar YCbCr remain incomplete. See media-godot.md; Media is not fully accepted.

MEDIA SOURCE BUILD RESUMED: Latest user requires Media, excludes WebKit. Fixed
process-local MSVC PATH inheritance, MSYS double conversion of -Fo/-out paths,
and MSYS/MSVC link.exe name collision. GLib/GStreamer/fxplugins/jfxmedia native
libraries compile from current JFX source. Workspace makedepend 1.0.10 is built
from pinned official source using existing UCRT64 GCC; header dependency probe
passes. No installer/system package changes. SDK build/staging is still running,
as are sequential engine rebuilds adding javafx.media to JVM root modules.
Prepared silent PCM MediaPlayer test for ready/play/pause/seek/end/dispose; not
run yet. Planar video and full playback remain pending, so no Media support claim.

LATEST USER CORRECTION: Media DOES require support; only WebKit is excluded.
This supersedes the preceding combined exclusion. Resume Media source build and
playback/rendering validation; do not treat default SDK completion as Media support.

USER SCOPE CLARIFICATION: Media/WebKit support is not required. Removed the
experimental Media build helper added during the latest investigation; its build
attempt had already terminated with failure, so no Media build remains running.
Default source SDK graphics/Glass/native build remains the required path. Media
conversion and missing Media/WebKit DLLs are no longer completion blockers.
This explicit instruction supersedes all historical Media/WebKit pending notes.

DELIVERY ENTRY POINT: Added repository README with verified build/run commands,
source/artifact/document map, current measured FPS/memory facts and explicit gaps.
Corrected architecture/native-module statements that still called implemented
Prism, fonts, effects, GodotView and window input pending. Glass documentation now
distinguishes implemented popup/modal windows and held-input cancellation from
unsupported native dialogs/system menus. README links, commands and referenced
capture paths exist. Default run-vfx-demo.ps1 -Smoke starts and closes the original
Demo successfully; no VFX business-source changes. Documentation consolidation
does not assert overall completion or expand the tests' acceptance scope.

CORRECTED REAL-DEMO SOAK COMPLETE: Host process sampled;
537-second Vulkan/safe test completes three 35-page round trips (205 Java/native,
517 process observations), 256-MiB heap, no forced GC, 656 natural collections.
All three homepage endpoints retain 99 resources/135692288 texture bytes;
round-2/3 static memory differs by -24 bytes. Final owned resources zero.
Process latter-half private bytes: 1.90–2.61 GB, median 2.29 GB, fitted slope
+113542 bytes/minute; handles 808–821. Round-2/3 maxima ~2484/2487 MiB, medians
~2155/2193 MiB. No clear sustained accumulation at this duration; this does not
prove absence of small leaks or cover arbitrary/longer workloads. Both logs and
analysis complete, no test process remains live. See memory-validation.md and
artifacts/reference/vfx-soak-mobile-3-heap256.analysis.json. Overall goal stays active.

REAL VFX MEMORY SOAK IN PROGRESS: Added test-vfx-soak.ps1 and vfx_soak scene,
using original Demo Next/Previous controls through host input. Three full 35-page
round trips run with natural GC, animations enabled and a 256-MiB Java heap.
Process private bytes/working set/handles are sampled every second; settled
page observations include owned resources, texture bytes and Godot static memory;
the Java observer records heap and GC at page change. Initial startup status
handling was corrected after an early fixture failure. Current run has completed
the first forward traversal and is returning; no acceptance result yet.
analyze-vfx-soak.py reports same-page round deltas and process tail trends without
equating navigation/cleanup success to leak freedom. See memory-validation.md.

GODOTVIEW TRANSFORM ACCEPTANCE: Added parent affine scale/shear/translation
coverage with GPU pixels and inverse mouse/wheel/touch coordinates. GL/safe,
Vulkan/safe, Vulkan/separate and packaged Vulkan/safe pass, including focus
cancellation, sibling isolation, resize preserving scene identity/state and
zero resources after teardown (peak 56). Untransformed Vulkan regression passes.
Stock D3D reference confirms upstream non-axis-aligned clip applies opacity in
both offscreen content and final blend; 50% red-over-white is (1,.753,.753),
matching Godot. No upper-level scene-graph behavior was changed. Fractional touch
positions exposed integer Glass quantization; exact-coordinate samples now use
representable points. Arbitrary-transform/physical-input stress remains open.

CLIPBOARD MAINLINE: Added immediate Windows HTML/RTF alongside Unicode text,
reusing upstream CF_HTML encoding and preserving bounded native ownership.
engine GL/Vulkan and Runtime application assertions pass: Unicode HTML offsets,
external .NET interchange, RTF, plain text paste, clear and invalid-write preservation.
engine/JFX source builds pass. Overall clipboard acceptance is still pending:
Runtime's OLE snapshot restoration changed ANSI Text representation. The fixture now
uses exact native byte backup/restore and a single STA thread, but the latest run
refused preexisting non-text native clipboard formats before writing. Do not clear
user clipboard to bypass this guard. Images/files/URL/custom formats and DnD remain
unsupported. White edges remain waived; default Vulkan/safe performance evidence
remains approximately 60 FPS. Overall goal is active.

The objective file has been read in full. Overall implementation is active;
no milestone is accepted yet.

MAINLINE RESUMED / STAGE ICONS: User explicitly waived the white-edge issue;
it is no longer a blocker or active investigation. Implemented standard
Stage.getIcons() for primary and independent native windows. JNI copies bounded
BGRA_PRE assets into the existing ordered queues (primary op25/native op5), with
1-MiB pending-icon limits per queue, validation and close rejection. Godot owns
native icon allocation/replacement/destruction. Native protocol tests pass.
engine and OpenJFX SDK source builds pass. Initial native compile failed
on a missing namespace qualifier and was repaired before testing. First icon
probe exposed the incorrect fixed 32px assumption: LR_DEFAULTSIZE gives 64px at
the current 200% scale. Test now checks system-scale dimensions and bounded
resampling error. A half-alpha probe then caught incorrect unpremultiplication;
the adapter now preserves BGRA_PRE RGB, consistent with native Glass's bitmap.
Seven-state native HWND icon tests pass on Vulkan/safe, GL/safe, Vulkan/separate
and packaged Vulkan/safe Runtime: distinct colors, replace, clear, hide/reshow,
transparent corners, half-alpha blue and final native-window/GPU cleanup.
Inspection uses WM_GETICON/GetIconInfo, not submitted-state echo or screenshots.
36-cycle safe Stage churn at heap128 passes; original VFX default smoke starts
and closes cleanly. No VFX business sources changed. All processes completed.
Native taskbar appearance and mixed-monitor scaling remain outside this fixture.

DEFAULT SAFE BROAD REGRESSION: Packaged Vulkan/safe transparent-perimeter,
original VFX scroll, table edit, loading completion and loading cancellation
tests pass; engine Vulkan/safe dialog passes. Fresh 35-page Vulkan/safe navigation
passes with scale 2, 2560x1600 captures and final_owned_resources=0. Compared
against the existing completed 35-page same-scale native D3D baseline, the
contact sheet shows no obvious new layout regression. Pages 18/19 have the
largest mean RGB differences (0.011568/0.007949); full paired images were viewed,
and VFX source confirms random IDs/text/numbers and current-time fields. Their
table geometry, headers and clipping match visually; observer navigation UI is
intentionally excluded by comparison. Other content-region mean differences are
<=0.00003575. This is visual triage, not exhaustive pixel equivalence or desktop
acceptance. Artifacts: vfx-pages-mobile/run.json and vfx-comparison-mobile.png/json.
The GPU window border is visible in both Godot and native images; it does not
resolve whether the user's desktop edge also contains a DWM border.
Computer-use skill/guidance were re-read and @oai/sky initialization retried:
Module not found. The configured bundled node_modules also lacks that package.
No OS capture or fallback UI automation was performed. Acceptance-status.md now
consolidates current performance evidence instead of listing superseded history
as current results. All test processes completed; overall acceptance stays open.

PHASE TRACE AND DEFAULT-MODE VALIDATION: Benchmark trace now buffers process,
pre-draw and post-draw callback timestamps and the analyzer reports adjacent
event gaps. Separate-mode post-draw delivery is deferred, so this is main-thread
phase evidence, not GPU/presentation timing. Initial separate run lost focus and
is excluded. Focused repeat records 59.456 compositions/s, Java max 58.626 ms;
largest phase gaps 55.719/49.220 ms precede pre_draw. The earlier large interval
outside host processing did not recur, so its cause remains unproven.
Crucially, the launcher's existing safe default now measures 60.004 compositions/s
in trace mode and 60.078 in an ordinary focused run; ordinary pulse rate 60.242,
p95 19.604 ms, max 35.592 ms. Safe trace has 1,324 shadow reuses and zero clones,
versus 623 reuses/614 clones in separate. Prefer the default safe launcher for
the current VFX Demo; this supersedes earlier separate-mode recommendations.
The source-built native D3D ordinary repeat is focused and measures 61.002
pulses/s, p95 25.135 ms, max 231.933 ms; its first run lost focus and is excluded.
The native outlier prevents blanket claims of relative tail-latency superiority;
near-native average cadence is demonstrated in this same scene/size/scale.
Packaged Runtime safe-mode GPU-motion probe passes. All processes completed.
Logs: vfx-frame-benchmark-phases{-repeat,-safe}.log,
vfx-frame-benchmark-safe-current-ordinary.log, and
vfx-frame-benchmark-d3d-current-repeat.log, with phase analysis JSON.

MONITOR SNAPSHOT REUSE: refresh_host_info now queries monitor count once and
reuses the enumerated current-monitor bounds/work area/DPI for primary-window
metadata. OS/scene queries finish before acquiring the JNI snapshot mutex.
No cross-frame cache or delayed topology refresh was introduced; the original
default-monitor fallback remains when the current index is absent. engine and
Runtime source builds pass. Screens tests on Vulkan/separate and GL/safe verify
metadata against DisplayServer, including primary ordering and window association;
Vulkan resize and packaged Runtime render-scale/VFX-window-controls tests pass.
The focused instrumented run is slower (56.599 compositions/s, max Java gap
118.358 ms); longest host intervals of 104.662/88.111 ms contain only
10.482/12.357 ms of host process time. This does not establish a metadata
optimization benefit or identify the remaining unaccounted wall time. Ordinary
first run lost focus and is excluded; focused ordinary repeat is 59.333
compositions/s, 59.457 pulses/s, p95 20.464 ms, max 67.811 ms, 755/755 focused
host ticks. Metadata wall total is 208.701 ms. Logs are
vfx-frame-benchmark-monitor-snapshot{,-ordinary,-ordinary-repeat}.log, with
analysis JSON for the trace. All processes completed. Near-60 average cadence
persists, but stable 60 FPS and physical multi-monitor acceptance remain open.

RENDER-THREAD ATTRIBUTION: Added opt-in process-wide atomic wall-time/pass/slow
pass counters inside the actual draw_offscreen_2d callback, covering synchronous
and queued paths without a new fence. engine builds pass. Profile-enabled
GL/safe and Vulkan/separate target tests pass; packaged Runtime timing control
also completes (this timing-only control is not GPU-motion acceptance).
Focused default trace vfx-frame-benchmark-render-thread.log has zero unfocused
ticks, 59.330 compositions/s, 59.375 pulses/s, 31,383 callback calls and 1.209 s
inside offscreen drawing (only one individual call >2 ms). Callback count equals
30,628 offscreen passes plus 755 direct final compositions. The first two host
intervals spend 16.205/21.231 ms inside rendering callbacks and 32.755/35.302 ms
in target allocation; these overlapping cross-thread timings must not be added.
All six Java gaps >33 ms occur in the first two measured traversals. The longest
host interval (94.544 ms) instead contains 53.555 ms in refresh_host_info and
only 5.078 ms in render callbacks. Source inspection confirms refresh_host_info
enumerates monitor properties every frame, including a DPI query while holding
the JNI snapshot mutex. This is a newly isolated investigation target, not proof
that every stall is caused by monitor enumeration. No performance improvement
is claimed for these diagnostic changes. All processes completed.

ASYNC TARGET TEXTURE EXPERIMENT: engine builds pass. Optional
GODOT_JFX_ASYNC_TARGET_TEXTURE=1 allocates a thread-safe texture RID, initializes
its proxy on the rendering thread after viewport setup, and frees the owned
proxy before its viewport. Render-target lifetime/count fixtures include exactly
one extra RID per target when enabled. Vulkan/separate and GL/safe target tests,
Vulkan shader-cache and readback tests pass. Focused trace off/on rates are
59.539/59.568 compositions/s; target-command wall time falls 70.794 -> 0.042 ms,
but early frames still wait about 45 ms at rendering sync. Java >33-ms gaps
number 3/6. This is not established smoothness improvement, so default stays off.
Initial off trace and on ordinary run lost focus and are excluded. Logs use
vfx-frame-benchmark-proxy-* with analysis JSON for the focused traces.
JNI batches remain approximately one per composition, with no launch upcalls
during measurement; tick waits are not CPU cost. Long-frame acceptance stays open.
With the proxy enabled, packaged Runtime 39-effect, GPU-motion, transparent
perimeter and pending-readback-stop probes pass, as does 36-cycle Stage churn
under a 128-MiB Java heap. All build/test processes have reached terminal status.

CPU SHADOW OWNERSHIP: Patch diagnostics split duplicate/blit/submission and
count retained image paths. An initially unfocused run is excluded from FPS
comparison. Source inspection confirms unconditional duplicate makes blit copy
the full shared pixel buffer. Reuse now requires the surface's Image to have one
reference; queued upload/cache references force cloning, and pixel-buffer COW
remains intact. GL tests exercise reuse; Vulkan/separate Prism texture tests
exercise 14 reuses and 10 clones with correct old GPU revisions, overlaps, float
regions and edge pixels. Both full and optional region-upload paths pass.
Focused REGION_UPLOAD=0 trace A/B: reuse off texture-command wall 2.911 s,
blit 2.351 s, 1,197 clones; reuse on texture wall 1.105 s, blit 1.007 s,
622 reuses/608 clones. Composition rates 58.566/58.959 do not imply a large FPS
gain at the display cap; the texture work reduction is the supported result.
Runtime 39 effects, 36-cycle heap128 churn, pending readback stop and GPU motion
pass. Combined region+reuse ordinary run: 59.780 compositions/s, p95 19.336 ms,
max 53.953 ms, zero unfocused ticks. REUSE_SHADOW now defaults to enabled unless
explicitly 0; REGION_UPLOAD stays opt-in. engine rebuilds and unset-env
GL/Vulkan texture checks pass. Default separate benchmark is 59.493 compositions/s,
p95 19.487 ms, max 65.341 ms, zero unfocused ticks, with region upload disabled.
Packaged Runtime GPU-motion and transparent-perimeter tests pass on these actual
defaults. All build/test processes completed; long frames remain open.

REGION UPLOAD EXPERIMENT (in progress): Added an internal RenderingDevice region
upload using the existing staging, dependency and transfer-worker path; full
texture_update delegates with an empty region and retains its previous behavior.
RD/GLES storage implementations support plain 2D RGBA8/RGBAF and retain a full
update fallback. The JavaFX surface opt-in GODOT_JFX_REGION_UPLOAD=1 captures
RID/image/rectangle in a render-thread callback only when no encoded draw retains
the texture; referenced revisions still use full replacement. engine build and
GL/Vulkan-separate texture-version tests pass, including overlapping patches,
the 1024x1024 atlas's last pixel, float-region values and untouched corners.
The extended Prism fixture retains one additional texture and mesh (22 resources,
then 8 after clear); its original 21 estimate was corrected after pixels passed
and diagnostics confirmed both resources. Runtime build, 39 effects on GL/safe
and packaged Vulkan/separate, Runtime GPU animation, pending-readback stop,
36-cycle heap128 Stage churn and Runtime transparent perimeter checks pass.
First focused trace A/B: off 58.429 compositions/s, p95 21.161 ms, max 71.121 ms,
texture-command wall 2.897 s; on 59.519, p95 20.187 ms, max 61.970 ms, texture
wall 2.308 s. Both zero unfocused ticks. These instrumented single runs suggest
benefit but do not establish stable smoothness. Ordinary focused repeat: on
59.949 compositions/s (60.004 pulses/s), p95 18.837 ms, max 62.396 ms; off
59.644 compositions/s, p95 19.598 ms, max 50.392 ms. This does not prove a
consistent long-frame improvement, so REGION_UPLOAD remains opt-in. Both runs
have zero unfocused ticks. The CPU shadow-image copy is still present and needs
further cost attribution. All builds and test processes reached terminal status.
Logs are vfx-frame-benchmark-region-{on,off}.log and adjacent analysis JSON.

TEXTURE PATCH COALESCING EXPERIMENT (rejected): Grouped adjacent same-handle
patches into one image copy/upload, stopping at every intervening command. Added
an overlapping-update/old-revision GPU check; GL/safe, Vulkan/safe and
Vulkan/separate pass, as do all 39 packaged Runtime effects. The real animation
trace has 1,196 patch commands and 1,196 uploads: draws separate its patches, so
coalescing does not address this hotspot. Measured 58.408 compositions/s and
2.515 s texture-command wall time do not establish improvement over the prior
58.787 instrumented / 2.669 s control. Removed the coalescer and its production
counters; retained the overlap test, test-bridge render-thread selector and
analysis support for the archived experiment log. Evidence:
vfx-frame-benchmark-separate-coalesced-patches.log/.analysis.json. Native
engine rebuilds after removal pass, as do the extended Vulkan/separate
texture version test and packaged Runtime GPU animation. All sessions completed.
Current patch_texture still duplicates the
CPU image and calls full texture_2d_update/create for each region; RenderingServer
exposes no partial-update API. Investigate that path next, preserving sampled
texture revisions and both Vulkan/OpenGL behavior.

LONG-FRAME DIAGNOSTICS: Added optional benchmark -Trace with buffered Java gap
and host counter samples, separate log suffix, and analyze-frame-trace.py JSON
summaries. Focused unprofiled trace has five Java gaps above 33 ms: four in the
first measured traversal (max 73.330 ms), one in the second; the remaining eight
traversals stay below 33 ms in this run. Host command encoding reaches 40–43 ms
in the first two long host intervals, so JNI upcall frequency is not a sufficient
explanation. A fresh native D3D trace remains variable too (max 43.787 ms).
The JFR-enabled run loses focus for 359 Java intervals and is excluded from
foreground FPS comparison. Its 11 GC pauses total 121.431 ms, max 31.289 ms,
with the large pauses during startup and later pauses around 1–2 ms; do not
attribute measured long frames to GC without temporal correlation. JFR/event
exports are under artifacts/logs/vfx-default-frames.*. Optional native command
profiling now splits texture/target/geometry/shader-state wall costs and counts
target shader-cache misses; engine builds pass. A focused native
command-profile run identifies the first two long intervals as target allocation
(31.024 / 36.533 ms), plus texture commands (6.516 / 10.538 ms). Whole-window
texture wall cost is 2.669 s, geometry .427 s, shader-state .138 s, target .068 s;
80 target shader-cache misses occur. These are overlapping instrumented wall
costs, not GPU execution timings. Inspect viewport_get_texture's initial sync
and full-image texture patch uploads next; do not remove resource-version fences.
The detailed log/JSON is vfx-frame-benchmark-separate-command-profile.*. Packaged
Runtime GPU-motion regression passes. The ordinary profile-disabled repeat is
57.790 compositions/s, p95 23.554 ms, max 101.947 ms, with zero unfocused ticks
and no profile counters. This turn adds diagnosis, not a claimed smoothness fix;
occasional long-frame variance remains. All native builds and GUI runs completed.

DEFAULT PERFORMANCE ROLLOUT: Promoted the seven previously validated switches
to enabled unless explicitly set to `0`, in both Java and native consumers.
DIRECT_OFFSCREEN now tests the value rather than environment-variable presence,
so `0` actually disables it. run-vfx-demo.ps1 no longer forces performance flags;
it inherits defaults/explicit overrides. The benchmark records both raw values
and resolved enabled states. Source engine and SDK rebuilds pass.
With all seven environment variables unset: timer cadence, pulse-stop, original
interactive Demo smoke, Vulkan/separate packaged Runtime scroll, 39 effects and
transparent perimeter checks pass. 36-cycle heap128 Stage churn and pending
readback-stop pass. Fresh focused Vulkan/safe: 57.404 compositions/s, 731/731
host ticks, 57.408 pulses/s, p95 24.239 ms, max 65.827 ms, zero unfocused intervals.
See vfx-frame-benchmark-safe-defaults.log. Focused default separate-mode repeat
measures 58.907 compositions/s (745/746 host ticks), 58.941 pulses/s, p95 22.044 ms,
max 69.776 ms, zero unfocused intervals (vfx-frame-benchmark-separate-defaults.log).
Default GL/safe original GPU animation and explicit all-seven-options-off
Vulkan/safe transparent Stage fallback pass. No VFX business sources changed.
All build/test sessions completed; long-frame optimization remains open.

ACCELERATED PATH BROAD REGRESSION: With frame pulse and all seven performance
switches enabled, Vulkan/separate passes all 35 original VFX pages, table editing,
loading completion/cancellation, FXML and 17-phase native window ordering. The
35-page mobile/D3D comparison contact sheet was inspected; content/layout agree
at that scale, with differences around animated controls and randomized tables.
This comparison is visual triage rather than a pixel-perfect acceptance oracle.
Long-table scrolling initially failed: its Java title reached the host while
three render submissions remained queued. Captured failure/later images prove
the movement did render subsequently. The fixture now queues its render-job
marker after the FX pulse, carries the submitted sequence in its title, and
waits for completed_render_sequence before pixel assertions. Applied sequence
alone still failed on GL because it does not prove final window composition.
The existing completion watermark is now exposed by get_render_stats; no render
ordering or acceptance thresholds were relaxed. Failure images/stats are saved.
GL/safe passes with the corrected completion barrier. engine rebuilds
pass. Packaged Vulkan/separate Runtime scrolling passes with 1,224 changed samples
after horizontal drag and 25,871 after vertical scroll; all four input phases,
clip checks and final resource drain pass. Fresh safe-mode benchmark after builds:
57.192 compositions/s, 57.233 pulses/s, 730/730 host ticks, zero unfocused ticks,
p95 27.853 ms, max 72.745 ms (vfx-frame-benchmark-safe-after-broad-regression.log).
This confirms near-native average cadence survives the broader tests; occasional
long frames remain. All build/test sessions reached terminal completion.
Backend defaults remain opt-in; run-vfx-demo.ps1 selects the tested configuration.

FRAME CLOCK / VULKAN WAIT PROFILING (current): Added opt-in per-render-thread
Vulkan wall counters for acquire/fence/submit/present. An initial namespace-TLS
constructor accessed OS before startup under MSVC (even --version exited
-1073741819); moved to function-local lazy TLS and verified --version succeeds.
GPU profiling initially exceeded 256 timestamp slots and is rejected as partial;
scripts/profile-vfx-gpu.ps1 uses an isolated fixture with 8192 slots and checks
for errors. Both VSync and no-VSync/host120 profiles now pass. Measured-window
counter summary in artifacts/logs/vulkan-wait-summary.json: wait-only VSync
acquire averages 7.353 ms/native present, fence .039 ms, submit .204 ms,
present .022 ms; no-VSync acquire .004 ms. The VSync wait-only run recovers
47.884 JavaFX compositions/s with ~60 host ticks/s, illustrating timing variance.
JFR parks show FX/Quantum often idle waiting for events/jobs, not doing CPU work.
Testing an explicit host-frame clock separate from capacity notifications:
GODOT_JFX_FRAME_PULSE=1 selects awaitFrameTick and a host-driven zero-period
Glass pulse timer. General timed Glass timers remain unchanged. Native frame
queue tests cover separation/coalescing and stop/finish wakeups. Builds pending.
engine/SDK builds and timer/pulse-stop tests now pass. First frame-clock
results reach 59.215 safe and 58.850 separate compositions/s under ordinary
60-Hz VSync, but the initial off control was unfocused. The benchmark now
requests focus once before warm-up and records unfocused intervals/ticks.
Focused A/B confirms off 47.450 versus on 57.403 compositions/s, both zero
unfocused ticks; on consumes every host tick (731/731), off only 616/765.
On p95 25.181 ms / max 137.504 ms still shows occasional long host frames;
repeat/native controls and functional regressions are underway. This is a
near-60 experimental result, not blanket smoothness/default-path acceptance.
Focused repeat is 58.586 compositions/s, p95 23.165 ms, max 69.460 ms,
zero unfocused intervals/ticks, 746 compositions/746 host ticks. Native Stage
input, modals, GodotView, 36-cycle heap128 Stage churn, pending-readback stop,
and host-stop pass on Vulkan/separate with frame pulse and all accelerated
switches. A subsequent D3D control lost focus for 495/566 intervals and is
excluded from foreground comparison (44.186 Hz); repeating it before finalizing
the comparison. Native runtime image regressions are still running.
Fresh D3D foreground control: 60.634 pulses/s, p95 27.748 ms, max 41.161 ms,
zero unfocused intervals. Compared with focused Godot repeats 57.403/58.586
compositions/s, this supports near-native average cadence for this original VFX
animation, while occasional long host frames remain. Packaged Vulkan/separate
Runtime GPU animation, all 39 effects (native exit zero) and transparent Stage
pass; GL/safe animation and transparent Stage also pass with frame pulse.
Added scripts/run-vfx-demo.ps1 to launch unchanged IntroMain interactively with
the accelerated configuration (Vulkan/safe by default), restoring process env
on exit. Its optional smoke mode exercises actual visible startup and normal
close/drain; smoke validation is in progress. Generic backend defaults remain
unchanged pending broader rollout; this launcher makes the tested path usable.
Both Vulkan safe/separate interactive-launcher smoke runs pass visible startup,
normal close, native-window drain and final owned-resource zero. Final inventory:
root 290, Godot 8, OpenJFX 42, VFX 0 changed paths. All build/test processes in
this turn reached terminal completion. Next work: broaden accelerated-path
coverage/default rollout and investigate occasional long host frames, preserving
the original full objective and remaining physical/visual acceptance gaps.

FOLLOW-UP PASS COST EXPERIMENTS: Bounded per-target item/material reuse (16
slots, cleared commands/samplers after each pass) measured 48.724 safe /44.098
separate compositions/s. Preserving persistent shader bindings measured 49.474
safe /46.534 separate, effectively unchanged from the previous path. Effects,
75-variant shader/uniform isolation and 36-cycle Stage churn passed, but the
experiment added persistent resources without established throughput benefit;
all draw-slot code and its test accommodation were removed. Logs retained with
-draw-reuse and -bound-shader suffixes. Now testing FIFO offscreen dispatch
under the newer batched protocol, with one host-batch CPU fence before readback
and completed-sequence publication. Earlier pre-batching async rejection remains
historical, not proof about the new batching configuration.
New async/batched result: 48.029 compositions/s, pulse 47.946 Hz, p95
30.617 ms, max 46.149 ms. Effects, 36-cycle Stage churn, original GPU animation,
readback and transparent Stage pass. Most draw/sync wall time moved to the batch
fence rather than disappearing. Async direct_offscreen_render_us=0 means timing
is unavailable before the fence, not zero rendering cost. OpenGL/safe control
is slower: 37.785 compositions/s, p95 47.547 ms. The next experiment replaces
composition completion's full-frame draw with a fenced single-surface draw and
avoids a second whole-frame submission after layer completion.
Single-surface composition experiment was rejected and removed: it dropped to
32.131 compositions/s (p95 35.951 ms) despite passing animation/effects/churn/
transparent checks. Log retained as -direct-composition.log. Sampling JFR on
the prior async/batched path to identify Java CPU/GC/wait contributions before
further synchronization changes. No default rendering policy changed.
JFR recording artifacts/logs/vfx-frames.jfr contains 116 Java execution samples:
20 sampled stacks pass through sampler source rewriting (replaceAll/matcher),
7 through the per-draw shader ASCII scan, plus regex compilation in name checks.
GC pauses total 18.8 ms (14 pauses, max 2.33 ms); this does not explain the frame
gap. Added bounded CPU-only shader adaptation caching (64 entries /524288
weighted characters per render thread), encoder ASCII byte caching (64 entries /
524288 bytes), and equivalent ASCII identifier scanning without regex compilation.
Uniforms/texture bindings remain draw-specific and validated. Source-cache unit
tests and GPU comparisons pending the SDK rebuild; no FPS claim yet.
Source-cache unit test, 39 effects, NodeShader and readback pass. However, first
VSync-enabled source-cache measurements regress to ~32.7 compositions/s with
the host itself at ~33 Hz; measured refresh remains 60 Hz, low-processor mode
false, max_fps=0. VSync-off/120-Hz control gives 55.417 compositions/s, p95
23.786 ms; fresh native D3D is 62.482 pulses/s, p95 18.978 ms. Cache is now
explicit opt-in (GODOT_JFX_SHADER_SOURCE_CACHE=1) pending same-binary on/off
comparison. Added display-policy diagnostics and Vulkan Mailbox 60/120/240 caps
to the benchmark; these change presentation policy and must be reported as such.
Same-build safe-mode source-cache A/B: off 32.744, on 32.683 compositions/s.
The previous packaged Runtime binary (11:53 build), with current SDK/cache off,
also gives 32.878 compositions/s. Thus the observed ~33-Hz plateau is not
isolated to the source cache or new native async code. The older SDK was not
restored, so this is not proof that all Java changes or external state are ruled
out. Mailbox is unsupported on this Vulkan surface: driver explicitly falls
back to Enabled, measured mode=1; the benchmark rejects it and stops further
Mailbox cap runs. No stable 60-FPS claim. Source cache and async remain opt-in.
Final validation of this turn: rebuilt engine and SDK; bounded source
cache test and 212-loader shader state test pass. With all six opt-in switches,
36-cycle Stage churn passes, packaged Runtime original GPU animation, 39 effects
(native exit zero), transparent perimeter/lifecycle pass; pending-readback stop
also passes on Vulkan/separate. Earlier current-SDK NodeShader/readback tests
pass. Inventory regenerated: root 286, Godot 7, OpenJFX 42, VFX 0 changed paths.
No running build/test remains. Next investigation: native GPU presentation/frame
wait timing under ordinary VSync, plus an older-SDK control if needed; do not
treat source-cache A/B as excluding every Java scheduling difference.

60 FPS COMPARISON (current investigation): Added a shared VfxFrameBenchmark
running the unchanged original animation page, three warm-up traversals followed
by ten measured a-to-b traversals. scripts/benchmark-vfx-frames.ps1 runs the same
class on source-built JavaFX D3D and Godot Vulkan, with no timing-path readback.
At 1280x800 logical / scale 2, D3D pulse throughput is 62.215 Hz (p95 25.970 ms).
With DIRECT_OFFSCREEN=1, BATCH_PASSES=1, DIRECT_PRESENT=1, Vulkan/safe completes
43.929 presentations/s (pulse 44.096 Hz, p95 31.877 ms, max 230.689 ms), separate
31.209 presentations/s (pulse 31.143 Hz, p95 38.918 ms). D3D pulse metrics are
not independently measured GPU presentation counts. Baseline Godot logs saved
as vfx-frame-benchmark-{safe,separate}-before-cadence.log. Goal remains stable
60 FPS or close to native; these experimental measurements do not satisfy it.
Java launch upcalls are zero; safe-mode JNI submission costs 235782 us across
13.294 s, versus 4.559 s native command encoding and 1.301 s draw/sync.
DIRECT_PRESENT draws the final target directly before scheduling composition;
its 36-cycle Stage churn, original GPU animation, 39 effects, and full-perimeter
transparent Stage regressions pass on Vulkan/separate. Three repeated earlier
effects runs also exit zero; test-effects now records native exit codes for
future diagnosis of the one historical unexplained exit anomaly.
Further changes under validation: preserve Glass timer phase across jitter
without catch-up bursts, and acquire PackedArray write pointers once per mesh.
Both changes rebuild successfully (SDK, engine). Deterministic timer
jitter/missed-deadline/pause/stop test and 50-iteration queued-pulse shutdown test
pass. Combined remeasurement: safe 49.356 completed presentations/s, pulse
49.432 Hz, p95 29.304 ms, max 50.483 ms; separate 30.261 presentations/s,
pulse 30.418 Hz, p95 40.767 ms. Logs retained with -cadence suffix. This does
not isolate the individual contribution of mesh changes, timer phase, and run
variance. Separate rendering still has an approximately two-host-tick cadence;
testing an opt-in early final-composition fence before queue admission.
The first early-fence experiment was rejected despite higher throughput because
the layer owner still reported pending composition. Its log is retained as
vfx-frame-benchmark-early-fence-rejected.log. The corrected path completes the
layer owner's explicit draw/fence and pending state before completing host
state; it is separate-render-thread only and opt-in via
GODOT_JFX_EARLY_COMPOSITION_FENCE=1. Corrected run: 46.482 completed
compositions/s, pulse 46.229 Hz, p95 31.232 ms, max 60.608 ms, no errors and no
backpressure. Original GPU animation and all 39 effects pass. Further resource
and transparent-window checks are in progress. Stable 60 FPS remains unmet.
Follow-up: 36-cycle heap128 Stage churn passes with exact warm baseline
(29 owned, 13,209,600 texture bytes), final resources zero; full-perimeter
transparent Stage passes. Final engine rebuild successfully.
VSync-off / 120-Hz host diagnostic (separate -host120 logs): safe 53.732
compositions/s, pulse p95 24.587 ms; separate 48.679 compositions/s, p95
28.549 ms. Thus display-cadence waits explain only part of the remaining gap.
This altered VSync policy is not a production fix and is not 60 FPS acceptance.
Next work should profile/reduce per-draw resource construction and per-target
CPU fences; do not increase queue capacity, change VFX duration/effects, or
claim pulse throughput as physical display FPS.
Packaged Runtime follow-up also passes original GPU animation, all 39 effects
with native exit code zero, and transparent Stage perimeter/lifecycle checks
with the four experimental flags. Delivery inventory regenerated: root 284,
Godot 7, OpenJFX 41, VFX 0 changed paths. No VFX business changes. The accelerated
paths remain opt-in pending broader acceptance and further frame-time work.

BATCHED PASSES / SHADER SOURCE INVALIDATION (current investigation): Native
END_PASS now executes in order within a transfer, while PRESENT/window boundaries
still terminate it. GODOT_JFX_BATCH_PASSES=1 batches Prism target switches until
publication/readback/capacity; native protocol decode/admission tests pass.
The direct offscreen path now performs the same sampler/retired-resource cleanup
as normal pass completion. This exposed repeated shader_set_code calls from
surface cleanup and uniform/clip updates; JavaFXRenderSurface now only submits
shader source for a newly created shader or changed code. Godot's source confirms
that identical shader_set_code still calls ShaderData::set_code and invalidates
material dependencies. engine and JavaFX SDK rebuild successfully.

With direct offscreen + batching + source cache, capture-free VFX action timings
are 39 presentations / 1418 ms (27.50 FPS) Vulkan/safe, and 36 / 1524 ms
(23.62 FPS) Vulkan/separate. Natural-animation pulse counts are 36 and 34,
maximum gaps 106.7 and 117.3 ms. These are action-interval measurements, not
steady-state acceptance. Source caching is active normally; batching and direct
offscreen remain experimental switches. A new 36-cycle Stage churn run fails
the existing warm-baseline gate: 39 resources and texture bytes changing with
former child dimensions. Added texture-handle/size/retirement diagnostics to
identify the retained allocation; do not weaken the gate or enable the switches
by default yet. Earlier asynchronous experiment rejection remains historical.
Follow-up diagnostics show only one live native child target, while Java's
window map is already cleared 150 ms after hiding. The fixture waited twelve
frame_post_draw signals, but a host iteration can emit several such signals;
this did not provide twelve host iterations for asynchronous close work. It now
waits twelve process_frame iterations then a post-draw signal, preserving the
exact original warm-baseline equality checks. The 36-cycle Vulkan/separate run
passes (29 owned resources, 13,209,600 texture bytes, final owned zero).
GodotPresentable.dispose also explicitly submits its disposal commands so the
unretained branch cannot depend on a later frame. Temporary Java reflection and
delayed-thread diagnostics have been removed; native retained-texture stats are
available only on request and printed if the churn gate fails.

engine and SDK rebuild pass. With both switches, Vulkan/separate and
OpenGL/safe's 39 Effect pixel comparisons pass; Vulkan NodeShader uniform/clip
tests, GodotView, readback, and full-perimeter transparent Stage also pass.
One first Vulkan Effect run ended after EFFECTS_PROBE_PASS without the native
GODOT_EFFECTS_PASS marker; a repeat passed. Preserve
effects-batched-separate-first-failure.log and investigate exit stability before
default-enabling the experimental paths. Do not infer a clean exit from correct
pixel comparisons alone.
Further opt-in regressions pass: strict VFX GPU motion on Vulkan/separate and
OpenGL/safe, plus packaged Vulkan/separate Runtime's 39 Effect comparisons and
normal native final pass marker. Default (switches unset) Vulkan/separate timing
still gives only 9 presentations / 2153 ms (4.18 FPS), maximum natural pulse gap
268.5 ms: source caching alone is insufficient. Saved opt-in measurements remain
vfx-animation-batched-shader-cache-mobile-safe.log and -mobile-separate.log;
the default comparison is vfx-animation-default-after-source-cache.log.
Next: resolve/reproduce the one unexplained Effect exit failure, then reduce
final-presentation latency. The current PRESENT path waits for the target draw,
then composes it into the window, then waits again. Directly completing the
target pass before queueing composition may eliminate one host-frame delay,
but must retain ordered resource completion and independent native windows.

TRANSPARENCY AND ANIMATION PROFILING (latest): Glass-Godot now advertises
transparent-window support; inherited HeadlessApplication previously stripped
the TRANSPARENT style and Quantum cleared the Scene white. Root native-window
transparency and backing alpha now follow the effective style. The host project
enables per-pixel transparency. TransparentStageProbe covers independent root
and child windows, hide/show, transparent/opaque Scene fill, and alpha at empty,
opaque and half-transparent pixels. GL/safe engine and Vulkan/separate engine
pass; packaged Vulkan Runtime also passes the expanded full-perimeter zero-alpha
check. The user confirms transparency is visible. VFX's original VStage draws a
0.5-logical-pixel light border (one physical pixel at 200% DPI); its source remains
unchanged. Physical desktop/DWM-edge verification remains unavailable.

The strict animation GPU-motion gate now samples only newly completed
presentations, avoiding repeated synchronous readbacks of the same image. It
passes GL/safe engine, Vulkan/separate engine, and packaged Vulkan Runtime with
the original >=20-pixel displacement requirement. These runs predate the newest
transparency changes and do not establish smooth frame pacing. Capture-free
Vulkan timing on the latest engine records 14 presentations over 2955 ms
(4.74 FPS including action/title latency), host ticks 55.84 Hz, and 480 offscreen
passes. Draw/sync totals 2,201,877 us; JNI submissions 44,027 us over 1626 calls,
metadata JNI 694 us over 249 calls, and native-to-Java launch upcalls zero during
the interval. Summed awaitTick wall time is 8,664,189 us across threads, not CPU
time. FX natural-animation pulse maximum gap is 322 ms. Performance remains
unacceptable. Two window-update suppression experiments showed no clear gain
and were reverted. A direct offscreen-viewport path is now under investigation,
opt-in via GODOT_JFX_DIRECT_OFFSCREEN; it is not yet accepted or enabled by default.
First opt-in Vulkan timing run gives 15 presentations / 2002 ms (7.49 FPS),
761 offscreen passes, draw/sync 1,512,052 us, and maximum natural-animation pulse
gap 287 ms. This is preliminary action-interval evidence, not a steady-state
benchmark. The direct path passes all 39 D3D-reference effect comparisons on
Vulkan/separate and OpenGL/safe, plus Vulkan's strict original-VFX GPU motion
check. More lifetime and presentation validation is required before default use.
The instrumented synchronous direct run records 17 presentations / 1863 ms
(9.13 FPS), 1018 direct passes, 160,718 us inside render-thread drawing versus
1,313,217 us for main-thread dispatch+sync. This implicates thread handoffs more
than Java upcall cost. Vulkan's 36-cycle Stage churn passes with this path,
including final zero ownership. An asynchronous grouped-fence experiment gave
3.76 FPS with the original three-batch queue, and 7.58 FPS / 141 ms maximum pulse
gap with a temporary 32-batch queue. The latter failed the Stage churn warm
baseline gate (closed-window texture bytes varied with former child size).
Both asynchronous batching and queue-capacity changes were reverted; the failed
log is stage-churn-direct-async-failed.log. The opt-in path retains per-pass CPU
fences and default admission capacity three. Native protocol tests passed during
the experiment. Runtime has not yet been rebuilt with the direct-offscreen path.
After reverting the rejected experiment, engine rebuild passes, the opt-in
synchronous path passes OpenGL/safe's strict original VFX GPU-motion gate and
Vulkan/separate's full-perimeter transparent Stage probe. Default rendering is
still unchanged pending broader validation and a satisfactory performance fix.
The older GPU-motion failure entry below is historical, superseded as described.

VFX GPU MOTION ACCEPTANCE GAP: Computer-use initialization was retried using the
skill's documented @oai/sky import; it still reports Module not found, so physical
desktop capture remains unavailable. Strengthened vfx_animation.gd to require
two GPU red-point centroids separated by >=20 pixels during the unchanged
original a-to-b animation. It samples the most recent presented image during
continuous animation instead of waiting for all pending composition, postpones
PNG encoding until afterward, records time/centroid/presentation count, and fails
immediately when the model reaches the next selection phase without GPU motion.
Both GL and Vulkan fail. Vulkan records a fixed centroid near (937.68,757.05)
with completed presentations moving only from 17 to 18. The Java AnimationTimer
observer logs the initial model position but no intermediate >10-unit displacement
before natural completion. This suggests missing/tardy intermediate pulses or
renders, but does not yet locate the bottleneck. Continuous readback has observer
overhead and must not be treated as an FPS measurement. Existing original VFX
business code and animation duration are unchanged. The stricter test is left
failing, not weakened. The structured failed Vulkan report and start image are
vfx-animation-mobile-separate-motion-failed.json and matching -start.png.
Next work: profile pulse/render scheduling and presentation throughput, compare
with a capture-free timing control, then fix and rerun the strict GPU-motion gate.

OWNER HWND RECREATION: NativeOrderProbe now has seventeen phases, including
hiding and re-showing the owner of the nested Stage chain. This reproduced a
SetWindowPos failure: Windows destroyed owned HWNDs when Godot destroyed their
owner HWND, leaving live Godot Window objects with invalid handles. Before hiding
an owner, refresh_native_owners now detaches its direct owned HWNDs; after a window
is recreated it refreshes native owner links. Owners without HWNDs are skipped
without calling DisplayServer with an invalid ID. GL/safe engine,
Vulkan/separate engine and packaged Vulkan/separate Runtime pass all seventeen
phases and final zero-resource checks. engine rebuild successfully.
The failing log is native_order-gl-before-owner-hide-fix.log.

OWNED-WINDOW INPUT CANCELLATION: The native input regression then exposed a third
child Button action (expected two) when a held press lost focus to its owner and
was released before a new touch. GodotApplication.focus previously canceled only
keys, relying on a later OS focus-loss event for pointer cancellation. It now
cancels all held input on logical focus transfer as well, balancing releases
outside the View and suppressing the stale release. GL/safe and Vulkan/separate
native input probes pass exact mouse/touch action counts, focus, wheel, close veto
and final cleanup. Vulkan modal and popup regressions pass. The SDK rebuild
succeeds; native-stage-input-before-focus-pointer-cancel.log preserves the failure.

NATIVE MODELESS OWNER FIX: Expanded NativeOrderProbe from seven to fifteen phases
with two nested owned Stages. Raising their owner exposed that Godot's nonexclusive
transient flag did not set GWLP_HWNDPARENT, so the owner could cover its children.
configure_native_window now establishes the HWND owner on show/recreation without
turning on Godot exclusivity. GL/safe engine, Vulkan/separate engine and packaged
Vulkan/separate Runtime pass owner raising, child/owner lowering, leaf hide/reshow
and final zero-resource checks. engine builds and Vulkan native Stage
lifecycle regression pass. The failing order log is retained as
native_order-gl-before-native-owner.log. Hidden-owner and topmost combinations
remain outside this probe's scope.

Modal regression initially failed because its old click fixture omitted the
current 200% output scale. Correcting native click coordinates makes GL/safe and
Vulkan/separate pass with the original immediate owner-focus assertion; a trial
asynchronous assertion was removed. Failure logging now includes title/window
count/enabled state. The old three-frame screenshot could contain only the clear
color, so capture now waits (at most 120 frames) for dark glyph content and fails
if none appears. The resulting Vulkan GPU image was inspected and contains the
Close inner button. These are GPU captures, not physical desktop screenshots.

NATIVE STAGE ORDERING: primary toBack previously threw an unsupported-operation
exception; secondary toBack only changed the Java logical list. New zero-payload
commands 22/23 lower/raise the actual HWND on the Godot main thread. Command 21
remains reserved for the root custom-cursor path. The first native test exposed
another gap: toFront used a focus request, which did not raise an already focused
window after toBack. It now explicitly uses HWND_TOP without activation, resize
or movement; toBack uses HWND_BOTTOM. NativeOrderProbe/native_order.gd and
test-native-order.ps1 verify seven actual HWND-order phases with the root and two
unowned secondary Stages, OS window count three, and final zero resources.
OpenGL/safe engine, Vulkan/separate engine and packaged Vulkan/separate Runtime
pass. Protocol validation covers both commands and malformed arguments. SDK,
engine rebuild successfully. The failed pre-raise GL run is retained
as native_order-gl-before-explicit-raise.log. Owned/topmost/unfocusable ordering
combinations and physical desktop interaction remain outside this test's scope.

STANDARD FXML HOST COVERAGE: Added FXMLProbe, tests/reference/fxml resources,
fxml.gd/.tscn and test-fxml.ps1 with Renderer/RenderThread/Runtime. The application
uses ordinary FXMLLoader with fx:controller, private @FXML fields/initialize/event
handlers, injected location/resources, a relative fx:include and a relative CSS
stylesheet. Host input focuses the loaded TextField, replaces its text with
Godot测试, clicks the FXML-bound action, and closes the second FXML-loaded Stage.
The controller checks injected objects, bundle text, include content, FX-thread
callbacks and Chinese result text. The host verifies the CSS swatch's GPU pixel
(#336699), independent secondary native window, four phases and final zero-resource
drain. OpenGL/safe engine, Vulkan/separate engine and packaged Runtime
Vulkan/separate pass. Primary/secondary GPU captures were visually inspected.
The initial GL fixture sampled a white startup frame too early; its log is saved
as fxml-gl-early-render-fence.log. Readiness now queues after the pulse and host
capture waits three post-draw frames. No backend rendering change was made.
This closes the previously missing representative FXML acceptance path, not all
FXML/custom-module combinations. The probe has no VFX dependency; outputs use
fxml-<renderer>-<thread>[-runtime] prefixes. No physical IME claim is made from
injected Unicode input.

REQUIREMENT/DELIVERY AUDIT: Added acceptance-status.md mapping objective sections,
all fourteen acceptance items and eleven delivery items to evidence and open gaps.
Source searches identify remaining explicit Glass failures (system menus, window
icons, primary lowering, virtual keyboard, Robot, non-text clipboard, drag/drop)
and Prism limits (3D, MSAA, mipmaps, planar media). These are not marked implemented.
Default SDK contains javafx.fxml.jar but no FXMLLoader fixture was found in the
current test/script tree; standard FXML/controller/CSS acceptance is a concrete
next task. Native jfxmedia.dll/jfxwebkit.dll remain absent. Current engine
and SDK build exit-code records are zero; actual binaries/DLLs were inspected.
Corrected stale build-output and native-window migration statements. Added
write-delivery-inventory.ps1 to list modified/untracked/staged paths across the
root and source submodules, revisions and selected artifact SHA-256 values.
Its current report records 259 root paths, 5 Godot paths, 40 OpenJFX paths and no
VFX source changes. Counts include submodule entries and are not unique merged
file totals. This inventory is not a completion certificate; broader acceptance
and final document consolidation remain open.

VFX ANIMATION GRAPH INTERACTION: Added VfxAnimationProbe, vfx_animation.gd/.tscn
and test-vfx-animation.ps1 with Renderer/RenderThread/Runtime. Original page 23
is selected without changing its graph or handlers. Host clicks select a then b,
play to natural completion, then select a and d, play again and click soft stop.
The observer reads selection order and the existing red Circle, checks movement,
playing control states, arrival at b, reset of all selections/controls, and soft
stop ending before d. Host GPU readbacks require visible red samples during both
runs, eight action/observation phases, and final presentation/window drain with
zero owned resources. OpenGL/safe engine, Vulkan/separate engine and packaged
Runtime Vulkan/separate pass. The initial GL fixture waited for a
Java title/render fence and missed the short 1.2-second animation; the failed
observation log is saved as vfx-animation-gl-title-fence-missed-frame.log. The
fixture now samples immediately after Play; no animation duration is changed.
The red-point capture was visually inspected. These checks establish model motion,
visible rendering and interaction state, not frame-by-frame animation smoothness
or physical input. Readback-related viewport_get_texture synchronization warnings
occur in this fixture and are not whole-scene performance evidence.

VFX LOADING CANCELLATION: test-vfx-loading.ps1 now accepts -Cancel, preserving
the normal completion case. Host mouse input clicks the original LoadingStage
CloseButton while progress is below 1.0; the observer requires the original
localized cancellation alert and rejects normal completion. After 500 ms settling
with the alert open, it records progress, dismisses Ok through host input, then
observes one second with no new secondary windows and unchanged progress. Loader
and alert retain the independent native identity checks and final zero-resource
drain. OpenGL/safe, Vulkan/separate and packaged Runtime Vulkan/separate pass;
settled progress values in these runs are 0.45, 0.14 and 0.33. The Runtime error
alert GPU capture was visually inspected. Normal completion was rerun on
Vulkan/separate and also passes. No production/VFX handler changes were needed.
Cancel logs and captures have a -cancel suffix. This bounded observation does
not claim that every possible delayed worker/error interleaving is covered;
injected item failure and physical close-button input remain unverified.

VFX ORIGINAL LOADING FLOW: Added VfxLoadingProbe, vfx_loading.gd/.tscn and
test-vfx-loading.ps1 (Renderer/RenderThread/Runtime). The observer selects original
Intro page 26 and host mouse input clicks its Open LoadingStage button. Original
100 loading items, 20 ms interval, TaskManager work, callbacks and alert handlers
are unchanged. The observer checks changing labels, at least three observed
progress values, monotonic progress in [0,1], final 1.0, automatic loader closure,
and the original "loading complete" alert. Host checks that loader and alert are
visible independent native windows, have different Glass/native identities, and
that the loader is destroyed before acknowledging the alert. Host clicks Ok;
all presentation/windows must drain and removal must leave zero owned resources.
OpenGL/safe engine, Vulkan/separate engine and Vulkan/separate packaged Runtime
pass. Observed progress changes are 8, 30 and 19 respectively, all ending at 1.0.
Loading and completion GPU captures were visually inspected. Logs/captures use
vfx-loading-<renderer>-<thread>[-runtime] prefixes. This covers normal completion,
not cancellation, injected load failure, physical input or smoothness/performance.
No production code or VFX business handler changes were needed.

OPENGL FULL VFX RECHECK AT 200% SCALE: Re-ran test-vfx-intro.ps1 -Renderer
gl_compatibility -RenderThread safe -AllPages after the native-memory fixes.
All 35 original pages are acknowledged via the observer after host Next-button
input, captured at 2560x1600, and close normally with final_owned_resources=0.
The manifest is artifacts/reference/vfx-pages-gl_compatibility/run.json; the log
is artifacts/logs/vfx-intro-gl_compatibility-safe-all-pages.log. Comparison against
the completed 35-page D3D reference at system_scale=2 produces the paired sheet
and JSON vfx-comparison-gl_compatibility.*. The paired sheet and full captures of
FusionPane, the editable table, components and image-backed transparent components
were inspected. Table pages 18/19 have mean absolute RGB errors 0.011251/0.007874
with randomized contents and timestamps; animated-control pages also differ.
These are visual triage values, not pass/fail thresholds. No production change
was needed in this run. All-page navigation does not exercise every control;
LoadingStage's original load/completion/alert flow and animation graph interaction
remain concrete follow-ups. Physical input, OS desktop captures and performance
acceptance also remain open.

VULKAN SCREEN DESCRIPTOR CACHE CLEANUP: Vulkan SubViewport-only churn completes
180 cycles with 468 bytes of static-memory range after cycle 20, while native
Window churn previously grew by roughly 32 bytes per new texture plus map growth.
RendererCompositorRD::render_target_descriptors inserted one RID-to-RID entry per
screen texture and never erased entries invalidated by texture destruction. The
uniform sets themselves were released through RenderingDevice dependencies, but
the map entries remained. Screen blitting now uses the existing UniformSetCacheRD,
whose invalidation callback removes the cache entry when its resources are freed.
Its cache key also includes the shader variant and bindings. The obsolete map is
removed. engine source builds pass.
Post-fix Vulkan/separate native Window churn completes 180 cycles with the
StaticRangeLimitBytes=1024 gate enabled: cycle 20..180 static range is only
62272249..62272749 (500 bytes); last sample 62272717, texture_bytes=1835008.
The before-fix log is retained as native-churn-Window-mobile-separate-before-descriptor-fix.log.
Real Stage Vulkan/separate regression also passes 180 cycles at -Xmx128m without
forced GC: owned=29, texture_bytes=13209600 throughout warm checkpoints and final
resource drain zero. Static bytes over cycles 20..180 vary 72772823..72801479;
cycle 20 is 72788903 and cycle 180 is 72789751. Last Java sample: heap_used=74032200,
gc_count=7, collected_stages=154. Packaged Runtime Vulkan/separate VFX window
controls pass maximize, restore, minimize, native restore and close, including
native geometry and resource drain. The maximized GPU capture was visually
inspected. These bounded observations do not establish whole-process/driver or
unlimited-duration stability. The two observed per-window retention defects are
fixed; broader final acceptance remains open.

WINRT WINDOW CALLBACK OWNERSHIP FIX: SubViewport churn (no native window) stays
at 54005830 static bytes after warmup through cycle 180, narrowing the growth to
native window setup/teardown. WinRTUtils::create_wd allocated an advanced-color
event handler with COM refcount 1, then QueryInterface added a reference without
releasing the original. Window teardown removed the event registration and its
ComPtr, leaving the handler and its Godot Callable alive. The code now adopts the
initial reference directly into the typed ComPtr with Attach, preserving callback
registration and automatic release on both success and early return.
engine source builds pass. Post-fix ordinary Window OpenGL/safe churn
completes 180 cycles: all cycle 20..180 samples equal 54005810 static bytes, with
texture_bytes=3381603 unchanged. The runner has an optional StaticRangeLimitBytes
gate over cycle 20..180; a 1024-byte gate was also applied to the completed JSON
and passed. Pre-fix logs are retained with -before-winrt-fix suffixes. Real Stage
OpenGL/safe also passes 180 cycles at -Xmx128m without forced GC: cycle 20..180
static bytes range 63305782..63305790 (8 bytes), owned resources stay 29 and
texture bytes stay 18464819; final removal drains resources to zero. Last Java
sample: heap_used=58372640, gc_count=7, collected_stages=160. The previous
64-byte-per-window trend is resolved in these workloads. Vulkan ordinary-window
post-fix verification completes 180 cycles (texture bytes stay 1835008): static
bytes rise from 61978125 at cycle 6 to 61988209 at cycle 180, with many successive
samples increasing by 32 bytes and occasional larger steps. That residual trend
is a separate unresolved allocation issue; overall memory acceptance is open.

NATIVE WINDOW MEMORY ISOLATION: Added native_churn.gd/.tscn and
test-native-churn.ps1. No JVM or JavaFXHost is started. The Window case creates
and closes 180 ordinary force_native Godot Windows, checks two OS windows while
open and one after closure, and streams static/texture-memory observations.
OpenGL/safe reproduces the trend: cycle 6 static_bytes=54001286, cycle 180
54012546, texture_bytes=3381603 throughout. The initial Vulkan/separate run
crashed in igvk64.dll during unfenced window removal at cycle 23; the log is
preserved as native-churn-Window-mobile-separate-unfenced.log. The fixture now
disables viewport updates and calls RenderingServer.force_sync before removal,
matching the fence already present in JavaFXNativeWindow. With that fence,
Vulkan completes all 180 cycles: static bytes 61974913 at cycle 6, 61996133
at cycle 180, texture_bytes=1835008. This is not proof of the crash's exact cause.
The OpenGL Idle control performs the same sampling/waits without window creation;
static bytes remain exactly 54002122 for cycles 20..180. Thus sampling alone does
not reproduce the sustained trend, and ordinary Godot windows reproduce it without
Java/Prism. Allocation ownership/root cause is still unresolved; no production
memory fix is claimed. The runner also supports JavaFXNativeWindow for subsequent
isolation, but that variant has not yet been run. Reports/logs are named
native-churn-<Kind>-<renderer>-<thread>.json/.log. PASS covers lifecycle/sample
completeness only, not flat static memory. Overall memory acceptance stays open.

INDEPENDENT STAGE CHURN WITHOUT FORCED GC: Added StageChurnProbe and
stage_churn.gd/.tscn with test-stage-churn.ps1. Host input opens/closes owned native
Stages of three alternating sizes, checks each target's pixels and native identity,
then waits for closure and samples a warm baseline. No System.gc call is used.
The default 36-cycle Vulkan run passed, with owned=29 and texture_bytes=13209600
after warmup, but its rising Java heap was not treated as leak proof. Added
configurable Cycles/HeapMiB, natural GC counts and weak Stage references, plus
post-process JSON reports. The 180-cycle, -Xmx128m Vulkan/separate run passes exact
owned-resource and texture-memory baseline checks after cycle 6 and final zero
native resources. Last Java sample: heap_used=29208800, gc_count=8,
collected_stages=173. Godot static bytes after warmup range 72479035..72526675
(first 72495039, last 72516903). This is a bounded workload observation, not an
unbounded-duration leak guarantee or measurement of all driver/process memory.
An initial version retained sample dictionaries inside Godot and therefore
contaminated static-memory measurements; it now streams logs and reconstructs
reports after process exit. Retained-observer log is saved separately. Reports
are artifacts/reference/stage-churn-<renderer>-<thread>-<cycles>-heap<MiB>.json.
The 180-cycle OpenGL/safe run with -Xmx128m also passes the native-window,
owned-resource (29), texture-memory (18464819 bytes) and final-zero checks.
Its last Java sample has heap_used=59166712, gc_count=7 and collected_stages=160.
However, Godot static memory grows from 63306154 bytes at cycle 6 to 63317310
at cycle 180 (11156 bytes, approximately 64 bytes/cycle). This small sustained
native-memory trend remains unresolved and is not covered by the passing resource
assertions. Isolating native-only window churn is the next diagnostic step;
full memory-stability acceptance remains open.

FIXED RENDER-TARGET TEXTURE RID CACHE: JavaFXRenderTarget::get_texture previously
called RenderingServer.viewport_get_texture for every sample, synchronizing the
separate render thread. Inspection of RD and GLES3 texture storage confirms these
fixed-size, non-overridden targets retain their texture RID until target teardown.
initialize now queries once after viewport setup; get_texture returns the borrowed
RID. It is not independently freed or counted as another allocation, and existing
main-thread/pass-open guards remain. Added a get_texture binding and repeatable
texture_lookup fixture/runner: six render/finish/readback cycles, 1000 identity
checks per cycle, red-pixel verification and target reference release.
Before-cache Vulkan batches (microseconds per 1000): 2873,2242,25509,2396,31551,1287;
after-cache: 140,135,170,170,147,171. Observed medians are 2634.5 versus 158.5 us.
This isolated six-batch comparison is not a whole-scene frame-rate benchmark.
OpenGL cached batches are 139,137,149,158,151,150 us. engine source builds
pass. The 100-cycle render-target copy/alpha/clip/source-retention regression passes
OpenGL/safe and Vulkan/separate; its runner now exposes RenderThread explicitly.
All 39 effects retain their comparison thresholds on OpenGL/safe engine and
Vulkan/separate packaged Runtime. The Vulkan/separate long-table drag, bottom/top
scroll, clip-sampling and resource-drain regression also passes; its current log
contains no viewport_get_texture synchronization warning. No whole-scene frame-rate
or long-term memory-performance conclusion is claimed from this change.

VFX LONG TABLE SCROLL VALIDATION: Added VfxScrollProbe and
vfx_scroll.gd/.tscn with test-vfx-scroll.ps1, using original Intro page 19's
50-row, 1500-logical-pixel-wide table inside a 1000x500 horizontal viewport.
Host drag moves horizontally by 250 logical pixels, wheel input reaches the
vertical bottom (observed -1050), reverse wheel returns to the top, and reverse
drag restores x=0. The observer reads the existing clipped Group transforms;
it does not set scroll state. Bottom detection checks the content/viewport size
difference, not merely any movement. Host captures require changed interior
pixels and unchanged sampled strips outside the left/right clip. OpenGL/safe,
Vulkan/separate and packaged Runtime Vulkan/separate pass, including final window
drain and zero resources after removal; the bottom capture was visually inspected.
This is synthetic host input and sampled clip coverage, not physical-input,
exhaustive clipping or performance acceptance.
Desktop acceptance rechecked this turn: computer-use Initialize still returns
"Module not found: @oai/sky"; the configured runtime node_modules directory also
lacks @oai/sky. No custom helper/protocol fallback was used. OS-desktop screenshots
and physical interaction therefore remain unverified; other implementation work
continues.
The separate-render-thread log warns about repeated viewport_get_texture
synchronization; JavaFXRenderTarget::get_texture currently queries RenderingServer
on every access. This is a concrete performance follow-up, not yet an optimization
or measured speedup.

VFX ORIGINAL TABLE INTERACTION: Added VfxTableProbe, vfx_table.gd/.tscn and
test-vfx-table.ps1. The original Intro page 18 business code/data generation is
unchanged. The observer reads the VTableView captured by Add's anonymous button;
all actions are host mouse/key input. Eight phases verify Add, identity-based row
selection, TextField focus, Ctrl+A plus Godot测试 character input, focus-loss data
commit, ascending and descending bandwidth model order, then deletion of the
selected data object. Initial count 10, added count 11, final count 10, complete
native window/presentation drain and zero resources after removal are required.
The first fixture assumed column-header clicks committed a TextField; that header
does not request focus. Saved failure in vfx-table-header-focus-assumption.log;
the corrected sequence explicitly focuses another TextField before sorting.
OpenGL/safe, Vulkan/separate and packaged Runtime Vulkan/separate pass at scale 2.
Committed-text and descending-sort
GPU captures were visually inspected (vfx-table-<renderer>-<thread>-5/7.png).
No production/backend change was needed for these interactions. This does not
verify physical input, IME, all sorting combinations, long-table scrolling or
performance acceptance.

VFX INDEPENDENT WINDOW CONTROL ACTIONS: Added VfxWindowControlsProbe and the
vfx_window_controls host fixture/runner. Host mouse input clicks the original VFX
MaxResetButton twice, IconifyButton, then CloseButton; restoration from minimized
is triggered on the native Godot Window so Java must consume the host notification.
The test checks only the child changes mode, native HWND independence, maximized
geometry equals the monitor work area, restored Java geometry matches the original,
all five phases, final window drain and zero native resources after removal.
This exposed two real defects. Windows borderless maximize MoveWindow omitted the
two-pixel expansion which WM_WINDOWPOSCHANGED subtracts. The resulting 3120x1982
client rect lost MAXIMIZED classification. The direct and OS-maximize adjustment
paths now add the existing expansion consistently; work-area content is 3120x1984.
Second, GodotWindow native refresh sent RESIZE when a minimized/maximized host
became normal. Glass cleared its own state, but Quantum only clears public Stage
properties on RESTORE. Primary and secondary refresh now select RESTORE on that
transition. Failure evidence: vfx-window-controls-first-failure.log and
vfx-window-controls-native-restore-failure.log. Source SDK/engine builds
pass. New controls test passes OpenGL/safe, Vulkan/separate and packaged Runtime
Vulkan/separate at 200% scale; existing 13-phase native Stage fullscreen/Escape/
restore Vulkan regression also passes. Maximized and restored render-target PNGs
were visually inspected. These use injected host input and GPU captures, not
physical taskbar interaction or OS-desktop screenshots; multi-monitor cases remain
outside this test's scope. VFX business code is unchanged.

PRESENTING PAINTER HOST CANCELLATION: PresentingPainter now handles only the
internal GodotHostStoppedException at the whole-frame boundary, retiring the
incomplete presentable while retaining normal finally/unlock/painting-completion
and error-path stale-texture-lock handling. All other Throwables retain the
upstream reporting path. SDK builds successfully. The host-stop gate now rejects
all leaked cancellation exceptions as well as RenderJob/renderer errors; it passes
OpenGL/safe, Vulkan/separate and packaged source Runtime Vulkan/separate, including
native/Glass closure, Application return, renderer join, Context disposal, zero
Java pool bytes and zero native owned resources after removal. Saved prior painter
logs in host-stop-before-painter-cancellation.log.
VFX tree-quit diagnosis now reaches main's sequence assertion, confirming that
Application returns instead of getting stranded. Added an explicit -Abrupt runner
mode: it requires exit while phase 1's independent Stage is open and verifies the
bridge reports host stop, then requires VFX_STAGE_ABRUPT_RETURNED. It retains all
observer failure checks and rejects exceptions/suppressed failures; regular mode
still requires all 12 phases. OpenGL/safe and Vulkan/separate abrupt tests pass.
The regular 12-phase Vulkan/separate Stage creation/closing/resize run also passes
with the revised runner and observer.
Application-failure/nested-modal Vulkan/separate regression preserves the injected
failure and passes cleanup. These are representative lifecycle regression results,
not proof for every possible cancellation interleaving or full project acceptance.

RENDER CANCELLATION RESOURCE CLEANUP: A cancelled vertex flush/admission in
GodotTexture.Data.dispose previously escaped before releasing its slot or letting
ManagedResource clear the shared resource and pool charge, aborting pipeline
cleanup. Typed host cancellation now releases that Java state while native GPU
teardown remains host-owned. Other failures still propagate without pretending
disposal succeeded. TextureCancellationProbe deterministically injects cancellation
at the flush boundary and verifies shared aliases become lost, accounting reaches
zero, repeated disposal is harmless, slot generation advances, and a genuine error
is preserved with the resource still live until a successful retry. The source
patch test fails before the repair (texture-cancellation-before.log) and passes
after it. GodotContext also releases retained window targets after cancelled
remove/configure commands and rewinds cancelled vertices when releasing a target.
Source SDK build passes. HostStopProbe now joins the renderer and asserts Context
disposal and zero Java texture-pool bytes in addition to its native/Glass lifecycle
checks. OpenGL/safe and Vulkan/separate both pass; their gate now rejects RenderJob
internal exceptions and uncaught renderer exceptions. In-flight PresentingPainter
work still logs typed cancellation, so complete abrupt-shutdown acceptance remains
open. This is not suppression of arbitrary drawing or protocol failures.
Vulkan/separate VFX Stage/resize and nested-modal application-failure shutdown
regressions pass after these resource-disposal changes.

EXPLICIT HOST STOP / GLASS SHUTDOWN ORDER: Added HostStopProbe and host_stop.gd,
which open primary/owned/grandchild Stages, call stop_host while retaining the Host
in the tree, and verify actual OS window removal, idempotent stop, Application.stop
and launch return, all three Glass handles closed, JVM completion, and zero owned
resources after Host removal. Before repair, stop retained two native windows
(host-stop-before.log). stop_host now stops native admission, destroys the native
owner trees and clears snapshots before stopping frame admission. A second failure
showed the scheduler directly terminated Glass, racing PaintCollector and stranding
Application.launch. It now requests Platform.exit so Quantum coordinates shutdown.
The intermediate log host-stop-quantum-order.log proved Application returned but
Glass peers survived because base termination aborted at the first cancelled hide.
GodotApplication now attempts hide and close for every peer; only typed host
cancellation is consumed during termination, with other failures still reported.
GodotWindow releases its Java peer after cancelled native close; native destruction
remains host-owned. SDK/engine builds pass. OpenGL/safe and Vulkan/separate
host-stop tests pass all the stated window/lifecycle/resource assertions. Render
submission, queued RenderJobs and renderer resource disposal still log typed host
cancellation, including an uncaught renderer cancellation; this is an explicitly
limited lifecycle regression gate, NOT acceptance of complete abrupt shutdown.
Vulkan/separate VFX independent Stage/resize and nested-modal application-failure
shutdown regressions also pass after the changes.

TYPED HOST CANCELLATION: JNI frame admission STOPPED and native-window transport
finish/stop now report internal GodotHostStoppedException (CancellationException)
instead of generic IllegalStateException. The render encoder keeps host cancellation
separate from its permanent protocol/error state, including backpressure awaitTick
shutdown and subsequent calls. Invalid arguments, queue limits and other failures
retain their existing error behavior; no cancellation is suppressed. Native protocol
tests cover typed finish/stop rejection and pending-command removal, and pass with
the existing malformed-input/backpressure/10,000-frame cases. Source SDK, engine and
Runtime builds pass. Vulkan/separate VFX independent Stage creation/closing and
resize regression passes. The Stage runner also rejects logged typed cancellation
during a normal run. Abrupt diagnostic vfx-abrupt-typed-cancellation.log confirms
both JNI window cancellation and render cancellation, without misleading encoder
failure messages. It still logs cancellation from Application.terminate hiding
windows and queued RenderJobs; abrupt teardown remains unaccepted and unfinished.

HOST-STOP QUEUED PULSE FIX: GodotPulseScheduler previously posted hostStopped
behind an already queued pulse without clearing running, so the stale pulse could
execute onFrame/timers after the receiver had observed shutdown. It now clears
running before enqueueing termination. Added an injectable internal TickSource and
a deterministic standalone probe: hold the event loop, queue one pulse, return
host-stop, join the receiver, then release the loop. Before the fix one stale
onFrame ran (pulse-stop-before.log); after it, all 50 iterations run no stale frame
and terminate. test-pulse-stop.ps1 patches only the scheduler class from source
against the SDK for this isolated race test. SDK build, Glass scheduler threading/
nested-loop/timer/cancellation regression and Vulkan VFX Stage/resize regression
pass. The scheduler fixture's primary-screen assertion now compares platform width
to native pixels, correcting its old scale-1 assumption.
An abrupt VFX run remains diagnostic (vfx-abrupt-pulse-fix.log), not accepted:
in-flight submissions/window operations can still fail when native queues stop.
This fix covers queued pulses only; it does not suppress protocol errors or claim
complete cancellation/teardown safety.

NATIVE WINDOW TREE-EXIT FENCE: Node tree teardown visits children before the host's
EXIT_TREE cleanup. JavaFXNativeWindow now disables its viewport and synchronizes
RenderingServer in its own reverse-order EXIT_TREE notification, before base
Window deletes the native swap chain. Explicit host destruction already fenced,
but parent/tree teardown could bypass that path. SDK-independent native test
removes a parent with three rendering native windows for 12 cycles, checking
surface resource and OS-window cleanup; GL/safe and Vulkan/separate pass. This
small fixture also passed before the change, so it is regression coverage, not
proof of reproducing/fixing the earlier fatal race. Editor/release builds and the
full Vulkan VFX Stage/resize regression pass after the fence.
VFX_ABRUPT diagnostic exits directly with a child alive. Before/after runs exited
without native errors in these samples, but both log Java submission/transport
stopped exceptions and poisoned encoder errors. Thus abrupt shutdown remains
UNACCEPTED, as does the previously observed intermittent native fatal condition.
Logs: native-exit-before.log, native-exit-<backend>-<thread>.log,
vfx-abrupt-before.log, vfx-abrupt-after.log. Next work is cancellation propagation
and deterministic coverage of in-flight shutdown, not suppressing these errors.

VFX RESIZE DRAG: the Stage factory fixture now drags the default VStage's actual
transparent corner Circle from 400x400 to 460x440 logical units, waits for both
native window and published content to reach 920x880 pixels, then reverse-drags
back to 800x800 pixels at scale 2. The same drag on setResizable(false) leaves the
window unchanged. GL/safe and Vulkan/separate pass and complete all six open/close
paths with zero-resource teardown. Initial synthetic mouse DOWN omitted its held
left-button mask: the Circle received DOWN but Quantum did not establish a drag.
The fixture now supplies that mask and flushes buffered motion before release.
No runtime/VFX rendering fix was needed for this input-construction error.
The first failed assertion forcibly quit with rendering still active and triggered
the previously outstanding Vulkan teardown failure; log retained as
vfx-stage-resize-first-failure.log. Resize assertion failure now requests FX exit
through a diagnostic F12 event and waits for runtime termination before quitting.
This improves this fixture's failure path, NOT general abrupt/fatal host shutdown.
VFX maximize/minimize control interaction and physical OS drags remain unverified.

VFX STAGE FACTORY BUTTONS: VfxStageProbe observes the unmodified page-2 Demo and
host mouse events activate all six original FusionButtons: default, no iconify,
no maximize/reset, no close, non-resizable and custom initial scene. Twelve phases
open and close each window through actual controls (the no-close variant uses
its interior close button). Java checks 400x400 logical dimensions, expected
CloseButton/IconifyButton/MaxResetButton presence and custom welcome content.
Godot checks 800x800 native size at scale 2, distinct native identity, actual OS
visibility, non-embedded status, native-window counts and final zero-resource
teardown. GL/safe and Vulkan/separate pass; the custom initial scene capture was
visually inspected. No VFX business code or runtime implementation was altered.
This verifies construction/control configuration and close actions; it does not
yet exercise the VFX resize-drag handler, disabled-resize behavior, minimize or
maximize button actions. Captures/input remain viewport/injected, not OS desktop
acceptance. Runner: scripts/test-vfx-stage.ps1.

VFX PAGE-2 BORDER DISCREPANCY RESOLVED: FusionButton's border-light opacity animates
over a 10-second cycle and is disabled/enabled by window focus. The navigation and
D3D capture runs did not synchronize those states. Added explicit diagnostic
FreezeFusion/PageLimit options to both capture paths, using separate frozen image
directories and leaving normal runs unchanged. With animation disabled through
FusionButton's public API, the first three Vulkan/separate pages pass navigation
and teardown. Their scaled D3D comparisons all have mean error .0000030637 over
the existing content crop; page 2's central rectangle (100,150)-(2460,1350) is
pixel-exact (RGB difference bbox is empty). Frozen contact sheet visually inspected.
Thus the observed border difference is state/timing-dependent, not evidence of a
border-rendering defect. No runtime or VFX business implementation changed.
Diagnostic reference log is vfx-reference-frozen.log; normal full-page images and
manifests remain separate. This does not validate animation timing/performance or
the page's Stage-opening button actions; those remain separate acceptance work.

VFX ALL-PAGE REVALIDATION AT SCALE 2: test-vfx-intro now explicitly supports render
thread selection and scales navigation coordinates/sample regions. Vulkan/separate
completed all 35 pages at 2560x1600, then drained windows and reached zero owned
host resources. run.json records scale, dimensions and final resource count.
Source-D3D reference capture now uses the same output-scale snapshot transform,
with running/passed manifests. compare-vfx-pages validates both completed manifests,
page counts and scale, and uses a scaled content crop. Current reference and Vulkan
captures compare without size mismatches. The 35-page contact sheet was inspected;
page 18 also inspected at full capture resolution. Highest mean RGB differences:
page 18 .011406, page 19 .008049 (random/time-bearing tables), page 2 .001539.
Page 2 has a visible button-border discrepancy in the contact sheet; this remains
UNRESOLVED and requires focused comparison, not dismissal based on a low mean.
The report is triage, not a visual pass oracle. This is navigation/render/cleanup
coverage only; per-page interactions, current GL all-page coverage, physical
desktop screenshots and performance acceptance remain outstanding.

BLEND MODES / LIGHT TYPES: the reference grid now has 39 scenes (800x1600 native
pixels at system scale 2). Every one of the 17 BlendMode values is compared with
a patterned translucent ImageInput bottom, a partially overlapping translucent
ColorInput top and Blend opacity .65. Point and Spot lights supplement the Distant
light case. All pass GL/safe, Vulkan/separate and packaged Release Runtime
Vulkan/separate with window/resource cleanup. Fourteen added blend tiles are
exact; MULTIPLY/GREEN/BLUE mean errors are .00000012255. Point/Spot mean errors are
.0005986520/.0008220589, and all added tiles have zero pixels exceeding .08 error.
The larger graph exposed a premature fixture capture: a fixed 180 post-draw count
could finish before the window frame was published, producing a blank image.
The test now waits for retained window content and completed composition within
its existing deadline. The first failure is preserved as
effects-expanded-premature-capture.log. This establishes these concrete blend/light
cases, not exhaustive alpha/parameter extremes or arbitrary effect graphs.

EXPANDED EFFECT COVERAGE: the same D3D/Godot fixture now contains 20 scenes in an
800x800 native image at system scale 2. Added SepiaTone, standalone Shadow,
PerspectiveTransform, a translucent patterned ImageInput, ColorInput, and a
GaussianBlur -> SepiaTone -> DropShadow chain. GL/safe, Vulkan/separate and packaged
Release Runtime Vulkan/separate all pass with normal window/resource teardown.
New SepiaTone/Shadow/ColorInput tiles are exact; PerspectiveTransform mean error
is .0000598039, ImageInput .0000001225 and the chain .0000002451. No new tile has
pixels over the existing .08 channel-error threshold. The grid was visually
inspected, including perspective geometry and alpha-pattern input. No production
shader changes were required. This broadens type coverage, but does not claim all
Blend modes, light types, parameter extremes or arbitrary effect graphs accepted.

STANDARD EFFECT REFERENCES AT SYSTEM SCALE 2: EffectsProbe now creates its D3D
reference with an explicit output-scale SnapshotParameters transform and viewport,
instead of comparing a logical-resolution Scene snapshot against a native 2x
Godot viewport. At the current scale 2 both images are 800x640. Each 100x80 logical
tile is compared over its complete physical pixel area; the original mean <= .01
and at most 1% of pixels exceeding .08 channel error limits are preserved.
All 14 scenes (including the no-effect control) pass GL/safe, Vulkan/separate and
newly supported packaged Release Runtime Vulkan/separate. Eleven tiles are exact;
MotionBlur mean error is .0000046569, DisplacementMap .0000323529 and wrap variant
.0000219363, with zero pixels above .08 in every tile. Normal window drain and
final zero-resource teardown pass in all three configurations. The native-size
effect grid capture was visually inspected. This covers the listed fixture effects
and settings, not every effect/property combination, OS screenshots or performance.

GODOTVIEW / NODE SHADERS AT SYSTEM SCALE 2: GL/safe and Vulkan/separate now pass
GodotView composition, clip/opacity, live scene redraw, layout resize without scene
reload, sibling input isolation, mouse/key/wheel/touch translation and cancellation,
and final disposal. Host pixel samples and injected coordinates are converted from
logical to native coordinates; embedded scene coordinates remain its logical-sized
SubViewport coordinates. This does not add supersampling of the embedded scene.
NodeShaderProbe also passes both backends for per-node isolation, GaussianBlur
input, scaled-parent clip/opacity, UVs, button text/action, 80 uniform updates and
cleanup. Its runner now explicitly selects safe/separate rendering threads.
The old glyph check skipped native pixels at 2x, missing thin strokes; it now scans
the entire physical text rectangle. A title acknowledgement can precede queued
uniform frames, so the fixture waits (within its existing deadline) for the final
gain=1 pixel state before evaluating the scene. The first failure, including the
subsequent abrupt-test-quit shutdown errors, is retained in
node-shaders-hidpi-first-failure.log. Native 2x shader capture was visually inspected.
These are GPU viewport/injected-input checks; desktop and mixed-monitor acceptance
remain outstanding.

NATIVE STAGE LIFETIME / INPUT AT SYSTEM SCALE 2: fixtures now distinguish logical
JavaFX coordinates from native window pixels. HostLifetimeProbe passes GL/safe,
Vulkan/separate and packaged Release Runtime Vulkan/separate: closing the primary
hides its HWND while an independent Stage keeps rendering/responding, a later
Stage remains independent, and closing the last Stage causes implicit FX-thread
exit. NativeStageProbe's thirteen phases cover decorated independent creation,
resize/move, hide/reshow, fullscreen/normal/Escape and maximized/fullscreen state
restoration; GL/safe and Vulkan/separate pass. NativeStageInputProbe passes both
backends for overlapping-window click isolation, focus/typing, wheel, cancellation
of a held mouse press on focus change, touch synthesis and native close veto.
New assertions check wheel/touch scene AND screen coordinates at scale 2. Final
window/resource cleanup passes. These remain injected native-window input tests,
not physical desktop interaction or multi-monitor DPI transition acceptance.

NATIVE POPUPS AT SYSTEM SCALE 2: popup selection/dismissal/context-key activation,
three-level menu navigation/hover, screen-edge upward/left flipping and custom
Popup autoFix true/false now pass GL/safe and Vulkan/separate at the actual 200%
system scale. Input fixtures convert JavaFX logical points into the target native
window's pixel coordinates. Edge bounds compare logical Screen visual bounds to
the scaled native usable rectangle. The prior PopupBoundsProbe was still a legacy
embedded-window test: it incorrectly required Popup content inside the owner's
resized bounds and sampled pixels in the root viewport. It now checks the screen
work area, explicitly requires overflow beyond the shrunk owner, and samples the
independent popup viewport while verifying native identity/visibility/position.
Its eight stages cover owner resize/move, autoFix off/on, hide, owner move/resize
while hidden, reshow, and owner-close cleanup. Both backends pass with native
windows drained and final host resource count zero. The captured edge submenu
was visually inspected at native 2x resolution; captures remain GPU viewport
images, not desktop screenshots. No rendering implementation change was needed
for these regressions. Mixed-monitor transitions and physical input remain open.

SYSTEM DPI BRING-UP (Windows): Glass now derives platform/output scale from the
Godot Windows effective DPI (DPI / 96), respecting prism.allowhidpi. Screen logical
bounds/work areas use the anchoring algorithm from upstream GlassScreen.cpp;
native platform rectangles remain unchanged. Screen association refresh also
notifies scale changes and view size. Synthetic ScreenLayoutProbe checks left,
right, above, bottom-aligned, offset, chained and disconnected monitor layouts,
fractional rounding and disabled HiDPI. It does not simulate native DPI events.
The available 192-DPI screen now reports output scale 2. RenderScaleProbe checks
logical Scene size, native output size, buffer dimensions, pixel positions and
both local/screen mouse coordinates across six explicit render scales. GL/safe
and packaged Release Runtime Vulkan/separate pass, as does the engine Vulkan
run (before the additional screen-coordinate assertions). The updated screen
metadata probe and VFX independent-dialog regression pass on Vulkan/separate.
The 200-snapshot stress regression also passes at system scale 2, with 65 retained
resources / 978,944 texture bytes after warmup and final host teardown to zero.
SDK rebuild passes; this turn changes Java and fixtures, not native binaries.
Real mixed-monitor transitions, native DPI changes, logical-size preservation
during those transitions and physical desktop verification remain outstanding.
Older fixed-pixel fixtures/results predate default system scaling and must be
adapted/revalidated before being counted as current HiDPI acceptance.

EXPLICIT STAGE RENDER SCALE: GodotPresentable now applies Prism's render scale
to its graphics, matching the D3D createGraphics contract. Independent native
windows retain the published output dimensions separately from the render-target
dimensions, so supersampling does not enlarge or clip their displayed content.
The six-phase RenderScaleProbe switches primary/child scales independently through
1, 2, fractional and anisotropic values, checks actual buffer dimensions and
displayed pixel positions, alternates local mouse clicks, verifies distinct native
window IDs, and requires final window/resource teardown. GL/safe, Vulkan/separate
and packaged Release Runtime Vulkan/separate pass; source SDK/engine
builds pass. Captures are GPU viewport images, not OS screenshots. Initial fixture
widths below Windows' decorated-window minimum were corrected to 320/288 pixels.
This initial run validated explicit renderScale only; the subsequent system-DPI
bring-up above supersedes its scale-1-only status. Mixed-monitor transitions remain
outstanding.
The Vulkan/separate VFX dialog and 200-snapshot stress regressions also pass after
these render-scale changes.

SNAPSHOTS BETWEEN WINDOW FRAMES: the 200-snapshot stress fixture exposed two
boundary errors. publishWindow retained a Java target cache after native
publication had closed its pass, causing a later snapshot to send END_PASS twice.
It now invalidates that cache on publication. The native ledger also rejected
offscreen drawing between window presentations; it now permits an explicitly
selected offscreen target while still rejecting root drawing and publication
without BEGIN_PRESENT. Protocol tests cover acceptance and rollback for those
invalid cases and pass. The first failure log is
snapshot-stress-stale-present-target-failure.log.

`test-readback.ps1 -SnapshotStress` verifies 200 asynchronous snapshots interleaved
with window rendering, GaussianBlur, three widths and changed colors. Every image
is checked for dimensions/pixels and FX callback thread. Every 20 reads, it pauses,
requests GC outside the result callback, and triggers an ordinary dirty frame to
drain Prism disposal. This is a retained-resource audit, NOT a no-GC memory or
latency benchmark. Before GC, new QuantumImage objects kept their cached RTs until
collection; snapshot-stress-before-gc-observation.log records 196/336/476/616
resources at 20/40/60/80 reads. After GC, all ten checkpoints report 38 resources
and 843,776 texture bytes on Vulkan/separate; GL/safe reports 38 and 1,374,051 bytes.
Godot tracked heap stays near 62.6 MB Vulkan / 54.7 MB GL after warmup; this excludes
Java heap and driver allocations. Source SDK/engine builds pass. GL/safe,
Vulkan/separate and packaged Release Runtime Vulkan/separate stress runs pass with
final window/resource teardown. Release Runtime's static-memory counter returns
zero, so only its resource/texture counters are meaningful.
The Vulkan/separate VFX dialog regression also passes after these boundary fixes.

CURSOR VISIBILITY CONTRACT: stock/custom shape changes now preserve Glass's
explicit visibility flag. CURSOR_NONE independently suppresses visibility until
another shape is selected; changing NONE to an ImageCursor restores visibility
only if the explicit flag allows it. The host records the prior Godot mouse mode
on its first cursor operation and restores it on stop. Native cursor diagnostics
are refreshed when showing a hidden custom cursor, and distinguish a visible-mode
fully-transparent image (null Windows cursor handle) from a hidden mouse mode.
The expanded thirteen-step primary/independent-child fixture passes GL/safe and
Vulkan/separate, covering hidden stock/custom changes, explicit show, NONE/image
transition, transparent/default transition and teardown while explicitly hidden.
engine and Release Runtime source builds pass; the packaged Release Runtime
Vulkan/separate thirteen-step fixture also passes.

CUSTOM IMAGE CURSOR: Glass-Godot now copies BGRA_PRE or ARGB_PRE Pixels into an
immutable Java cursor asset, and selects it through the ordered native host queue.
Godot alone creates the Windows cursor on its main thread. Cursor dimensions are
1..256 with validated hotspots; queued cursor assets have a separate 1 MiB bound.
The advertised best size preserves requested dimensions up to that supported cap,
instead of inheriting a fixed 16x16 headless answer. Standard-cursor selection and
host stop reset the custom arrow slot, releasing Godot's cached image/native icon.
Source SDK/editor/Release Runtime builds pass. test-image-cursor.ps1 passes GL/safe and
Vulkan/separate using standard ImageCursor and injected input: primary 32x24 at
(5,7), independent native child 48x40 at (11,13), default cursor, then first image
again. GetIconInfo/GetDIBits inspect the installed Windows cursor's dimensions,
hotspot and premultiplied center pixel; this is stronger than echoing submitted
metadata, but is not a physical-mouse/desktop screenshot acceptance. Host teardown
clears the custom slot and owned rendering resources. The later visibility test
above covers all-transparent behavior. DPI-dependent cursor scale and
long-duration cursor churn remain unverified.

COMPOSITE EDGE BASELINE RESOLVED: the adjacent SRC edge observation below is also
present in source-built D3D. The identical low-level Prism probe now compares all
five CompositeMode values with antialiasing on/off and integer/.25-offset geometry
(20 cases, all 16 RGBA pixels per case). GL/safe and Vulkan/separate both match
D3D within two channel levels, including the transparent SRC row at y=1 when AA
is enabled; the row retains red when AA is disabled on both backends. No renderer
change is justified for this observation. test-composite-edges.ps1 records raw
reference/backend pixels and comparison logs, and checks final host resource
release. This is a resolved compatibility investigation, not exhaustive edge or
shape coverage. The historical readback note below is superseded by this evidence.

EXPLICIT RT READBACK: readPixels now fences admitted rendering and reads on the
Godot main thread, returning owned ARGB_PRE data through JNI. Java supports full
and rectangular IntBuffer/BGRA ByteBuffer reads with positions, limits, slices,
heap/direct buffers and input validation. Normal presentation remains GPU-only.
One pending request and a ten-second wait bound prevent unbounded accumulation;
host stop wakes it without modifying the destination. New targets receive their
transparent initialization; repeated reads do not add empty redraw passes.
Source SDK/engine builds pass. Direct and standard synchronous Node/Scene
plus asynchronous Node snapshot pixel checks pass GL/safe and Vulkan/separate.
The async callback stays on FX. Release Runtime Vulkan/separate snapshot and
observed-pending-request cancellation pass; VFX dialogs also regress successfully.
Raw texture disposal and final host teardown are checked. Snapshot fixtures allow
Quantum's caches until host teardown rather than assuming the raw fixture's eight
base RIDs are the application's whole live resource set.

NEW EDGE INVESTIGATION: in a 4x4 blue RT, SRC half-red at (0,0,2,2), followed by
SRC green at (0,2,2,2), the first read showed transparent pixels at (0,1)/(1,1).
This was initially mistaken for a repeated-read failure; the full first-read data
shows it is already a drawing result. The newer D3D comparison above reproduces
the same result, resolving the suspected backend discrepancy. The buffer-transfer
test uses SRC_OVER to isolate transfer, while the separate edge comparison retains
the original SRC/AA case.

PRISM COMPOSITES: CLEAR, DST_OUT and ADD now join SRC/SRC_OVER in GodotComposite,
using GPU shader output adaptation with Godot's existing replacement/multiply/add
blend states. ADD compensates both RGB and alpha for Godot's SRC_ALPHA factor;
DST_OUT multiplies destination RGBA by one minus source alpha. No CPU readback or
Godot core changes are introduced. GL/safe and Vulkan/separate pass 25 mode/input
combinations plus excluded clip regions, including alpha 0/.25/1, an RT sampler,
custom fragment nested blocks/comments, and final resource disposal. The GL GPU
capture was inspected. This is interior/clip pixel coverage, not exhaustive
antialiasing or arbitrary effect-shader acceptance. The raw test explicitly ends
its last target pass; submission alone does not enable a retained viewport update.
Final source SDK build and both composite backend reruns pass. The existing
14-effect D3D comparison also passes Vulkan/separate with this SDK.

GPU RT BLIT: GodotContext.blit now copies source RT rectangles to an explicit
destination or the Graphics-selected target, using SRC replacement and linear
level-zero sampling directly on GPU. Scaling and reversed source coordinates
work independently of drawing clip, transform, opacity, external shader and source
texture filtering preferences; subsequent normal draws restore their Prism state.
Foreign resources and identical underlying source/destination storage are rejected
explicitly. The source SDK builds. test-blit.ps1 passes GL/safe and Vulkan/separate
pixel assertions for cropped/scaled copies, half-alpha replacement, bilinear
boundaries, horizontal reversal, cached state restoration, alias rejection and
resource disposal. The GL viewport capture was inspected. The existing Prism
context regression also passes Vulkan. MSAA remains incomplete; subsequent
readback and composite work is described above. These results do not establish
desktop acceptance.

FOLLOW-ON PASS BUDGET: the first indivisible batch can wait for previous window
presentation; the host now starts its 4 ms follow-on allowance after that batch,
still checking after each subsequent batch and stopping at 16 total batches.
A batch can exceed the soft allowance. VSync and normal window presentation stay
enabled. The real Vulkan/separate five-action VFX run took 12,725 ms, with 706
offscreen passes, 292 host ticks and 7,646,472 us draw/sync (775 calls). Log:
vfx-dialog-followon-budget.log. This is a functional-run observation, not steady
FPS or a controlled benchmark. The first trial exposed premature test readiness:
component nodes were stationary before the slide-in animation began. The observer
now waits for VSceneGroup.getCurrentMainScene() to commit the component scene in
postShowing, followed by stable coordinates and its existing render-job fence.
Business animations remain unchanged; the failed run is retained in
vfx-dialog-budget-transition-failure.log. Vulkan/separate 14-effect D3D comparison
and injected VFX failure cleanup pass with the new allowance. GL/safe also passes
the 14-effect D3D comparison. Source engine and Release Runtime builds pass;
Release Runtime Vulkan/separate passes nested Application failure cleanup and
host lifetime (primary closure, surviving/new independent native Stages, input,
actual HWND visibility, implicit exit and final resource drain).

DRAW WAIT PROFILING: get_render_stats now reports accumulated wall-clock microseconds
for host processing, command encoding, metadata refresh, native/host commands and
draw+sync, plus draw count/maximum. These intervals overlap and are not GPU timings.
The successful VFX baseline took 27,116 ms, with 20,397,579 us across 631 draw/sync
calls, 1,334,577 us encoding and 76,727 us metadata. Log:
vfx-dialog-draw-timing-baseline.log. A temporary experiment disabling native-window
viewport updates during offscreen draws took 27,670 ms and caused repeated getter
synchronization warnings. It was reverted; its log is
vfx-dialog-window-redraw-experiment.log. No window updates are skipped in final code.
A one-off --disable-vsync diagnostic reduced the first target's mean draw/sync
interval from about 22 ms to 2.1 ms, supporting a presentation-pacing bottleneck.
However, its first injected action did not advance and the 20,000-frame runner cap
terminated it; the full interaction did NOT pass. Its no-vsync log is retained as
limited diagnostic evidence only, and the temporary switch was removed. Default
VSync behavior is unchanged. A controlled wall-clock benchmark and a solution that
preserves presentation synchronization were the next investigation; the follow-on
budget result above is newer evidence, still requiring controlled benchmarking.

BOUNDED OFFSCREEN SHADER REUSE: JavaFXRenderTarget now retains immutable shader
RIDs by exact code, with at most 64 entries per target. Material/uniform state
remains separate for every draw. Once full, additional shader codes use the
existing pass lifetime and are freed at completion; target destruction releases
the cache and resource accounting includes its retained RIDs. A dedicated 75-pass
probe passes GL/safe and Vulkan/separate: same-code reuse across draws/frames,
two simultaneous distinct tint uniforms, alternating pixels, 71 unique codes,
64-entry bound, overflow cleanup and final target/surface disposal. Source engine
and Release Runtime builds pass; 14-effect D3D comparisons pass Vulkan/separate.
The real VFX dialog still passes, but its measured 27,140 ms versus the prior
27,543 ms run does not establish a meaningful latency improvement. Keep the
allocation reduction distinct from the unresolved pass scheduling/GPU cost.
The measurement is retained in vfx-dialog-shader-cache.log.

OFFSCREEN WAIT REDUCTION: separate-thread END_PASS now executes its existing
ordered draw(false)+RenderingServer.sync fence directly in the host process loop,
instead of waiting for a later display-frame callback to initiate that fence.
At this stage the bound was 16 batches / 4 ms from loop start; the later follow-on
allowance is described above. A single draw may exceed the soft budget. Transient
target resources are released only after the ordered draw;
final presentation/native composition scheduling is unchanged. Main-thread render
counters are exposed through get_render_stats and recorded by the VFX dialog test.
An observed Vulkan/separate five-action run changed from 51,178 ms / 516 offscreen
passes / 1,141 host ticks to 27,543 ms / 526 passes / 587 ticks. Logs are
vfx-dialog-offscreen-baseline.log and vfx-dialog-offscreen-immediate.log. Animation
counts differ and these are single functional runs, not a steady-state FPS claim.
The result remains slow; full performance acceptance is outstanding.
Fourteen effect tiles pass the existing D3D comparison thresholds in GL/safe and
Vulkan/separate. Real VFX normal/failure shutdown and Release Runtime nested-failure
cleanup pass; engine source builds pass. The effect fixture formerly
hard-stopped the host after pixels matched, exposing rejected cleanup submissions.
It now waits for its Java probe's normal exit and verifies drained windows/resources;
effects-hard-stop-cleanup-failure.log preserves that failure. Arbitrary hard host
cancellation remains a separate unresolved shutdown path.

VFX NATIVE VISIBILITY RECHECK: the real unchanged Demo dialog handlers pass
GL/safe and Vulkan/separate with actual HWND visibility checks before every
injected click, distinct secondary native identities, inspected viewport captures,
and complete native/presentation/GPU cleanup. Vulkan injected SimpleAlert failure
also passes after the Windows visibility fix. The observer now uses a render-job
fence after stable coordinates instead of waiting an arbitrary 20 pulses. The
previous visible-stage3-timeout and fixed-pulse-wait logs show unchanged target
coordinates but only about four pulses per ten seconds on the complex root page;
this is a real performance limitation, not accepted as fixed by the test change.

Desktop acceptance was retried through the installed Computer Use skill. Its
required node_repl import still fails with `Module not found: @oai/sky`, and that
package is absent from the configured workspace dependency directory. No desktop
input or OS screenshot was produced. This limitation does not block continued
backend implementation, but OS-level visual/input acceptance remains incomplete.

NATIVE VISIBILITY AND PRIMARY LIFETIME: the migrated lifetime probe exposed an
actual Windows visibility bug. Godot's style recomputation cleared WS_VISIBLE
for an already-shown borderless secondary HWND even though Window.visible stayed
true and its viewport rendered normally. The baseline is preserved in
host-lifetime-native-invisible-before-fix.log. _update_window_style now preserves
the HWND's existing WS_VISIBLE bit; ShowWindow remains responsible for showing
or hiding it. JavaFXHost.is_window_visible queries IsWindowVisible on the actual
HWND, including the primary hidden directly through Win32.
The lifetime probe now passes GL/safe, Vulkan/separate and source-built Release
Runtime Vulkan/separate: primary closes/hides, independent survivor stays visible,
mouse then Space actions repaint it, resizable/always-on-top changes preserve
visibility, a new independent Stage does not reuse the primary, and closing the
last Stage terminates the FX thread through implicit exit before test cleanup.
Both surviving viewports are inspected, final windows/presentations drain and GPU
resources reach zero. Popup and nested-menu Vulkan regressions now also assert
actual HWND visibility and pass. Earlier GPU-only captures did not establish OS
visibility; OS screenshots and physical desktop interaction remain outstanding.

SCREEN ENUMERATION: screenInfo now snapshots every Godot display on the main
thread, primary first, including full/usable bounds and DPI. Glass exposes all
records, detects changed snapshots, refreshes Screen objects and re-associates
windows by intersection/nearest-screen distance. ScreensProbe passes GL/safe and
Vulkan/separate, comparing public JavaFX/Glass metadata against JNI and independently
against DisplayServer, checking primary order, explicit settings notification,
an independent child window's screen association, and zero-resource cleanup.
This machine reports one 3120x2080 screen, work area 3120x1984, DPI 192. Therefore
multiple-monitor/hotplug behavior is implemented but not physically verified;
scale factors remain 1 and mixed-DPI scaling is still incomplete. SDK/editor/release
Runtime source builds pass. The earlier single-monitor metadata limitation below
is superseded by this enumeration path, not by a claim of full DPI acceptance.

MONITOR WORK AREA: host metadata now appends Godot's usable screen rectangle and
Glass reports it as Screen.visualBounds instead of repeating the full monitor
size. PopupEdgeProbe now places the Stage at the actual work area's bottom-right,
compares JavaFX visual bounds with DisplayServer (3120x1984 on this machine),
requires ComboBox upward placement and submenu left flipping, and checks custom
Popup autoFix=true containment and autoFix=false preservation outside both edges.
It targets popup-local native input, verifies leaf pixels and final zero-resource
cleanup. GL/safe and Vulkan/separate pass; SDK/editor/release Runtime source builds
pass. These are single-monitor injected-input tests. Multi-monitor enumeration,
dynamic work-area/DPI changes and OS-screen visual verification remain incomplete.
The independent Stage Vulkan/separate regression also passes after the metadata
change, including resize, hide/reshow, fullscreen and maximized restoration.

NATIVE POPUP REGRESSION: ComboBox/ContextMenu and three-level submenu fixtures
now address each popup by its Glass identity and window-local coordinates rather
than injecting all events into the root viewport. Both test-popups.ps1 and
test-nested-menu.ps1 pass GL/safe and Vulkan/separate with independent native
window identity checks, only one root presentation layer, final window draining
and zero GPU resources. Coverage includes selection, outside dismissal, Escape,
menu-key/Shift+F10 invocation, submenu keyboard left/right/reopen/Enter, cross-window
pointer hover and leaf activation. Native popup captures are visually inspected
(ComboBox rows, ContextMenu entries and leaf menu). A bounded capture helper waits
for nontransparent, contrasting content: a shown window with no pending composition
may still be awaiting its first Prism frame. These remain injected-input/viewport
checks; screen-edge/monitor placement, real desktop input and OS screenshots are
not covered. Historical host-bounds/edge fixtures still require migration.

APPLICATION FAILURE SHUTDOWN: GodotBridge now requests FX exit while JNI queues
remain open, joins the render worker, and waits for admitted native/host/render
commands to drain before reporting the original exception. Renderer join and GPU
drain each have a 10-second bound; cleanup failures are attached as suppressed
exceptions rather than replacing the original. A main-thread completed sequence
is published only after presentation/composition finishes. Protocol faults and
explicit host cancellation still use the immediate stop path.
Stage.showAndWait now clears its nested-loop flag in finally, including forced
toolkit exit, preventing a subsequent hide from exiting an already-removed loop.
The baseline failure was reproduced and saved as failure-shutdown-before-drain.log.
Two-level nested probes pass GL and Vulkan separate-thread mode for both main
throwing while showAndWait is active and FX-thread Platform.exit followed by an
Application.launch failure report (the Demo observer pattern). Both also pass the
source-built release Runtime with Vulkan separate threading. They require the
original injected exception, returned loops, drained windows and zero resources,
and reject additional shutdown exceptions/render errors. SDK/engine source
builds and protocol tests pass. GPU device loss, a hung application thread, and
arbitrary host cancellation are not covered by this graceful-failure validation.

The real VFX dialog failure probe also passes Vulkan with a separate render
thread: unchanged VDialog actions select 2 and close their result alert, then
the observer injects INJECTED_VFX_FAILURE inside SimpleAlert.showAndWait.
Native windows, primary presentation and GPU resources drain without additional
shutdown errors. This uses injected input and viewport images, not physical-input
or OS-screenshot acceptance. Readiness now has a separate 60-second deadline;
the action retains 30 seconds after its stable target is published. The captured
baseline (vfx-dialog-readiness-timeout.log) had only 125 ms remaining when the
first target became ready, so its premature exit prevented click processing.
The normal five-click VFX dialog sequence also passes GL/safe after this change,
including both result alerts and final zero-resource cleanup.

PER-WINDOW IME: native properties 16/17/18 now target each Stage's existing HWND.
Glass converts candidate positions relative to that Window, waits on its command
acknowledgements for composition completion, and receives preedit packets tagged
with the source window ID. The host stores composition/enable/candidate state per
native window, routes OS updates to the focused native ID, and clears old preedit
on focus loss. Hidden native windows reapply their requested IME state on show;
ordinary resize does not re-associate the IME context.
NativeImeProbe passes GL and Vulkan separate-thread mode: Chinese/emoji preedit,
UTF-16 caret offsets, replacement, commit, cancel, intra-window focus completion,
candidate coordinates outside the root, unchanged root TextField, disable and
window/GPU cleanup. The root IME regression passes. Composition is injected;
physical IME selection/reconversion and candidate-window visual placement are
still unverified. The test temporarily places/restores the physical pointer while
IME completion pumps OS events, keeping injected clicks consistent with WM_MOUSELEAVE.
The earlier click timeout was a fixture coordinate error, not a viewport-coordinate
bug; the attempted notification-coordinate change was reverted.
Input regression exposed an overly restrictive foreground-process guard in focus
requests. The host now activates only its own UI-thread HWND even if Windows denies
foreground activation. GL/Vulkan native-input regression and Vulkan IME pass again.
SDK/engine source builds and protocol validation pass, including the final
focus-request change.

NATIVE FULLSCREEN: GodotView now requests mode changes through its own GodotWindow,
so secondary Stage fullscreen no longer throws or changes the root HWND. Exit
restores the previous normal/maximized mode. The expanded standard Stage probe
passes GL and Vulkan separate-thread mode across 13 checked states: independent
geometry and content, hide/reshow, repeated fullscreen, programmatic/Escape exit,
maximized-to-fullscreen-to-maximized restoration, final normal bounds and cleanup.
It checks the full-screen viewport size and a far-edge GPU pixel to require a
new full-size Prism frame, while the root retains its size, color and windowed
mode. The default fullscreen hint remains enabled. SDK source build passes.
This does not accept mixed-monitor DPI, physical interaction or performance.

NATIVE MODALITY: Glass enabled/focusable state now reaches each native HWND via
properties 19/20 (also available on the root host queue). Upstream Glass disable
counts remain authoritative for nested modality. Disabled HWNDs are restored after
the final modal closes; hidden native windows retain their requested enabled state
across recreation, and host teardown restores the root. The migrated modal probe
passes GL and Vulkan separate-thread checks using separate native windows, actual
IsWindowEnabled state, nested showAndWait, WINDOW_MODAL/APPLICATION_MODAL isolation,
blocked synthetic clicks, owner focus restoration and GPU/window cleanup.
The real VFX dialog observer now identifies each target Glass peer and injects
window-local events. GL passes the unchanged Demo's number selection/result alert
and SimpleAlert.showAndWait sequence. Vulkan separate-thread mode also passes.
Independent dialog GPU captures were inspected; these are not OS screenshots.
The Vulkan observer initially exhausted a global 60-second limit during its fifth
layout-stability wait. It now uses a bounded 30-second deadline per progressed
phase and a 180-second host deadline, with all interactions/assertions retained.
The timeout failure log (including nested-loop/failure-shutdown errors) is preserved
as vfx-dialog-native-global-deadline.log. Failure teardown and performance acceptance
remain outstanding; successful functional probes do not prove either.

PER-WINDOW INPUT: Godot Window callbacks now append the source Glass ID to one
ordered input queue. Glass routes mouse/key/touch/wheel, enter/exit, focus and close
by that ID rather than hit-testing embedded layers. Root uses ID zero; late events
for closed peers are ignored. Native focus snapshots consider every Stage. On
Windows, foreground activation additionally activates the requested HWND within
the already-foreground application, fixing owner focus requests that otherwise
retained the last active owned window.
test-native-stage-input.ps1 passes GL and Vulkan separate-thread mode: overlapping
Stages, isolated clicks, actual native focus transitions and FX focused properties,
TextField typing, wheel, touch, focus-loss cancellation of a held button, stale
release suppression, close veto followed by accepted close and clean resources.
Input and close requests are injected through Godot, not physical OS interaction.
The primary Stage interaction regression and SDK/engine builds pass.
An earlier focus-timeout run also crashed during Vulkan failure teardown; its log
is retained as native-stage-input-focus-before-fix.log. Successful shutdown passes,
but robustness of that failure teardown path remains unverified and outstanding.
Per-window IME/DPI, modal/native enablement, fullscreen and broader VFX interaction
remain required. This is not final compatibility or visual acceptance.

STANDARD STAGE MIGRATION: the first Stage still maps to the existing root HWND;
subsequent Stages now create independent Godot native windows, including decorated
Stages. Glass awaits creation acknowledgement and uses per-ID geometry, visibility,
properties and snapshots. Prism routes secondary backbuffers through opcode 26.
Native ownership uses -1 for the root Stage. Popup auto-fix now uses the normal
monitor bounds instead of constraining popups inside the primary viewport.
test-native-stage.ps1 passes GL and Vulkan separate-thread mode with standard
Stage/Scene/Label: distinct native IDs, content outside the root, independent move/
resize/repaint, hide/reshow with a new Glass peer, close and resource cleanup.
The child GPU capture was inspected. It is not an OS screenshot. The root Button
only acknowledges pixel checks; secondary input/focus, system close, fullscreen,
IME/DPI and modal semantics still require identity-aware integration. Legacy
embedded-window multi-Stage tests must be migrated, not treated as acceptance.

Native property commands now address title, focus request, mode, resizability,
always-on-top, min/max size and border style by stable window ID. The JNI probe
checks Unicode title changes, independent property mutation/reset, minimize/restore,
unsupported/out-of-range rejection and requests after owner destruction. The
untouched window retains its initial device-dependent maximum-size default;
explicitly removing a size limit records zero. Focus command admission/application
is exercised, but physical foreground activation is not yet asserted.
SDK/engine source builds and protocol checks pass. Standard Glass wiring
remains pending; these native property operations are a prerequisite.

Native GPU publication now routes opcode 26 by window ID to each independent
window's own surface, without creating a layer in the original host. SDK/editor/
runtime source builds and protocol tests pass. The JNI GPU probe passes GL and
Vulkan separate-thread checks for distinct red/blue output, independent repaint,
hidden-window publication, retained output after showing, late publication after
close, and removal/resource cleanup. GPU captures were inspected, not OS screenshots.
Standard Glass Stage/Presentable still uses the previous path; this infrastructure
does not yet satisfy native Stage acceptance.

The legacy window-command probe exhausted its 30-second deadline in fixed tick
delays. It now advances only after Godot acknowledges each pixel check, including
final cleanup; GL and Vulkan separate-thread pass with all original pixel assertions.

JNI native-window transport is implemented: bounded FIFO admission, projected
owner/identity validation, main-thread create/configure/destroy and copied snapshots
with acknowledgement sequences. IDs increase monotonically without retaining an
unbounded set of historical identities. SDK/engine source builds and native
protocol tests pass. The Java JNI probe passes two distinct native windows, Chinese
titles, independent bounds/visibility, 12 hide/show cycles, bad-request rejection
and recursive owner destruction in GL and Vulkan separate-thread mode.
The initial Vulkan run exposed swap-chain deletion overlapping a render-thread
draw; host native-window mutations now synchronize the rendering queue first.
Its failure log is retained. Ordinary Glass Stage input/presentation is still on
the previous path and must be migrated next; this is not Stage acceptance.

Native host registry now maps stable window IDs to independent JavaFXNativeWindow
instances, including explicit owner IDs, geometry/visibility configuration and
per-window identity/geometry/focus/mode snapshots. Duplicate IDs, missing owners and
invalid dimensions are rejected. Destroying an owner removes descendants first;
host tree exit cleans any remaining windows. GL and Vulkan separate-thread native
tests pass registry validation, independent GPU rendering, owner teardown, retained
target destruction and window-count restoration. JNI command queuing and Glass
Stage routing are still pending; these APIs are main-thread native operations only.

Independent-native-window foundation added as JavaFXNativeWindow (Godot Window
subclass with force_native and an independent GPU presentation surface). engine
and Runtime source builds pass; GL/Vulkan separate-thread native probes pass distinct window IDs,
placement outside the original host, separate red/blue contents, target replacement,
independent resize/hide/show and window/GPU cleanup. Per-window GPU captures were
inspected; they are not OS screenshots. The initial force_native initialization
order was corrected to hide before enabling native mode. Ordinary JavaFX Stage is
NOT connected yet: identity-aware host commands, presentation/input/snapshot routing
and removal of the embedded-only Glass assumptions are the next integration work.

USER REQUIREMENT CORRECTION (2026-11-02): JavaFX Stage must be an independent
native window, not embedded in another Stage. This supersedes the original
single-HWND constraint. Godot must own multiple native windows while remaining the
sole event/rendering host. Existing embedded Stage, popup-bound and one-HWND checks
are historical coverage and do not satisfy this corrected requirement. Native
window migration is pending; see architecture.md. Do not extend the embedded
Stage model as the final implementation.

Immediately before this correction, an actual VFX component-page dialog probe
exposed stale mouse capture during non-modal showAndWait entered from a release
callback. Application routing now commits mouse/touch release ownership before
callbacks. The SDK builds and the GL VFX VDialog -> Optional[2] result alert ->
SimpleAlert sequence passes using original Demo handlers. Vulkan validation of
this probe was not run before the architecture correction. This input fix remains
relevant, but embedded dialog captures are not independent-window acceptance.

Already-open autoFix popups now receive host work-area change notifications.
Godot detects geometry changes on the FX event thread; PopupWindow registers only
while shown with autoFix enabled and unregisters on hide/disable. SDK builds and
GL/Vulkan separate-thread probes pass eight states covering shrink, move, grow,
autoFix disable/re-enable, hide/move/resize, reshow and owner closure. Screen bounds,
GPU pixels, layer counts and teardown are checked; the capture was inspected.
Edge-popup regression passes. This validates a plain Popup with standard Stage API
geometry changes; physical dragging, nested menus during movement, RTL/oversized
content and mixed-DPI transitions remain unverified.

Popup placement now obtains a backend work area without changing monitor Screen
data: Godot supplies the native host bounds, and existing autoFix/side-flipping
algorithms use them. Source SDK builds. GL/Vulkan separate-thread edge probes pass
bottom-right ComboBox selection, left-flipped submenu action, and explicit Popup
autoFix true/false behavior. Actual control content bounds, one HWND and cleanup
are checked; the GPU capture was inspected. Basic and nested popup regressions
pass. Open-popup host resize/move, oversized content, RTL and mixed DPI remain
unverified; this supersedes the monitor-only placement limitation in older notes.

Three-level standard ContextMenu validation now passes OpenGL and Vulkan
separate-thread mode. Direction keys enter, return and reopen nested Menu levels;
Enter and pointer hover/click each activate the leaf exactly once. Outside click
closes the full hierarchy without activation. Logical-layer counts, one HWND and
resource cleanup are checked; the GPU capture was inspected. No new runtime fix
was needed. This does not resolve host-edge placement: PopupWindow still computes
autoFix against monitor bounds, which can exceed the single host viewport.

Independent Stages now survive primary Stage closure: native visibility follows all
visible logical windows and input no longer requires a live primary. New windows
remain secondary while other layers survive. Source SDK/editor builds and GL plus
Vulkan separate-thread host-lifetime probes pass mouse/Space interaction, new Stage
creation, fixed host dimensions, one HWND and final layer/resource cleanup. Runtime
source build and the Vulkan separate-thread packaged runtime probe also pass;
primary hide/show and secondary input lifecycle regressions pass. The
capture was inspected. The test also exposed queued cleanup discarded at normal
JVM return; FrameQueue.finish now preserves accepted commands while closing admission.
Protocol and encoded host-stop regression pass; explicit stop still cancels pending
work. Decorated reopen, native close-request veto/modal cases and broader host
movement/DPI/lifetime stress remain incomplete.

Hide/close-held-input coverage now passes OpenGL and Vulkan separate-thread mode.
test-input-lifecycle.ps1 runs six cases: mouse/touch/Space held while a secondary
Stage hides or closes, followed by late release and reopening the same Scene.
Each Button disarms without activation or drag, fresh input produces one action,
and teardown releases GPU resources with one native window throughout. These are
injected events; native focus loss, other drag controls and primary-host lifetime
still need validation/implementation. No runtime change was needed for these cases.

Held-input cancellation now tracks key owners, mouse capture and touch targets.
Disabling/hiding a logical window or losing native focus releases tracked input;
focus changes release its keys. Canceled physical releases/repeats are suppressed,
while a fresh non-echo press remains valid if the old key-up was lost. Cancellation
does not synthesize a drag. The source SDK builds, and test-input-cancel.ps1 passes
OpenGL and Vulkan separate-thread mode: modal opening while a Button holds mouse,
touch or Space disarms it without activation, and subsequent input works. Popup,
modal and Vulkan separate-thread GodotView regressions pass. These injected modal
tests do not accept physical focus loss, hide/close while held, or every drag control.

Actual nested WINDOW_MODAL and APPLICATION_MODAL Stage probes pass OpenGL and
Vulkan separate-thread mode: blocked owner/outer actions stay blocked, independent
windows remain usable only under window modality, showAndWait returns, and owner
focus/input restore after close. Logical level sorting and secondary toBack are now
implemented with owner-before-child constraints. Ten-state GPU tests pass in both
configurations for topmost/front/back and child ordering, with one native window and
resource cleanup. Modal and order captures were inspected; SDK and popup regression
pass. Full focus/capture cancellation, decorated windows, popup edge/nesting cases
and primary-host lifetime cases remain incomplete.

Standard ComboBox/ContextMenu probes now pass OpenGL and Vulkan separate-thread
mode: pointer selection, outside-click/Escape dismissal, and menu action dispatch
after opening by right click, menu key or Shift+F10. The missing Glass menu-event
notification was implemented; popup focus grabs now have logical ownership and
reentrant-safe ungrab notification. Both popup captures were inspected. Source SDK,
secondary Stage and IME regressions pass. Nested menus/grabs, edge placement,
physical native focus loss and complete modality/capture behavior remain unverified.

Secondary untitled/transparent Glass windows now use retained layers in the sole
native host. An actual owned Stage probe passes OpenGL and Vulkan separate-thread
mode: child mouse and keyboard Button activation, main-button focus return,
screen-to-host positioning, move/opacity, hide/show and owner closure. The capture
was inspected. Decorated secondary windows, min/max/fullscreen and lowering still
reject; popup grab/auto-hide, level grouping, modality and capture cancellation
remain incomplete. The earlier entries below describe incremental work and do not
supersede this current support boundary.

The new cleanup workload exposed a JVM-return race: the native bridge stopped
command admission while the daemon Quantum renderer still had disposal jobs.
Godot pipeline registration now records the renderer thread; successful bridge
launch waits for its completion before returning to native shutdown. Source SDK,
IME and Vulkan separate-thread GodotView regressions pass after this fix. The
earlier failing IME shutdown log is retained as ime-gl-shutdown-before-render-drain.log.

Logical-window composition snapshots now carry host-local position, z and opacity,
and distinguish the primary host from secondary layers. Secondary Presentable
allocation no longer resizes the host surface. A two-Presentable probe passes GL
and Vulkan separate-thread mode across six alpha/move/stack/hide/show/close states,
preserving the 240x160 host with an 80x60 secondary target and releasing all layers
on close. The overlap capture was inspected and the source SDK builds. The second
Presentable uses a synthetic state: actual secondary Glass windows and their
screen-coordinate conversion/input/modal behavior remain to implement.

Glass visibility/closure now shares an immutable lifecycle snapshot with Prism.
Queued Presentables retain the closed token; render jobs apply latest visibility,
and stale hidden/closed publication uses zero opacity before closed-layer removal.
Primary Stage hide/change-content/show tests pass OpenGL and Vulkan separate-thread
mode (16 stable states, 320/341 frame checks, peak 14 resources, zero layers after
close). The closed-token registry and irreversibility checks pass. Source SDK,
resize and Stage drawing/effect/input regressions pass. Popup coordinates, focus/capture, modality and owner closure
remain incomplete; additional logical windows are still rejected.

WINDOW_CONFIGURE now transports independent logical-window geometry, z, opacity
and visibility through the render queue. OpenGL and Vulkan separate-thread probes
pass eight pixel-checked states including hide/restore, move/resize, ordering and
opacity without republishing GPU content. Hidden targets retain their budget
charge; protocol tests reject removed IDs and updates during open drawing passes.
SDK/engine source builds pass. This is a tested transport capability;
Primary Glass lifecycle synchronization is now connected as described above;
additional JavaFX windows are still explicitly rejected pending input/modal work.

Standard Prism Presentable now publishes the primary Glass window ID through
WINDOW_PRESENT. GodotContext retains its old GPU buffer across resize replacement,
then disposes it only after new publication; normal disposal and Glass close remove
the layer first. The source SDK builds. OpenGL and Vulkan separate-thread resize
tests pass 40 changes/six sizes, checking 454/717 frames without a missing red
content pixel or missing layer, peak 19 owned resources, and zero layers on close.
Stage drawing/effect/input and Vulkan separate-thread GodotView regressions pass.
The Stage interaction capture was inspected. Additional Glass windows still reject:
popup visibility, coordinates, focus/capture and modal routing remain to implement.
The OpenGL VFX Intro 35-page navigation run also passes on this publication path,
with a fresh 35-page passed manifest and regenerated D3D/Godot comparison sheet.
The sheet was inspected; this checks navigation/rendering, not every demo button,
dialog, physical input or OS-level screenshot acceptance.

Retained window publication now crosses the production Java encoder/native queue:
WINDOW_PRESENT / WINDOW_REMOVE carry window identity and composition metadata.
JavaFXHost consumes them and retains each GPU target independently. Ledger tests
reject disposal of published/shared targets until the last layer is removed,
keeping output within the texture budget. OpenGL, Vulkan and Vulkan separate-thread
integration probes pass independent lower-layer updates, alpha overlap, upper-layer
removal and final GPU cleanup. The OpenGL capture was inspected; SDK/engine
source builds pass. Glass popup lifecycle/input remains unwired, so additional
JavaFX windows remain unsupported.
The existing Stage drawing/effect/mouse/keyboard regression also passes. Its
fixed five-frame wait after a Glass title update was replaced with a bounded
final-pixel wait because host metadata can arrive before queued Prism GPU work;
the same pixel and resource-growth assertions still apply.

Native logical-window GPU composition is now implemented as JavaFXWindowSurface.
GL, Vulkan and Vulkan separate-thread tests pass 100 cycles covering opacity,
stacking, hide/move/clip, in-flight source retention and destruction after close,
with one native window. engine builds and the render-target regression
pass. Glass input/modal routing for additional windows is not connected yet;
additional JavaFX windows still reject explicitly. This is the compositor
foundation for real VFX dialogs, not popup acceptance. See logical-windows.md.

IME enable/preedit/commit/cancel and focus completion now have a working Glass
path through Godot's Windows IME context. The injected-event TextField probe
passes GL/Vulkan, including Chinese, supplementary Unicode caret conversion,
composition replacement, typed commit, cancellation via the DisplayServer query,
and focus change while preedit is active. A bounded completion handshake delivers
Windows character results before JavaFX moves focus. The source SDK/editor build
and GodotView/VFX Intro smoke regressions pass; the release runtime is rebuilt.
This resolves the earlier focus-time unsupported
exception, but physical IME candidate/conversion/DPI acceptance is still pending.
No system clipboard writes were performed for this verification. See ime-godot.md.

Unicode text clipboard support has been implemented through Win32 using the
existing host HWND; unsupported formats fail explicitly before mutation. The
source SDK/editor build passes. The clipboard probe's selected TextField copy/
paste, cross-API native transfer, empty/clear and rejected-write checks passed,
but that run's overall result was FAILED due to the then-unimplemented IME
entry point. The IME-specific exception is now fixed as described above, but the
clipboard test has not been rerun to acceptance. The runner backs up clipboard formats
in memory and restores them via OLE. A later run encountered clipboard contention
and a QQ rich-format restoration mismatch. The runner now refuses non-text
clipboard formats before writes; further integration verification is pending.
See glass-godot.md and clipboard.log.

VFX page coverage is being expanded beyond the initial smoke test. All 35 pages
now navigate and close successfully on GL with a render-job acknowledgement
before capture. A Windows D3D reference set from the same SDK and a paired
contact sheet were produced and inspected. LCD-heavy tables exposed the cost
of waiting one host display frame per offscreen target transition. The host now
drains offscreen draws without window swaps on its default main-thread renderer,
bounded to 16 batches / 4 ms checked after each batch. engine builds and
GL/Vulkan effects, render-target and GodotView regressions pass. All 35 pages also
pass navigation/capture/close on Vulkan; both paired contact sheets were inspected.
The separate rendering-thread failure is now fixed: deferred post-draw signals
could release a newly queued pass early. An ordered draw plus render-queue sync
protects resources before release. Effects and mixed GodotView tests now pass on
GL/Vulkan with `-RenderThread separate`; the default GodotView regression passes.
A separate upstream shutdown bug was reproduced in an empty scene without JVM:
the main RenderingDevice retained the departed worker's thread ID. Returning its
ownership to main after joining that worker fixes finalization. Empty-scene safe
and separate shutdown tests pass in engine and release runtime without leak
warnings. Full VFX interaction/stress acceptance is still pending.
OS screenshot capture is still pending: the computer-use skill's
required @oai/sky package could not be imported in the current node runtime.

The unchanged VFX library and all test/Intro sources now build against the local
OpenJFX SDK using scripts/build-vfx.ps1. The real IntroMain starts, renders its
welcome page, responds to its Next button, and closes normally on GL and Vulkan.
The smoke test requires a changed central content image and exactly one native
window. Welcome-page host resources are 95. GPU captures of the welcome and
VStage introduction pages have been inspected; these are not OS screenshots.
Remaining Demo pages, physical input, native dialogs/media and sustained resource
stress are not accepted. See vfx-demo.md for reproducible commands and limits.

GodotView input forwarding now passes GL/Vulkan mixed-Stage checks. Command 22
validates live scene handles and bounded input payloads; render jobs resolve the
current texture after resize and native input is delivered on the host thread.
The probe verifies mouse coordinates, wheel factor, Space key/Unicode, JavaFX
touch press/move/release coordinates, sibling event isolation and focus loss
releasing a held key plus canceling a held touch. GUI focus clears before cancel
events to avoid accidental activation. Protocol malformed-input/kind/stale-handle
tests pass. SDK/engine builds pass; resource peak remains 30 with cleanup.
Touch now enters through Godot Input.parse_input_event and the native Glass
queue. Primary-touch mouse promotion activates ordinary Button controls while
GodotView ignores promoted mouse events. Both renderers verify exactly one mouse
and one touch Button action. IME and broader input stress remain pending. M5/full VFX acceptance
is still open; this result does not imply physical input or final screenshots.

Public GodotView composition now passes GL/Vulkan. The Region/helper/NGRegion
peer uses a pinned live scene texture, normal Prism drawing and a showing-window
AnimationTimer for redraw; peer release queues disposal on the render thread.
test-godot-view.ps1 verifies two embedded scenes mixed with Label/Button, native
scene changes visible without JavaFX property changes, parent clip/opacity,
button-driven layout resize preserving scene identity/state, old-pixel clearing,
one window and scene cleanup after close/removal. Both backends observe resource
peak 30 and zero host resources at teardown. The GL image was inspected. The
source SDK build passes. See godot-view.md. JavaFX-to-Godot input/focus routing
remains pending, so M5 and the full objective are not accepted.

Scene resize transport now passes GL/Vulkan tests. Command 21 consumes the old
scene handle and transfers the same SubViewport owner to a new texture wrapper
with new physical dimensions. A GPU pass boundary precedes resize, and admission
rejects resizing a still-referenced scene. Protocol tests cover that rejection,
completion ordering, decode and stale-handle invalidation. The runtime probe
changes scene color before resizing and checks stable root ObjectID, retained
color/ticks, new pixels, alias invalidation and updated pool charge. SDK, engine
and runtime builds pass. The public javafx.scene.layout.GodotView / NGGodotView
composition result is recorded above; JavaFX input/focus forwarding remains pending.

Scene texture transport: command 20 now loads res:// PackedScenes on the host
thread and exposes their SubViewport textures in the common generation-tagged
texture namespace. GodotSceneTexture and the factory/pool encode real allocations,
preserve same-mode shared locks, reject CPU uploads and release accounting.
Native retained scene owners outlive Java disposal while submitted draws reference
them, then release scene nodes at clear/pass cleanup. Load failures stop the queue
and remain FAILED even as the probe worker exits. Protocol tests pass for malformed
paths, kind restrictions and rollback. Source SDK/engine builds pass.
test-scene-textures.ps1 passes GL/Vulkan for two differently sized live scenes,
alpha pixels, disposal-before-render retention and node cleanup; the Vulkan GPU
capture was inspected. The missing-scene failure test passes. This is transport
integration, not the finished GodotView control: state-preserving resize, JavaFX
layout/peer, pulse redraw and input/focus routing still need implementation.

GodotView native foundation: JavaFXSceneView now owns a real SubViewport and
PackedScene in an isolated World2D, exposes its borrowed texture, resizes without
reloading, and forwards local mouse/touch/key InputEvents. Scene subwindows are
embedded to preserve one native host window. Surface draw commands retain the
scene owner until cleared; checked ObjectIDs tolerate parent-first destruction.
engine builds pass. test-scene-views.ps1 passes GL/Vulkan for 100 real
scene cycles, processing, resized markers, transparent texture composition,
input-driven redraw, retained lifetime, embedded-window count and parent-first
teardown. Pixel results match across backends; GL capture was inspected. This
does not yet connect a JavaFX GodotView control: Prism scene handles, layout,
redraw pulses and JavaFX input/focus routing are the next integration steps.

Per-node GodotShaderEffect is now a public additive javafx.scene.effect API.
It uses a UserSpace FilterEffect and a pooled GPU pass per selected node/subtree,
with immutable numeric uniform snapshots, standard input chaining and normalized
input UV adaptation. CanvasItem fragment-entry COLOR includes the input texture;
float/int scalar/vector declarations may have default values. The source SDK
build passes. test-node-shaders.ps1 passes GL/Vulkan for independent shader
instances, 80 live parameter changes, GaussianBlur input, scaled parent clipping,
opacity, unaffected sibling, UV gradient, a tinted Chinese Button and an injected
click that changes another subtree from red to blue. Observed native peak is 53,
with zero resources after teardown. The GL image was inspected. The 212-loader
ShaderStateProbe regression also passes. See node-shaders.md for API, mapping,
commands and explicit limitations (additional samplers/blend modes, fixed bounds,
and no Java-visible GPU compile acknowledgement). This is not final M4/VFX
acceptance. GodotView and the full remaining objective are still pending.

Float textures / DisplacementMap: protocol commands 18/19 now allocate/patch
RGBAF textures, preserving signed finite float32 channels. Java/native budgets
count 16 bytes per pixel and reject format mismatches/non-finite input. Protocol
tests pass including budget enforcement and rollback. Source SDK, module engine
and module runtime builds pass. PrismTextureProbe passes GL/Vulkan with padded
float uploads, immutable source position, no partial NaN upload, filter mutation
flush and disposal accounting. EffectsProbe now has 14 tiles including signed
DisplacementMap with clamp/wrap: both GL/Vulkan pass D3D comparisons (mean errors
0.00002990 / 0.00002059, zero pixels above .08). The expanded Vulkan capture was
inspected. This uses GPU float sampling rather than the software displacement
fallback. Native resource count reaches zero after effect host teardown.
Remaining work includes public per-Node Godot shader integration, GodotView,
broader Glass support, VFX build/run/visual acceptance, media/WebKit builds,
readback and broader effect parameter/transform stress.

The standard EffectsProbe compares the same scene on the source SDK D3D and
Godot backends. Before adding DisplacementMap, test-effects.ps1 passes on both
GL/Vulkan for None, GaussianBlur, BoxBlur, DropShadow, InnerShadow, Glow, Bloom,
ColorAdjust, Reflection, MotionBlur, Lighting (Distant) and Blend (Multiply).
Every tile is pixel-identical except MotionBlur (mean maximum-channel error
0.00006422, zero pixels above 0.08). D3D and Vulkan captures were inspected.
These are particular parameter combinations; broad effect acceptance remains
open. The probe is being extended for float-texture displacement maps.

Effect sampling extension: PPSRenderer explicitly selects GodotShaderSource on
GODOTPipeline and loads the generated Decora CanvasItem shaders. GaussianBlur(4)
and DropShadow(6,4,4) now run in StageProbe through GPU offscreen passes on both
GL and Vulkan. The initial blur incorrectly extended opaque edge texels;
GodotSampler now implements level-zero transparent-border/repeat/edge sampling
and nearest/bilinear filtering with texelFetch. Filtering changes flush pending
vertices before mutation. Both backends report blur edge (1,.8745,.8745,1), blue
shadow body and shadow edge (.4471,.4471,.4471,1), while passing dynamic redraw,
Chinese text and two injected button actions. Observed resource peak/final is 44
with these effects; teardown reaches zero. The GL GPU capture was inspected.
This is limited GaussianBlur/DropShadow evidence, not full Effect acceptance.
DisplacementMap GPU support, general composite modes, readback and other effect
types still need implementation/verification. SDK rebuild succeeds.

Latest controls extension: StageProbe now includes standard Label/Button with
Chinese/English labels. LCD rendering now passes through real RTTexture target
switches; text/effects were not disabled to bypass the initial failure. Native
JavaFXRenderTarget now owns an offscreen Viewport/canvas and supports GPU-only
rectangle passes and target-to-target copies. test-render-targets.ps1 passes
on GL/Vulkan for 100 allocation/copy/release cycles, premultiplied-alpha pixels,
and source lifetime retained through a two-target reference chain. Instance IDs
are checked after command clear to avoid a test weak-reference read retaining
the object itself. Vulkan GPU capture was inspected. Stage controls render on
GL/Vulkan; native input injection clicks Button then presses Space, verifies two
FX-thread Actions and separately waits for each updated Label image. The final
Vulkan image visibly reads "Action 2 中文". Dynamic controls resource observations
are 28 peak/final, not the earlier rectangle-only baseline of 9. Presentable now
owns a sampleable offscreen backbuffer and composes it only after completed passes.
Complex effects/readback and full VFX compatibility remain incomplete.

GodotRTTexture allocation is now connected through command 15 and the same
generational texture pool/ledger. The factory returns RTTexture objects with
shared-resource locks and deferred disposal. Native RT CPU uploads are rejected;
borrowed viewport texture RIDs are never freed as ordinary image textures.
PrismContextProbe passes on GL/Vulkan for RT allocation, shared alias type/locks,
CPU-upload rejection, transparent sampling after Java disposal, and native clear
returning to eight base resources. Native offscreen targets additionally draw
Prism meshes with shader parameters/scissor via the shared prism_mesh.h converter.
The 100-cycle offscreen test passes on both backends with shader color/clip,
GPU copy/alpha and full reference release. SDK/engine builds pass;
Vulkan mesh/shader regressions pass. Commands 16/17 select targets/end passes;
consumption pauses at pass completion before targets are sampled or rewritten.
Protocol tests reject feedback, image textures as targets, and switches that
skip unfinished geometry. Texture handles are captured while Prism holds their
locks, preserving deferred batch flush after cached textures are unlocked.

First standard Stage/Scene now renders through Quantum -> GODOTPipeline ->
GodotPresentable -> GodotGraphics -> native command queue. test-stage.ps1 passes
on GL and Vulkan with two Scene Graph Rectangles, verifies one native window,
checks expected GPU colors and zero native resources after host removal. Vulkan
capture godot-stage-mobile.png was inspected. The source SDK rebuild passes.
Glass null-icon requests preserve the Godot host default; custom icons remain
explicitly unsupported. The test now performs 120 FX-thread rectangle moves.
It initially exposed 638 retained resources after 79 batches. BEGIN_PRESENT /
PRESENT boundaries now preserve framebuffer pixels, draw a Viewport once per
completed frame and free transient commands on frame_post_draw. Both GL and
Vulkan pass with observed peak/final counts of 9, preserved stationary geometry,
correctly cleared old positions and zero resources after removal. Host consumption
pauses at PRESENT until post-draw cleanup; split batches remain unrendered until
commit. Texture reference budgets reset at the projected completion boundary.
Protocol boundary/rollback tests and window/PrismTexture regressions pass.
Present success still means queue admission, not a Java-visible GPU fence.
Full controls, effects/offscreen targets, resize/DPI and complex multi-batch
visual stress remain unverified. This is not controls/VFX acceptance.

GodotContext now extends BaseShaderContext and submits real Prism VertexBuffer
batches through the bridge. GodotResourceFactory creates production textures
and generated stock shaders; GodotGraphics extends BaseShaderGraphics rather
than rebuilding geometry. test-bridge.ps1 -PrismContext passes on GL/Vulkan:
Graphics.fillRect, two paints, translation and scaling render expected pixels.
The fixture uses a test RenderTarget, not a Stage or Presentable. Device-space
scissor now uses command 12 and immutable native CanvasItem clip state. GL and
Vulkan verify clipped blue geometry, empty-clip suppression and red geometry
after clip removal; the Vulkan GPU image was inspected. Protocol tests cover
negative origins, empty bounds and malformed flags/sizes. Unsupported
ADD/DST_OUT/general CLEAR composite modes, offscreen targets/blit, perspective/depth and 3D
throw explicitly. Pipeline/presentable hardening and full scene/control integration
remain incomplete. One factory/pool owns the host texture namespace through the
pipeline device singleton. No full M2/M3 acceptance is claimed.

SRC replacement, clipped clear(Color), and transformed/clipped clearQuad are now
implemented through blend_disabled GPU geometry. The context probe passes on
GL and Vulkan with half-alpha SRC over opaque blue, half-alpha blue clear over
red, and a scaled/translated transparent clearQuad. GPU pixels distinguish
replacement from SRC_OVER and confirm untouched regions remain intact. The
Vulkan image was inspected; the source SDK rebuild passes. Godot blend_add uses
SRC_ALPHA and therefore is not substituted for Prism's premultiplied ADD.

Latest checkpoint: source SDK rebuild succeeds with GodotShader, the Prism
Shader descriptor implementation. test-shader-state.ps1 passes all 212 real
generated Prism loaders plus immutable snapshot, typed/partial array, invalid
input, thread ownership and disposal checks (m2-shader-state.log). Native
shader state transport and sampler binding are the next integration steps.
The native surface now freezes recorded material/code/parameter revisions in
ordered CanvasItem segments. Both GL and Vulkan pass the generated-shader
fixture, including 100 cycles of overlapping red/green/blue draws with distinct
uniform/code revisions and bounded resource counts (8 after clear, 14 with
three segments, 0 after removal). The Vulkan GPU capture was visually checked.
M1 and production PrismTexture bridge regression tests also pass on Vulkan.
Java descriptors now travel through JNI as opcode 11 with owned source and
typed constants. Source SDK/editor builds and native protocol tests pass.
test-bridge.ps1 -ShaderStates passes on GL and Vulkan: two snapshots use a
vec4 array and integer index to draw purple/green after Java mutation/disposal.
Sampler transport now resolves named texture units into versioned handles and
retains the bound GPU revision. The shader probe binds a white texture, draws,
updates it to green, binds/draws again, and disposes it before consumption;
both GL and Vulkan preserve purple/green output. Resource counts are 15 before
clear, 8 after clear, 0 after tree removal. SDK/engine rebuilds pass.
Protocol tests cover unallocated sampler rejection and retained-version budget.
Clear removes current uniform/sampler bindings, requiring state rebind. Shader
transport currently accepts ASCII source only. These probes do not establish
JavaFX control-rendering acceptance. Context/factory/pipeline integration remains
the next major step; sampler filtering/wrapping still needs explicit mapping.

Completed preparation:
- Inspected repository versions, Glass/Prism/Quantum entry points, Godot
  RenderingServer and custom module conventions, and VFX intro source.
- Recorded architecture and ordered acceptance gates in architecture.md.
- Installed SCons 4.10.1 in the workspace venv and the upstream AccessKit,
  Mesa NIR, PIX and Agility dependencies under .tools/localappdata.
- Added build-windows.ps1; PowerShell parsing and git diff --check pass.

M0 evidence:
- Godot stock editor build passed, exit 0, in 15m26s; log
  artifacts/logs/godot-editor.log. `--headless --version` returns
  4.8.beta.custom_build.7be59b463. MSVC 14.3 selector (VS 2022), SDK
  10.0.26100.0, eight jobs. Initial dependency failure was resolved.
- OpenJFX default SDK passed, exit 0, in 9m12s; log
  artifacts/logs/jfx-baseline.log and explicit .exitcode file.
  JDK 25.0.3, Gradle 9.7.0; native graphics DLLs and modular JARs exist.
- Baseline hashes saved in artifacts/logs/m0-baseline-hashes.json before
  custom-module rebuilding.
- ReferenceSmoke runs the source-built JavaFX D3D pipeline. Its snapshot
  artifacts/reference/stock-d3d.png was visually inspected: Chinese/English,
  button, text field, gradient, DropShadow, opacity and rotated clip appear.
  Capture run returned 0 and shut down normally. It is a JavaFX scene
  snapshot, NOT an OS screenshot/input test and NOT a Godot result.
- Computer-use failed to import @oai/sky, including after adding the bundled
  node_modules path. No desktop interaction verification was possible.
- The manually opened baseline exec session 56110 was stopped after the
  automatic snapshot run. Its nonzero interruption status is not a test pass.

M1 validated:
- native/godot_modules/javafx provides JavaFXRenderSurface, an explicitly
  limited main-thread RID owner for viewport/CanvasItem/texture/shader.
- tests/godot passed on OpenGL Compatibility and Vulkan Mobile: rendered
  pixel values, resize, resource ownership and 100 create/remove/free cycles.
  Captures godot-m1-gl_compatibility.png and godot-m1-mobile.png were inspected.
  Actual RGB samples match (51,102,204) and (0,204,0). Logs have no errors.

M2 foundation implemented and tested:
- The JNI bridge transports batches consumed on the Godot main thread.
- frame_protocol.h: little-endian validated batches, 4 MiB/65,536-command
  limits, bounded three-frame FIFO, monotonic sequences and coalesced ticks.
- Native tests passed malformed/truncated inputs, atomic rejection,
  backpressure/retry, stop, and 10,000 concurrent FIFO frames.
- test-bridge.ps1 passed normal probe completion and -StopFromHost. Java
  memory was overwritten after submission; the native-owned commands still
  rendered the expected pixel. godot-bridge.png was visually inspected.
- Standard application launch forces glass.platform=Godot/prism.order=godot;
  until these backends exist it fails explicitly instead of opening a second
  native window or using a fallback pipeline.
- All latest editor/JFX builds and both JNI bridge tests returned success.

Glass-Godot scheduler implemented and verified:
- GodotPlatformFactory selects GodotApplication. GodotEventLoop provides the
  separate Glass event thread, FIFO dispatch, synchronous exception
  propagation, nested loops, and rejection/wakeup of pending calls at stop.
- GodotPulseScheduler coalesces native ticks and GodotTimer supports periodic
  and per-frame callbacks, pause/resume/stop without an independent clock.
- Native hostInfo returns initial Godot viewport dimensions and monitor DPI.
- Latest engine and OpenJFX builds passed. test-glass-scheduler.ps1 passed
  including non-innermost nested-loop exit, both timer modes and cancellation
  of a caller verified WAITING on a queued synchronous task.
- The host-stop JNI regression test also passed after these changes.
- Clipboard/Robot routes explicitly remain unsupported;
  GodotApplication reuses HeadlessApplication's platform-neutral key/pixel
  helpers but overrides presentation and never allocates its framebuffer.

Primary Glass Window/View and stock cursor routing now pass the actual JVM
integration probe. Commands run on the Godot main thread with bounded queues
and applied-sequence acknowledgements. Tests verify one host window, Unicode
title, bounds, resize flag, cursor, View notifications and GPU background.
artifacts/reference/godot-glass-window.png is an inspected GPU readback, not
an OS screenshot. Window probe, scheduler and host-stop regression all pass.
The probe exposed a Godot Windows event-pump bug: mutable RBMap indexing for
an invalid focused-window ID inserted a phantom window. A minimal core patch
uses find() and keeps the window registry unchanged when focus is absent.

Host input routing now passes on both the tested configurations:
- Godot Node::input captures mouse/key records into a bounded 4096-event FIFO.
- Glass drains records on its event thread before pulse timer callbacks.
- Input.parse_input_event integration checks move/down/drag/up order,
  modifier bits, window-relative/absolute coordinates, fractional wheel,
  repeated key press/typed events, navigation keys and non-BMP Unicode text.
- Ordinary mouse dragging required Glass dragboard allocation; allocation is
  supported, while actual transfer flush remains explicitly unsupported.
- Scheduler and host-stop regressions pass with the new native method.
These are injected engine input tests, not physical-device or IME tests.
No builds remain running. Logs: m2-glass-window.log,
m2-glass-window-runtime.log, m2-glass-scheduler.log, m2-bridge-host-stop.log.

Window boundary/close routing now passes on the tested configurations.
The probe sends mouse exit/enter and close notifications through the Godot
Window notification path. Glass receives them on its event thread, vetoes
the first close request, accepts the second, and the host restores the
previous SceneTree auto-accept-quit setting when removed. This also verifies
that a close request does not prematurely destroy its Glass Window. Both
scheduler and host-stop regressions pass after the lifecycle changes.

Prism vertex transport foundation is implemented and verified:
- Protocol opcode 4 carries seven float attributes plus four color bytes per
  vertex, with bounded quad counts, finite-value checks and atomic rejection.
- JNI applies batches as real ArrayMesh draws on Godot's main thread. UV1 is
  retained in CUSTOM0; the ordering matches the upstream VertexBuffer source.
- OpenGL and Vulkan pixel tests independently verify UV0, UV1, vertex color,
  and premultiplied alpha through offscreen drawing and presentation.
- The 100-cycle ownership test includes mesh allocation/disposal; clear and
  exit release mesh resources. JNI rendering and host-stop tests pass with a
  real Java-submitted mesh, and the Glass window regression passes.
- Baseline surface resources now include premultiplied draw/presentation
  shader/material pairs. GPU readbacks godot-prism-vertices-*.png were inspected.

GodotRenderCommands now provides the production Java render encoder. It
owns a reusable/growing direct buffer, validates commands before mutation,
enforces thread ownership and serializes sequence admission across contexts.
Full-queue retries wait on host ticks with bounded timeout and shutdown
handling; accepted sequence is explicitly not a GPU completion fence.
The encoded JNI integration passes 32 batches of 1024 vertices, buffer growth,
caller/buffer overwrite, invalid-command atomicity and submission after stop.
The fixture pauses host consumption until the native FULL counter increments,
then resumes and verifies the final GPU pixels. Both encoded variants pass;
raw JNI, Glass window and scheduler regressions also pass. Logs:
m2-bridge-encoded.log and m2-bridge-host-stop-encoded.log.

Transactional texture resources now work end to end through the Java encoder,
native queue and GPU meshes. Generation-tagged slots, projected queued-state
validation, atomic rejection and a 256 MiB live/retired-image budget prevent
stale references and partial resource commits. Updates retain immutable GPU
revisions until CLEAR; disposal invalidates logical handles immediately while
preserving already-recorded draws. GL and Vulkan tests verify old purple,
updated green and reused-slot blue textures in one batch, rollback of a late
invalid command, stale-generation rejection, and resource count returning to
baseline after clear. The Vulkan capture was inspected. Logs:
m2-bridge-textures.log and m2-bridge-textures-mobile.log. Native protocol tests
also cover pending-resource references, rollback, dimensions and retired budget.

Empty RGBA texture allocation and bounded region updates now pass GL/Vulkan
integration tests. A 1024x1024 zero-initialized atlas accepts a one-pixel patch
at (1023,1023); the GPU test checks that pixel, the older transparent version,
and untouched pixels around a separate partial update. Unreferenced updates
reuse RIDs; only referenced versions consume retired-resource budget. Native
tests reject out-of-bounds/overflowing regions and verify unreferenced updates
do not exhaust the version budget. The current adapter keeps source-image CPU
shadows and uploads the resulting image through Godot; GPU subregion transfer
optimization remains. No full JavaFX scene bitmap is produced.

The JavaFX native module now locally enables exception unwinding; Godot's
other modules retain their default. JNI converts render/window allocation
failures to Java OutOfMemoryError, and window title copying no longer pins
a Java string across a potentially throwing STL allocation. engine
builds and texture, encoded host-stop and window regressions pass after this
configuration correction. No builds remain running.

GodotTexture now implements Prism BaseTexture with a real managed resource
pool and Disposer integration. GPU tests on GL/Vulkan cover ARGB_PRE,
BGRA_PRE, RGB, gray and alpha formats, source offsets/stride, direct/read-only
buffers, shared locks, generation recycling and cross-thread deferred disposal.
A 1024x1024 direct upload spans two bounded batches and renders correctly.
Both captures were inspected; encoded host-stop and Glass window regressions
pass. See prism-godot.md for source texture behavior and remaining limitations.

JSLC now generates Godot CanvasItem shaders from the existing JSL AST. The
SDK packages all 212 Prism and 50 Decora variants, matching the D3D variant
names. Both renderer tests validate exact SDK/source equality and Godot
parser acceptance. Generated FillPgram_Color also passes actual GPU checks
for interior, exterior and fractional-edge coverage; its capture was inspected.
The backend handles Godot's reserved E constant and preserves dual UV/color
inputs. Gradle now tracks compiler outputs for generation, fixing stale
incremental output after backend edits. The stock D3D reference scene passes.
No builds are running. See prism-godot.md and godot-shaders-*.log.

Next: implement Prism-Godot pipeline/context/factory
and per-draw shader/state on top of this path. Vertex transport alone does not select
or implement the Prism pipeline, stock shaders or control rendering. IME,
native clipboard, complete DnD, DPI, focus-loss state and popup/modal layers
remain required. The
scheduler/window/transport probes are NOT
full M2 acceptance. See glass-godot.md for exact coverage and limitations.

Native media/WebKit remain unbuilt (default SDK has no corresponding native
DLLs). MSYS2 has make but lacks makedepend; its configured pacman database
has no matching package. An isolated Cygwin setup download/install command
was rejected BEFORE execution by automatic approval policy, with only
"blocked by policy" as reason. This was reported; do not repeat that action.
Continue independent work, keep this limitation visible and resolve via an
authorized toolchain path later. No binary JavaFX SDK has been substituted.

The older bring-up notes above are historical. Current Prism/effects, node shader,
GodotView and VFX smoke coverage is described at the top of this file. Complete
Glass compatibility and final Demo acceptance remain pending.
Do not mark the overall goal complete based on these foundational tests.
