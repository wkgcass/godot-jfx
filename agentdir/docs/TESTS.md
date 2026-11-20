# TESTS — historical verification

## Windows 稳定性复验

macOS 验证前按 `docs/build-macos.md` 从源码重建对应产物。带 `--renderer <后端>` 的用例分别运行 `mobile`（Metal）和 `gl_compatibility`（OpenGL），使用 safe 模式，GUI 测试串行执行。每个入口均须正常退出、退出码为 0，并满足脚本原有 PASS 与错误检查。合并 `ca8ff42` 后既有窗口及资源修复的 Windows 三轮稳定性记录位于 `agentdir/artifacts/logs/restored-stability-20261118/results.csv`。

## 外部拖放

外部探针的 FX 驱动调用设有 10 秒超时，回调异常会使测试失败；退出时停止并回收驱动线程，逐项尝试释放输入、恢复原鼠标位置和关闭窗口，清理失败不输出 PASS。脚本恢复调用前的 helper 坐标环境变量。早期 2026-11-10 记录仅有编译和语法检查；后续已获授权的 Runtime mobile/safe 跨进程实跑通过，含拖入/拖出、自定义负载、预览元数据和取消，日志 `review-drag-request-runtime-external.log`。实际运行仍需有效用户授权和空闲桌面；不据此证明所有外部应用兼容。

## Media 资源回收

Media churn 也覆盖 Viewport 材质缓存对已销毁视频纹理的回收。2026-11-10 的
mobile Runtime、24 轮、`-Providers` 在缓存开启时曾于第 11 轮触发资源增长
门禁（owned=51）；修复后同一门禁通过，owned=31、最终为 0。保持原来的
暖机后资源上限，不以禁用缓存或提高阈值作为通过条件。修复前后日志分别为
`review-final-media-churn-runtime-full.log` 与 `review-material-retirement-churn-full.log`。

## 虚拟键盘

`test-virtual-keyboard.ps1` 的成功仅表示 Java 调用完成、宿主 tick 继续推进和探针
清理完成，不验证系统键盘是否实际显示或关闭。脚本会直接输出原生日志中的
touch keyboard 警告。2026-11-10 当前产物运行返回关闭请求 HRESULT
`-2147024891`（拒绝访问），因此不能以该次 PASS 宣称系统键盘关闭成功；
证据为 `agentdir/artifacts/logs/review-final-virtual-keyboard.log` 和 `virtual-keyboard.log`。

## 快速拖出窗口

2026-11-10：mobile/separate 合成与 Robot、GL/safe 合成均通过。真实档验证窗口
Y=-14、尺寸 740×576、手势连续和宿主资源归零，日志
`agentdir/artifacts/logs/physical_drag-mobile-separate-robot.log`。本机实际缩放为 2 倍，
未切换显示器 DPI，也未动态注入 Robot 清理错误；不能据此宣称跨屏缩放已验证。

## 原生表格拖动

2026-11-10 获授权后水平、垂直实际运行均通过，各 96 个间隔；日志为
`agentdir/artifacts/logs/review-native-table-drag-h.log` 和 `review-native-table-drag-v.log`。
上述 2026-11-10 记录只验证采样和正常退出。2026-11-11 补齐位移门槛与水平可滚动目标筛选后，
纵向 62.475 FPS/1581 像素、横向 62.530 FPS/867 像素均通过，日志为
`review-native-table-displacement-v.log`、`review-native-table-displacement-h.log`。
这仍是 Pulse 测量，不含像素断言或动态注入清理异常。
