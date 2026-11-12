# VFX frame benchmark

## Menu redraw and ripple profiling

`./scripts/profile-vfx-menu.ps1` measures the actual Intro menu with synthetic
application events, without physical mouse/keyboard input. Five consecutive
five-second phases cover closed idle, initial menu opening, open-menu ripples,
closed-menu ripples, and repeated menu opening/closing. Ripples spawn every
0.5 seconds; the final phase toggles the menu every 0.7 seconds with ripples off.
The `MENU_PERF` records report JavaFX pulse timing, p95/max gaps and lost-focus
counts, not physical display FPS. Host command counters are also captured.
`-FullUploads` disables region uploads for a controlled comparison;
`-RenderThread separate`, `-RD`, and `-Renderer gl_compatibility` select paths.
Logs use `artifacts/logs/vfx-menu-<renderer>-<thread>-rd<0|1>-<default|full>.log`.

The menu's frequent small texture patches previously re-uploaded complete
textures. Updating only dirty rectangles for unreferenced textures removes this
avoidable transfer work. Referenced textures still get immutable new revisions;
full replacements and unsupported formats retain the existing complete-upload
path. This changes the host upload policy, not VFX animations or shader quality.
Region uploads are now the default, with `GODOT_JFX_REGION_UPLOAD=0` retained
for diagnosis. On Windows/Intel Arc B390, mobile/safe Viewport (2026-11-12),
the focused measured phases report:

| Phase | Full uploads: pulses/s, p95 ms | Default region uploads: pulses/s, p95 ms |
| --- | --- | --- |
| Menu open with ripples | 19.524, 81.154 | 59.928, 18.559 |
| Menu closed with ripples | 54.718, 20.216 | 60.076, 18.441 |
| Repeated menu sliding, ripples off | 36.135, 76.826 | 59.776, 24.156 |

Evidence is in `vfx-menu-mobile-safe-rd0-{full,default}.log` under
`artifacts/logs`; each measured row has zero unfocused intervals.

The separate render thread previously held a full CPU shadow for every queued
region upload. This kept forcing full-image copy-on-write work even though the
GPU upload was small. Callbacks now retain only packed patch pixels; Vulkan and
OpenGL accept that representation directly. Full/referenced revisions remain
protected. The same separate-mode fixture now reports:

| Phase | Before packed patches: pulses/s, p95 ms | Packed patches: pulses/s, p95 ms |
| --- | --- | --- |
| Menu open with ripples | 16.077, 78.373 | 55.266, 23.905 |
| Repeated menu sliding, ripples off | 39.964, 55.138 | 53.374, 29.527 |

Evidence: `vfx-menu-mobile-separate-rd0-before-packed.log` and
`vfx-menu-mobile-separate-rd0-default.log`. Both measured phases have zero lost
focus intervals. The final sampled host counters show 0 shadow-image clones
versus 4,248 before this change; aggregate patch blitting time fell from about
5.07 seconds to 0.076 seconds in these instrumented runs. Initial compilation and scheduling still cause some long
frames; these pulse measurements are not physical scanout rates.


Latest shared-target-mesh build (2026-11-11), mobile/safe, 68 transitions:
Viewport RD0/LCD1 = 58.604 pulse / 55.741 host-composition FPS;
RD1/LCD1 = 59.662 / 56.786. Both have zero unfocused samples and pass cleanup.
Logs: review-shared-mesh-transition-rd0.log and -rd1.log; independent composition
rates and binary hashes: artifacts/review-shared-mesh-performance.json.
These supersede earlier latest-build labels below. No physical scanout claim.


Dated measurements below belong to their named builds and configurations. The
current goal is average FPS close to 60; occasional long frames are recorded but
are not a separate repair target. RD remains opt-in (`GODOT_JFX_RD_DIRECT=1`),
and pulse, host composition and physical display rates are different metrics.

## 2026-11-11：当前构建收尾复验

Godot Editor / mobile / safe，显式 RD_DIRECT=1、LCD_SCREEN=1，栈采样变量移除，
RD/OFFSCREEN/COMMANDS/GPU/Vulkan 诊断关闭。2560×1600、60 Hz，启动 VSync=1，
未观察到 pacing 回退日志。68 次切页通过，失焦 0：58.742 Pulse FPS、
56.542773 宿主合成 FPS；p50 16.643 ms、p95 18.025 ms、p99 35.716 ms、
max 114.793 ms。资源清理通过，backpressure 462、java_launch_upcalls 0。

完整日志 `artifacts/logs/review-final-transition-full.log`；按每段脉冲数和舍入 FPS
加权复算、按宿主 presentations/elapsed_ms 复算均一致，结果保存在
`artifacts/review-final-performance-rates.json`。构建产物哈希记录在
`artifacts/review-final-performance-binaries.json`；本次运行的是 Editor，记录 Runtime
哈希不表示此次运行了 Runtime。没有同轮原生 D3D 配对，不作因果提速或追平原生声明。

首轮误将 STACK_SAMPLE 设为 0，被配置验证拒绝，保留
`review-final-transition-invalid-sampler.log`；它不是性能样本。正确关闭方法是移除变量。
正常复验支持此切页负载平均接近 60，不证明每页稳定 60、水平大表负载或物理扫描输出；
偶发长帧按用户要求暂不修复。

## 2026-11-11：最大值与最近一次 GPU 测量的报告口径

切页和表格报告只对累计计数做区间相减。`lifetime_max_draw_sync_us` 是宿主
从创建至采样结束的最大同步耗时，不能解释为本次测量区间的最大值。
启用 GPU 诊断时，`last_offscreen_gpu_us`、`last_window_gpu_us` 保留结束时
最近一次测量值；不是区间累计耗时或平均值。旧报告对这些字段相减，差值不具备
上述物理意义，不能用于解释长帧或 GPU 成本。切页的可选 GPU 样本汇总另行输出。

修正最大值报告后的普通 RD1/LCD1、mobile/safe 68 次切页为 59.184 Pulse FPS /
56.353 宿主合成 FPS，失焦 0、资源清理通过；日志
`artifacts/logs/review-transition-max-counter-full.log`。没有改 FPS 计算、动画负载
或生产渲染代码。额外开启 PROFILE_COMMANDS/GPU_TIMING 的验证只用于确认字段，
不能替代普通性能结果。

2026-11-05 plateau root cause and fallback: the ~33-Hz plateau returned
(animation benchmark 32.751 compositions/s, p50 30.557 ms). A bare-Godot probe
without JavaFX (`tests/godot/host_frame_probe.gd`) reproduces the same pacing on
Vulkan (32.83 Hz) and OpenGL (32.43 Hz), a native D3D JavaFX control on the same
machine holds 62.5 pulses/s, and VSync-off with a 60-FPS engine cap paces
cleanly at 60.10. These comparisons support a Godot/window pacing explanation
for that run; a low host cadence alone cannot identify FIFO as the cause of
every slowdown. The host runs a one-shot pacing
health check after JVM start (skip 2 s of bring-up, sample 2 s of frame
intervals): with no explicit Engine.max_fps cap, when enabled VSync on a non-fullscreen window averages above 1.4x the
refresh period, it switches to VSync-disabled plus `Engine.max_fps = refresh`
(windowed presentation behavior still depends on Windows and the driver) and prints
`JAVAFX_VSYNC_FALLBACK`. Explicit FPS limits are preserved and VSync is rechecked
before switching. On completion/failure/stop, the host restores the previously
uncapped/VSync-enabled settings only where current values still match its own
fallback values; later different application settings are preserved. This
value comparison cannot detect another writer setting the same value.
Opt out with `GODOT_JFX_VSYNC_FALLBACK=0`. With the
fallback the same benchmark records 58.050 compositions/s, p50 16.670 ms
(`vfx-frame-benchmark-safe.log`); with the knob off it returns to 32.751.

Godot-side per-pass diagnostics: `GODOT_JFX_OFFSCREEN_PROFILE=1` prints
cumulative canvas-update/prepare/draw splits per 2048 offscreen passes and
`GODOT_JFX_RES_PHASES` (printed with it) splits the resource-update phase;
their extra timing/counter work is disabled when unset. `GODOT_JFX_SAFE_PASS_SYNC=0` disables the
safe-mode per-pass device sync (measured slower; kept for A/B only).

RD-direct switches and opt-in diagnostics:
`GODOT_JFX_RD_BATCH=0` restores per-pass submission from the default
tick-level batched submission — `rd_batch_commits` in the host stats counts
committed batches against `immediate_passes`; `GODOT_JFX_RD_RING=0` disables
the mutable vertex-buffer ring; `GODOT_JFX_RD_PROFILE=1` prints sub-site
timings of the geometry apply path at exit (`RD_PROFILE`, `RD_SINKS`,
`HOST_GEOM_PROFILE`). Compiled pipelines share a process-wide 256-entry / 16-MiB payload cache.
Queued draws retain their own references; cache eviction can cause recompilation,
and final release retires the pipeline. Sharing avoids per-target recompilation
when the entry remains cached. With batched submission
plus the profile-attributed fixes (2026-11-08) the same benchmark records
56.96 pulses/s, p95 27.6 ms versus the viewport path's 42.62 / 62.6.

The transition probe runs unchanged on the native D3D pipeline (launch
`VfxTransitionProbe` with `java -Dprism.order=d3d`, same SDK build) for
same-benchmark comparison, and prints `VFX_TRANSITION_TARGET_SWITCHES`
(render-target switch count, comparable across pipelines), plus an
optional in-process stack sampler (`GODOT_JFX_STACK_SAMPLE=<ms>`) since
embedded JNI JVMs cannot be attached by jcmd.

Page-flip cost is measured separately by `benchmark-vfx-transitions.ps1`
(68 forward/backward transitions across the 35 Demo pages). After the
LCD-text destination sampling moved to the renderer backbuffer (see
prism-godot.md, 2026-11-06) the same benchmark improved from 30.9 to 35.0
pulses/s with the worst page (the 50-row table) from 7.5 to 11.5 fps
(same-binary A/B via `GODOT_JFX_LCD_SCREEN=0`). What remains is per-presentation
rounded-clip offscreen passes (shape-group clips through Prism's effect
pipeline, the same work native pipelines perform) and Java-side re-encoding of
genuinely changed page geometry; shader-state parsing measured 0.16 s of a
37 s run, so protocol-level shader-state deduplication was evaluated and not
implemented. That content-side work is a separate architectural item and
remains a known limitation, not a regression. Drag-scroll cost on the same
table page is covered by `test-vfx-table-scroll.ps1` (default uses synthetic
input; performance comparisons still require focus tracking): 96 drag pulses hold the display refresh interval with -83% offscreen
passes versus the LCD round-trip path. The draw-modulation protocol
(2026-11-07) completes the encode-side retention design — translation,
modulation and consecutive shader/clip state are all carried as draw state
(`GODOT_JFX_DRAW_MODULATE`/`GODOT_JFX_STATE_SUPPRESS` opt out) — and is
fps-neutral on this benchmark with 8% fewer full quad uploads; the clip
passes named above remain the binding constraint. When comparing runs, gate
on the probe's `unfocused` count: early single runs of this benchmark varied
by 10+ fps purely from focus/machine-load noise.

Review repeat (2026-11-04): ordinary Vulkan/safe records 59.954 completed
compositions/s and 59.985 Java pulses/s, p95 18.654 ms, p99 21.824 ms and maximum
54.074 ms. Focus-loss/backpressure/launch-upcall counters are zero. The actual
Glass/Prism backend identity checks pass. Evidence: `vfx-frame-benchmark-safe.log`.
The earlier saved runs below remain historical comparisons; they are not all
measurements of the latest source state.

Compact/R8 Media SDK regression (2026-11-03): original VFX animation on
ordinary Vulkan/safe records 59.907 completed compositions/s, 59.990 Java pulses/s,
p95 18.229 ms, p99 22.392 ms and maximum 43.165 ms. Zero focus loss, queue
backpressure and launch upcalls. Log: `vfx-frame-benchmark-safe-r8.log`.
The probe now prints the actual Glass/Prism classes and the runner rejects a
backend mismatch. Default Backend is safe (Godot); use explicit `-Backend d3d`
for the native JavaFX comparison. An earlier same-build VFX run near 33 FPS
preceded this recovery; the trigger remains unresolved. Repeated media controls
and the limitation are recorded in media-godot.md. This is near-60 average
cadence for the tested scene, not a guarantee of stable 60 FPS for all pages.

After adding explicit media-plane disposal and rebuilding the SDK, the default
Godot repeat records 58.654 compositions/s and 58.722 pulses/s, p95 18.535 ms,
p99 44.420 ms and maximum 128.103 ms. Focus/backpressure/upcall deltas remain
zero (`vfx-frame-benchmark-safe-r8-cleanup.log`). Average cadence remains near
native; occasional long frames remain a limitation and are not hidden by the
earlier faster run. Current 35-page Vulkan/safe navigation/captures complete at
2560x1600, scale 2, with final resources zero. The paired contact sheet was
inspected: layouts match; table rows/time differ as expected from Demo data.
Packaged Runtime table editing, window controls and actual GPU motion pass.

Post-Media-fix regression (2026-11-03): ordinary Vulkan/safe records
59.917 completed compositions/s and 59.984 Java pulses/s over ten animation
rounds; p95 18.175 ms, p99 22.535 ms, maximum 43.110 ms. Native D3D on the same
scene records 62.498 pulses/s, p95 16.728 ms, maximum 19.754 ms. Both runs have
zero unfocused intervals; Godot also has zero unfocused ticks/backpressure and
zero Java launch upcalls. Native pulses and Godot completed compositions are
different counters; neither measures physical scanout. These results support
near-60 average cadence, with occasional longer Godot frames still visible in
the timing data. Logs: `vfx-frame-benchmark-safe-media-fix.log` and
`vfx-frame-benchmark-d3d-media-fix.log`. Runtime VFX window controls, table editing
and GPU-motion tests also pass against the rebuilt SDK.

Current preferred interactive mode is the launcher's existing Vulkan/safe default:
`./scripts/run-vfx-demo.ps1`. An earlier focused ordinary run records
60.078 completed compositions/s, 60.242 Java pulses/s, p95 19.604 ms and maximum
35.592 ms, with zero unfocused ticks (`vfx-frame-benchmark-safe-current-ordinary.log`).
A separate diagnostic run records 60.004 compositions/s and maximum 36.880 ms.
In that safe-mode trace all 1,324 texture patches reuse their private CPU shadow;
there are no shadow clones. The focused separate-mode trace records 59.456
compositions/s and maximum 58.626 ms, with 614 clones/623 reuses. These are
representative scene measurements, not guarantees for every application or
physical scanout measurements. Prefer the default mode for the current VFX Demo;
`-RenderThread separate` remains available for comparison.

Fresh source-built native D3D comparison on the same 1280x800 logical window,
scale 2 and animation sequence records 61.002 pulses/s, p95 25.135 ms and a
231.933-ms maximum (`vfx-frame-benchmark-d3d-current-repeat.log`, zero unfocused
intervals). The first D3D run lost focus and is excluded. Native reporting counts
Java pulses, not independently observed completed presentations. The large native
outlier and run-to-run variation preclude claiming universal tail-latency
superiority from this comparison. Packaged Runtime safe-mode GPU-motion passes.

Current defaults enable the seven original accelerated-path switches and safe
CPU shadow-image reuse (`GODOT_JFX_REUSE_SHADOW`).
No performance environment variables are required to run the benchmark or Demo.
Set a switch explicitly to `0` to compare the fallback path. The dated results
below record development history, including the earlier opt-in configuration.

Latest ordinary default separate run (`vfx-frame-benchmark-shadow-default.log`)
records 59.493 completed compositions/s, 59.611 Java pulses/s, p95 19.487 ms
and maximum 65.341 ms, with zero unfocused ticks. This is near the historical
native D3D cadence (60.634 pulses/s), but does not establish equivalent tail
latency or physical display scanout timing.

The optional `GODOT_JFX_ASYNC_TARGET_TEXTURE=1` allocates a texture proxy RID
and initializes it in RenderingServer FIFO order after viewport setup. It avoids
the main-thread `viewport_get_texture` query fence, owns one extra RID per target,
and frees that proxy before its viewport. Default remains off. Focused trace
off/on runs (`vfx-frame-benchmark-proxy-off-repeat.log` / `...proxy-on.log`) show
59.539/59.568 compositions/s and target-command wall time 70.794/0.042 ms.
However, the first proxy frames still spend about 45 ms in rendering sync;
Java gaps above 33 ms number 3/6, despite maxima of 77.043/51.789 ms. Removing
this query primarily relocates the wait and is not a demonstrated smoothness
improvement. The initial off trace and on ordinary run lost focus and are
excluded from foreground performance comparisons.

The focused default trace submits 756 JNI command batches over 758 host ticks;
submission wall time totals 249.130 ms and metadata JNI time 10.471 ms over
12.731 s. The launch-upcall delta is zero; source inspection shows the only
Java launch upcall counted by this metric is application launch. OLE drag-target
callbacks also cross into Java but are a separate system-interface path, outside
this animation workload and this counter. Tick-wait duration
is blocking wall time across threads, not CPU consumption. These counters do
not support per-primitive upcalls as the current bottleneck.

With all seven variables unset after the default rollout, focused Vulkan/safe
measures 57.404 completed compositions/s (p95 24.239 ms, max 65.827 ms), and
Vulkan/separate measures 58.907 (p95 22.044 ms, max 69.776 ms). Both use ordinary
60-Hz VSync and record zero unfocused intervals/ticks. Logs:
`vfx-frame-benchmark-safe-defaults.log` and
`vfx-frame-benchmark-separate-defaults.log` under `artifacts/logs`.

For long-frame investigation use `-Trace`. This buffers per-tick host counters
and Java pulse intervals and emits them after measurement, under a `-trace.log`
suffix. It also enables `GODOT_JFX_PROFILE_COMMANDS=1` for optional texture,
render-target, geometry and shader-state wall-time counters. Trace runs are
instrumented diagnostics, not acceptance FPS. Analyze one with
`python scripts/analyze-frame-trace.py artifacts/logs/vfx-frame-benchmark-separate-trace.log`.
The adjacent `.analysis.json` contains the longest host/Java intervals and
per-round Java summaries, including focus-loss counts. Host and Java time origins
differ by marker transport; timings overlap and must not be summed as GPU work.

`profile_render_offscreen_us` measures wall time inside the render thread's
`draw_offscreen_2d`, including canvas updates and draw encoding. The accompanying
`profile_render_offscreen_calls` counts passes, and
`profile_render_offscreen_slow_calls` counts individual calls exceeding 2 ms.
These process-wide atomic counters cover both synchronous and queued direct
offscreen dispatch. They are sampled without inserting a new fence, so adjacent
host samples may straddle an in-flight render operation. They do not measure
GPU completion, shader-set commands outside the draw, or presentation/VSync.
Normal runs leave this instrumentation disabled. Trace mode requires these
fields, to reject older host binaries missing the render-thread instrumentation.

Trace mode also buffers `VFX_FRAME_TRACE_PHASES`: main-thread process-frame,
RenderingServer pre-draw and post-draw callback timestamps, using the same
origin as host samples. The analyzer reports the longest adjacent event gaps.
These include intervening work and scheduling, not just the named operation.
Post-draw callbacks are deferred to the main thread in separate mode, and
pre-draw can include explicit host draws in addition to the engine's regular
draw. Neither signal measures physical scanout or isolates GPU/VSync duration.
No signals or phase arrays are used in ordinary benchmark runs.

Host metadata refresh now reads the monitor count once per refresh and reuses
the current monitor's enumerated bounds/work area/DPI for the primary window's
snapshot. OS and scene queries finish before taking the JNI snapshot mutex.
This is reuse within one frame, not a timed cache: display information is still
refreshed every frame, with the original default-monitor query fallback if the
current index is absent from that refresh's enumeration.

After this change, the focused ordinary repeat records 59.333 compositions/s,
59.457 pulses/s, p95 20.464 ms and maximum 67.811 ms, with 755/755 focused host
ticks (`vfx-frame-benchmark-monitor-snapshot-ordinary-repeat.log`). The first
ordinary run lost focus and is excluded. The focused diagnostic trace records
56.599 compositions/s and a 118.358-ms Java maximum; its longest host gaps have
substantial time outside host processing. These results do not prove improved
smoothness from snapshot reuse, and the slower trace is retained for diagnosis.

Dirty-rectangle GPU uploads for unreferenced ordinary textures are now enabled
by default; `GODOT_JFX_REGION_UPLOAD=0` restores full uploads for comparison.
The earlier opt-in evaluation below predates the menu workload. Focused ordinary separate-mode
on/off repeats reach 59.949/59.644 compositions/s, with maxima 62.396/50.392 ms.
These runs establish near-60 averages, not consistent jitter improvement from
the region path. CPU shadow reuse is described below. Detailed evidence is in
`artifacts/logs/vfx-frame-benchmark-region-{on,off}-ordinary.log`.

Safe CPU shadow reuse is a separate optimization. With GPU region uploads off,
focused traces record texture-command wall time of 2.911 s with reuse disabled
versus 1.105 s enabled; the blit portion falls from 2.351 to 1.007 s. Enabled
executes 622 reuses and 608 necessary clones. Image references held by pending
uploads/caches and pixel-buffer COW remain protected. Composition rates in those
instrumented runs are 58.566/58.959, so the evidence supports less texture work,
not a large FPS increase at the display cap. See `vfx-frame-benchmark-shadow-off.log`
and `vfx-frame-benchmark-shadow-on.log` under `artifacts/logs`.

Run from the repository root, using the locally built SDK and Godot Editor:

```powershell
./scripts/benchmark-vfx-frames.ps1 -Backend d3d
./scripts/benchmark-vfx-frames.ps1 -Backend safe
./scripts/benchmark-vfx-frames.ps1 -Backend separate
```

The Java test navigates to the original VFX animation page and invokes its
original selection/play handlers for a-to-b traversal. Animation duration,
effects, layout and business sources are unchanged. Three traversals warm up
the renderer, then ten traversals contribute AnimationTimer intervals. Reports
include throughput and p50/p95/p99/maximum intervals. The host independently
reports completed composition counts and native/JNI diagnostic deltas between
measurement markers. No snapshots or GPU readbacks occur in this benchmark.
Both backends must report identical window dimensions and render scale before
their timings are compared. Run GUI tests sequentially.

Pulse throughput is not a GPU presentation counter. D3D currently has only
pulse measurements; the Godot presentation counter records completed host
composition, not independently measured physical display scanout. Title marker
transport introduces a small boundary difference between Java and host windows.
The original GPU-motion acceptance test remains separate:
`scripts/test-vfx-animation.ps1`.

2026-11-03 reference: native D3D 62.215 pulses/s, p95 25.970 ms. With the three
experimental flags and cadence/mesh changes, Vulkan/safe reports 49.432 pulses/s
and 49.356 completed compositions/s, p95 29.304 ms. Vulkan/separate reports
30.418 pulses/s and 30.261 completed compositions/s. These are individual runs,
not confidence intervals. They do not establish stable 60 FPS acceptance.

Logs are under `artifacts/logs/vfx-frame-benchmark-*.log`. At that stage the flags
were not production defaults; subsequent composition scheduling results are recorded
in `progress.md`.

`GODOT_JFX_EARLY_COMPOSITION_FENCE=1` additionally removes an avoidable admission
tick in separate-thread mode. With all four flags, its corrected run reports
46.482 completed compositions/s (46.229 pulses/s, p95 31.232 ms). Animation,
39 effects, 36-cycle Stage churn and transparent perimeter checks pass.

Optional `-Host120` disables Godot VSync and caps the host at 120 Hz to diagnose
display-cadence waits. It writes a separate `-host120.log`; do not compare this
as though it used the default VSync policy or treat it as a production fix.
Measured diagnostic: safe 53.732 compositions/s, separate 48.679 compositions/s.
Increasing host cadence alone does not close the gap to native JavaFX.

Later same-build controls found a ~33-Hz ordinary-VSync plateau: cache off
32.744, cache on 32.683 compositions/s. A previous Runtime binary with the current
SDK also reports 32.878. These later results supersede any claim that 46–49 FPS
is currently reproducible under default VSync. Fresh D3D remains 62.482 pulses/s;
VSync-off host120 reaches 55.417 compositions/s. The discrepancy is unresolved.

`GODOT_JFX_SHADER_SOURCE_CACHE=1` enables bounded source/encoding caches, with
dynamic shader state still validated and sent per draw. `-MailboxFps 60` (or
120/240) tests Vulkan Mailbox and rejects driver fallback. The current Intel
surface does not support Mailbox, so its fallback measurements are not Mailbox
results. Logs include requested/measurement VSync mode, refresh rate and host cap.
`-Renderer gl_compatibility` runs the same scene on OpenGL; the measured control
was slower at 37.785 compositions/s. JFR evidence is in
`artifacts/logs/vfx-frames.jfr`; it identifies repeated shader source regex work
and only 18.8 ms total GC pauses in that recording.

The next controlled change separates host-frame ticks from queue-capacity wakes:
set `GODOT_JFX_FRAME_PULSE=1` along with the accelerated flags above. With ordinary
60-Hz VSync and the window focused throughout, safe-mode off/on measures 47.450
versus 57.403 compositions/s; a repeat with the frame clock is 58.586 (p95
23.165 ms). Separate mode with `GODOT_JFX_ASYNC_PASS_FENCE=1` measured 58.850,
but that earlier run only recorded focus at the start. The frame clock removes
the extra 16-ms timer filter and delivers one coalesced pulse per host tick.
Those opt-in results were close to 60 but retained occasional long frames.

The benchmark requests focus once before warm-up and now reports
`unfocused_intervals` and `unfocused_ticks`. Reject focus-changing runs for
foreground A/B comparisons. A D3D run at 44.186 Hz lost focus during 495 of 566
intervals and is excluded; old reports without these counters cannot establish
that focus was maintained for the complete measurement.

Fresh native D3D control with zero unfocused intervals: 60.634 pulses/s, p95
27.748 ms. The controlled Godot repeats therefore reach near-native average
cadence in this scene, though their worst frame gaps remain larger. Run the
unchanged interactive Demo using this tested accelerated configuration:

```powershell
.\scripts\run-vfx-demo.ps1
```

The launcher defaults to Vulkan/safe, preserves ordinary VSync, inherits the
accelerated render path and host-frame pulse, and restores its environment variables
after the Demo closes. `-RenderThread separate` selects the other tested mode.
`-Smoke` automatically closes after startup for lifecycle verification; normal
runs remain interactive. Explicit performance overrides are respected; the
launcher no longer forces them to `1`. Backend defaults provide the acceleration.

After the 35-page and interaction regressions, a fresh rebuilt Editor safe-mode
run measures 57.192 completed compositions/s (730/730 host ticks), 57.233 pulses/s,
p95 27.853 ms and maximum 72.745 ms, with zero unfocused intervals/ticks. See
`artifacts/logs/vfx-frame-benchmark-safe-after-broad-regression.log`. This repeats
near-native average cadence but does not establish consistently smooth 60 FPS.

## Stack sampler reliability (2026-11-10)

The optional VFX sampler requires a positive integer millisecond interval;
invalid settings fail explicitly instead of disabling sampling silently or
spinning on repeated sleep failures. Its worker exclusively owns a map capped
at 4096 unique stacks. Stop interrupts sleep and joins the worker before a
report is copied; capture errors and a failed shutdown are reported as failures.
Overflow observations are counted in `VFX_TRANSITION_SAMPLE_DROPPED`. These are
bounded diagnostic samples, not an exhaustive profile. Sampling-enabled runs
print `diagnostic_only=true` and must not be treated as uninstrumented FPS data.
The standalone `test-stack-sampler.ps1` checks these lifecycle and budget rules.

Reports include the observed thread state and up to eight frames nearest the
current execution point, including Java wait/sleep frames. State and stack are
observed separately and can race with the running thread; these wall-clock
samples do not measure CPU utilization or prove a bottleneck on their own.

## Godot phase timing is opt-in (2026-11-10)

`GODOT_JFX_OFFSCREEN_PROFILE=1` now gates the Canvas dirty-item and RD resource
phase clocks/counters as well as the offscreen-pass report. With profiling off,
the normal resource update work still runs, but these extra timestamp reads,
accumulations and periodic `GODOT_JFX_RES_PHASES` messages are skipped. The option
is captured once per process; change it before launching the host. Enabled
measurements remain instrumented diagnostic data.

## Texture retirement fence follow-up (2026-11-10)

After fixing early texture retirement, the source-built Editor completed
`benchmark-vfx-transitions.ps1 -Renderer mobile -Backend safe` with RD direct
rendering enabled, RD debug/profiling and offscreen profiling disabled, and Java
stack sampling unset. The 2560×1600 window remained focused for all 68 transitions
on a 60-Hz display with VSync enabled. Preserved log:
`artifacts/logs/review-vfx-transition-retirement.log`.

| Measurement | Earlier bounded-geometry run | Texture-retirement follow-up |
| --- | ---: | ---: |
| JavaFX pulses/s | 57.255 | 56.744 |
| Host compositions/s | 54.730 | 53.972 |
| Pulse p95 gap (ms) | 21.072 | 26.212 |
| Pulse p99 gap (ms) | 75.116 | 60.800 |
| Maximum pulse gap (ms) | 191.007 | 181.025 |
| RD batch commits | 4974 | 5318 |

The earlier log is `review-bounded-geometry-transitions.log`. These are single,
noncontemporaneous runs with intervening changes, not a controlled A/B test.
Average cadence and p95 worsened while p99 and the maximum improved; neither a
performance regression attributable to the fence nor a performance improvement
is established. Stable 60 FPS remains unproven. Host composition counters do not
measure physical display presentation. `java_launch_upcalls=0` covers that named
counter only; it does not imply that all Java/native crossings disappeared.

This measurement predates the bounded shared-pipeline cache change. The new
cache ownership and lookup costs need a fresh uninstrumented run before making
performance claims about that change.

## Bounded shared-pipeline follow-up (2026-11-10)

The source-built Editor with the 256-entry / 16-MiB pipeline cache completed
`benchmark-vfx-transitions.ps1 -Renderer mobile -Backend safe`, with RD direct
on, RD debug/profiling and offscreen profiling off, and Java stack sampling
unset. Log: `artifacts/logs/review-vfx-bounded-pipelines.log`.
The 2560×1600 window stayed focused through all 68 transitions at 60-Hz VSync.

| Measurement | Bounded pipeline cache |
| --- | ---: |
| JavaFX pulses/s | 58.242 |
| Host compositions/s | 55.604 |
| Pulse p50 / p95 / p99 gap (ms) | 16.436 / 24.686 / 39.301 |
| Maximum pulse gap (ms) | 212.925 |
| RD batch commits | 5393 |

Compared with the preceding retirement-fence log, this single run has higher
average cadence and lower p95/p99, but a larger maximum gap. It is not a paired
A/B comparison and does not establish a causal speedup or consistently smooth
60 FPS. The later window-composition diagnostic gating change is not included
in this measurement. That change caches RD_DEBUG once and skips its extra clock
reads when disabled; rendering and synchronization remain unconditional.

## Target-switch diagnostic availability (2026-11-10)

The host now exports `com.sun.prism.impl.ps` to its application classpath, like
its other Prism diagnostic packages. Previously the probe's reflective read
of the public `BaseShaderContext.TARGET_SWITCHES` counter was denied by module
access and printed `unavailable`. The Godot transition wrapper now requires a
positive numeric counter as well as the backend markers and ordinary PASS.
This is the cumulative process count read after JavaFX exits, including startup
and shutdown; it is not a delta over the timed transition interval and is not a
GPU submission/presentation count. Historical logs with `unavailable` remain
valid only for the other metrics they actually recorded.

The rebuilt Editor follow-up passed with `VFX_TRANSITION_TARGET_SWITCHES 33412`:
`artifacts/logs/review-vfx-target-switch-counter.log`. Diagnostics/sampling were
disabled, RD direct was enabled, and all 68 transitions stayed focused at
2560×1600 / 60-Hz VSync. Pulse rate was 57.436/s, host compositions 55.033/s,
p95 24.324 ms, p99 57.498 ms, and maximum 255.111 ms. The counter is now available;
these repeat results still show long-frame variability and do not establish
stable 60 FPS or a speedup from the export/diagnostic fixes.

The later LCD per-node snapshot run (`review-vfx-lcd-node-snapshot.log`, explicit
RD_DIRECT=1) failed with an invalidated queued uniform binding. Its pulse and
composition figures are diagnostic output from a failed run, not accepted
performance evidence. A subsequent debug run without explicit RD_DIRECT logged
zero RD batch commits and cannot establish that the RD failure disappeared.

## Queued texture-reference repair follow-up (2026-11-10)

`review-vfx-texture-reference-fence.log` records the repaired Editor with
RD_DIRECT=1 and LCD_SCREEN=1, profiling/debug off and Java sampling unset.
All 68 transitions pass with zero focus loss at 2560×1600 / 60-Hz VSync:
58.183 pulses/s, 55.530 host compositions/s, p95 19.964 ms, p99 37.312 ms,
maximum 158.954 ms, 44,215 offscreen passes and 6,238 RD batch commits.
There is no invalidated-binding error. This accepts that workload after the
texture-reference repair, not consistently smooth 60 FPS or a controlled
speedup claim. Per-text-node LCD correctness now costs more offscreen passes
than the earlier shared-snapshot path; transfer remains batched.

## 2026-11-10：Shader 修复与名称缓存有界化后的整段复验

源码 Editor / mobile / safe，显式 RD_DIRECT=1、LCD_SCREEN=1，关闭 RD_DEBUG、
RD_PROFILE、OFFSCREEN_PROFILE 和 Java 栈采样。2560×1600、显示器 60 Hz、失焦 0，
68 次切页通过，无 ERROR，日志 `artifacts/logs/review-vfx-post-shader-fixes.log`。
测得 pulse 57.296/s、宿主合成 54.614/s，p50 16.656 ms、p95 20.486 ms、
p99 45.996 ms、最大 188.866 ms；RD batch commits 5866、Prism target switches
32751。启动报告 VSync=1，但随后检测到平均 32.967 ms 的 FIFO 阻塞并自动转为
CPU pacing，所以不能把整段描述成持续 FIFO/VSync 运行。单次结果仍有长帧，
不构成稳定 60 FPS 或相对上一轮显著提速的证据。此轮后续的模块卸载阶段修复
只改变退出清理入口；上述测量发生在该修复前。

## 2026-11-10：大表诊断采样与时间序列更正

VfxTableScrollProbe 原先仍保留旧的无界采样 Map，停止时未 join，异常被忽略。
现与切页夹具共用 ThreadStackSampler：最多 4096 种栈，保留线程状态和等待帧，
停止并等待工作线程后读取稳定快照，异常退出也会关闭采样器。包装器同时编译
该帮助类；未配置时不采样，非法配置明确失败。

空闲分位数此前直接按未排序列表取索引；现先排序。拖动 GAPS_MS 此前在排序后
输出，不能用作长帧周期分析；现保存原始时间顺序，另用排序数据计算分位数。
旧日志对应的空闲分位数与拖动“时间序列”不能作为相应分析证据。

显式 direct（不操作真实输入）、RD_DIRECT=1、mobile/separate、20 ms 采样运行
通过，日志 `review-table-sampler-positive.log`，丢弃样本 0；96 项原始间隔与
汇总分位数经独立重算，在日志舍入范围内一致。0 ms 配置运行明确失败，日志
`review-table-sampler-invalid.log`。这些采样运行用于诊断可靠性，不能当作
未采样 FPS 或性能提升证据。

## 2026-11-10：大表宿主计数窗口更正

旧夹具的 measured_ticks/unfocused_ticks 只在空闲阶段递增，却放进拖动报告；
资源采样用的 pollCount 从未递增，实际每帧采样，横坐标重复为同一空闲计数，
最后一项还使用数组长度作为 tick。旧日志不能证明拖动阶段的失焦比例，
GROWTH 也不能据此推断增长发生在哪个拖动时刻。

现空闲与拖动分别计数，GROWTH 从拖动 tick 0 起每 8 tick 采样，加上结束项，
并断言横坐标严格递增。max_* 不再相减，改以 lifetime_max_* 输出当前进程
累计最大值；普通累计计数仍输出区间差值。

未开启栈采样的 direct / RD_DIRECT=1 / mobile / separate 实跑通过，日志
review-table-host-counters.log：空闲 61 tick、拖动 95 tick，各自失焦 0；
GROWTH 共 13 项，横坐标 0、8、16……88、95，经独立 JSON 检查确认端点
与拖动计数一致。该次窗口有焦点，不验证后台拖动或物理鼠标。

## 2026-11-10：原生大表物理对照工具审查

NativeTableDrag 旧版在后台线程等待后即读写 FX 线程的帧列表，超时未完成也可能
继续输出 PASS；动画异常未统一释放鼠标按键。现改为 FX 线程状态流程，完整
96 次间隔、清理成功及 Application.launch 返回后才输出 PASS；失败传播到 main，
提前关闭不再通过，失焦会中止，正常/异常/关闭路径统一清理。场景访问不再跨线程，
分位数采用与其他夹具一致的 nearest-rank 索引。

获用户授权后，当前源码 SDK 上以 Win Glass、请求 D3D 的命令运行两个方向，均通过
96 间隔和退出门禁：垂直 61.882 pulse FPS（p95 20.410 ms），水平 61.873
（p95 23.068 ms）。日志 review-native-table-drag-v.log、review-native-table-drag-h.log。
补齐原鼠标位置恢复，以及后台任务清理异常时仍尝试注销全局监听器的路径。
原生对照不是 Godot 后端验收；采样没有表格位移/像素断言，也未注入清理异常。后续位移门禁已补齐，记录见下文。
45 秒期限依赖 FX 脉冲推进，不是进程外的挂起检测。运行说明见 TESTS.md。

## 2026-11-10：悬停图像门禁补全

hover-flicker 旧实现只对普通按钮断言，FusionButton 的 hold/gap 亮暗值只打印；
现要求六轮各有稳定样本，跳过每轮前 23 帧后按固定 0.30 亮度阈值检查，
稳定期错误帧超过 5% 则失败。新增 HOVER_FUSION_PIXEL_PASS，脚本同时拒绝
ERROR/SHADER ERROR；宿主失败或超过 120 秒均结束为失败。输入与采样区域
使用当前屏幕缩放，不再硬编码 2 倍。

mobile/separate 合成输入实跑通过，日志 review-hover-fusion-gate.log：普通按钮
1432 帧、缺色 28 帧；Fusion 稳定 hold 588/588 亮、gap 224/224 暗。当前屏幕
2 倍缩放、60 Hz，未运行其他缩放或 Robot。该夹具每帧 GPU 读回会影响性能，
只用作视觉正确性检查，不能从它推导 FPS。旧 Fusion 统计无断言的 PASS
不能替代新增门禁。

## 2026-11-10：按更新后的目标复验当前构建

当前目标为 FPS 接近 60，偶发长帧暂不修复。本次使用最近的源码 Editor/SDK，
Godot / Glass-Godot / Prism-Godot，Vulkan mobile + safe，RD_DIRECT=1、
LCD_SCREEN=1；关闭栈采样、HOVER_TAP、RD/OFFSCREEN profile、GPU timing 和
RD debug。2560×1600、60 Hz，启动记录 vsync=1；日志没有记录自动 pacing
回退，不能仅凭启动值证明全程显示模式。

68 次页面动画切换通过，共 1625 个测量 pulse、失焦 0：pulse 平均 57.343 FPS，
宿主合成提交 54.538 FPS；p50 16.608 ms、p95 19.768 ms、p99 67.850 ms、
max 283.435 ms。日志 `artifacts/logs/review-vfx-current-scope.log`。独立按每段
pulse 数及 FPS 重算加权总速率、按宿主 presentations/elapsed_ms 重算合成
速率，均与汇总一致。

这是当前工作负载平均帧率接近 60 的证据，不是每个页面均稳定 60，也不是
物理显示帧率测量。短过渡的最低均值仍为 25.551 FPS（R18 大表），受长帧
影响；保留记录，不据这次长帧追加修复或改变 VFX 行为。没有与同轮原生
JavaFX 配对运行，不据本次数字声称超越或追平原生性能。

## 批次容量修复后的复验（2026-11-10）

当前 Media SDK、Godot Editor mobile/safe，RD1/LCD1，诊断采样关闭，60 Hz、
2560×1600；68 次切换、1625 个 pulse、失焦 0。平均 59.125 pulse FPS，
宿主合成 56.547 FPS；p50 16.649 ms、p95 18.315 ms、p99 28.614 ms、
max 103.647 ms。按每段 pulse/FPS 加权和宿主计数独立复算均一致。
完整日志 review-batch-boundary-vfx-full.log，复算 review-batch-boundary-rates.log。

结果仍接近 60，不把单次波动归因于容量修复，也不把 pulse/合成计数当作实际
显示刷新。此轮没有配对原生对照；继续保留偶发长帧，不追加相关修复。

## 手动悬停日志的解释限制（2026-11-10）

`repro-hover-manual.ps1 -LogPath <已有日志>` 只读取并汇总，不启动 Demo，不改
诊断环境变量。此模式没有原生退出码，输出会明确说明未知；不是一次新验收。
连续亮度采样相同、随后变化，只能确定该采样区域的亮度序列，静态画面也会
产生这种结果。缺帧时不把前后样本拼成连续跳变；帧跨度不再乘固定 16.7 ms，
因为日志没有每帧真实时间。FX_GAP 是等待队列任务的时间，也可能是正常空闲；
与宿主间隔相近只是排查线索，不能单独判定因果或帧率。

实时运行结束后仍先输出诊断摘要，再对非零进程退出/错误日志报告失败。本次
修改报告准确性，没有修复或重新开启偶发长帧优化。

## 2026-11-10：水平表格负载的实际位移门禁

修正前 horizontal 选择不能保证 direct/real 真正横向滚动，且跳过位移门禁；
旧水平 PASS 不证明工作负载有效。当前两模式分别观察 1500 px 的累计横向位移，
默认纵向回归 2325 px。只有所选轴 ≥200 px 才允许通过，不修改 Demo 业务行为。

mobile/safe，96 脉冲，未启用 RD 的水平 direct/real 分别 44.020/42.645 FPS；
显式 RD_DIRECT=1、LCD_SCREEN=1 的水平 direct 为 51.819 FPS（p50 16.933 ms，
p95 36.334 ms，max 59.333 ms），2644 次 RD 批次提交，失焦 0。
日志 review-table-horizontal-{direct,real,rd}-full.log。短样本与运行次序可能影响
结果，不据此宣称全场景性能达标或确定的提速比例；中位间隔不能替代平均 FPS。
本轮不操作物理输入，也不针对偶发长帧修改运行时。

## 2026-11-10：水平负载延长采样

表格夹具增加 `-Sweeps 3..30`（默认仍为 3×32 脉冲），Java 与合成输入端使用
相同段数，长样本不丢弃前段。非默认段数日志名带 `-sweepsN`。
显式 RD_DIRECT=1 / LCD_SCREEN=1 / mobile / safe / direct / h，30 段共 960 脉冲，
15000 px 累计位移、资源与结束检查通过；平均 50.978 FPS，p50 18.123 ms，
p95 31.554 ms，max 62.813 ms，失焦 0（review-table-horizontal-long.log）。
按日志四舍五入到 0.1 ms 的间隔复算，前 96 脉冲约 51.959 FPS，后 864 约
50.870 FPS；不是仅初次绘制拖低结果。复算记录 review-table-horizontal-long-analysis.json。

独立的 `-Profile` + 20 ms 栈采样运行仅用于定位，不作为无诊断性能测量。
宿主 encode 约 5.76 s，其中 geometry 约 2.13 s、shader 约 1.94 s、texture
约 0.43 s；Java 多数样本为队列等待，JNI await 的 RUNNABLE 标签不能解释为
CPU 忙碌。日志 review-table-horizontal-profile-full.log。据此检查持续状态处理
开销，不针对单个最长帧修改运行时。

关闭诊断后的修复版同配置长测通过：960 脉冲、15000 px、失焦 0、23069 次 RD
批次提交，平均 53.707 FPS，p50 16.803 ms、p95 33.556 ms、max 56.192 ms；
日志 review-table-instance-lookup-long-full.log。旧样本为 50.978 FPS，但 VFX 数据
随机且没有重复交错对照，因此只报告结果，不断言差值全部来自此次修改。
该重负载仍低于稳定 60，不能用其接近 16.7 ms 的中位数替代平均值。

顶点转换入口后续移除了同类型输入数组的两次深拷贝，并在布局转换前一次性获取
可写存储。RD_SINKS 保留历史 copy_us 字段，但该入口不再计入复制时间；零值
不表示整个渲染路径没有数据复制。此次只验证所有权与像素回归，没有新增 FPS 结论。

## 2026-11-10：顶点入口校验后的 VFX 切页

当前源码 Editor/Media SDK，mobile/safe、显式 RD1/LCD1、无诊断/栈采样，
68 次切页通过，1627 pulse、失焦 0。平均 57.553 pulse FPS，54.324900 宿主
合成 FPS；p50 16.621 ms、p95 20.656 ms、max 410.083 ms。每段脉冲数与舍入
速率独立加权复算为 57.552547，宿主 presentations/elapsed_ms 复算一致。
日志 review-vfx-after-input-validation-full.log、review-vfx-after-input-validation-rates.json。
该运行在当时替代旧 59.125/56.547；后续切页记录见本文顶部；不从单次波动推断优化或退化，
也不把它替代水平表格负载。偶发长帧没有作为本轮修复对象。
