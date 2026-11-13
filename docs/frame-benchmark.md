# VFX frame benchmarks and diagnostics

The supported host path is **Viewport + safe**. Renderer choices are `mobile`
and `gl_compatibility`; native JavaFX/D3D runs are explicit comparisons. No
performance environment variables are required for the Demo or ordinary tests.
Run GUI measurements serially with the test window focused, without concurrent
builds or GPU-heavy work. Historical RD/separate measurements are in
[progress.md](progress.md) and Git history, not available backend choices.

## Entry points

| Command | Purpose |
| --- | --- |
| `./scripts/benchmark-vfx-frames.ps1` | Repeated animation; Java pulse and host composition counters |
| `./scripts/benchmark-vfx-frames.ps1 -Backend d3d` | Source-built native JavaFX reference; no Godot host counters |
| `./scripts/benchmark-vfx-frames.ps1 -Trace` | Java, host and frame-phase trace; enables instrumentation |
| `./scripts/benchmark-vfx-transitions.ps1` | 68 forward/backward transitions through 35 Demo pages |
| `./scripts/test-vfx-table-scroll.ps1 -Profile` | Synthetic table scrolling with host profiling; no physical mouse input |
| `./scripts/profile-vfx-menu.ps1` | Menu opening, ripples and repeated sliding with synthetic application events |
| `./scripts/profile-vfx-menu.ps1 -FullUploads` | Same menu workload with region uploads disabled for comparison |
| `./scripts/profile-vfx-gpu.ps1` | Built-in Godot GPU profile plus host command timing; diagnostic project uses 8192 timestamp slots |

`-Renderer gl_compatibility` is accepted by the frame, transition, table and menu
wrappers. `profile-vfx-gpu.ps1` uses mobile. See [TESTS.md](../TESTS.md) for
additional options, prerequisites and physical-input fixtures.

For a frame trace:

```powershell
./scripts/benchmark-vfx-frames.ps1 -Trace
python scripts/analyze-frame-trace.py artifacts/logs/vfx-frame-benchmark-safe-trace.log
```

The analyzer requires completed Java/host records and produces `.analysis.json`
beside the log. Main-thread phase gaps include intervening work and scheduling;
pre/post-draw CPU callbacks are not GPU completion or physical presentation times.

## Reading the counters

- Java pulses, completed host compositions and physical display frames are
  distinct. Divide each event count by its own interval; do not equate their FPS.
- Host CPU/sync counters overlap. They are wall-clock intervals and must not be
  summed into a GPU cost. `profile_render_offscreen_*` covers synchronous direct
  offscreen drawing; it is not GPU time.
- `lifetime_max_*` is the maximum since host creation. Subtracting endpoint
  maxima does not give the maximum within a measurement interval.
- `last_offscreen_gpu_us` is a latest measurement, not an additive counter.
  Direct-pass timestamp mapping can be cleared before results are consumed, so
  this field can remain zero. It cannot establish zero GPU work.
- The old host `window_gpu_us` / `last_window_gpu_us` fields were never updated
  and have been removed. The transition fixture measures the actual window
  viewport and reports samples separately in `VFX_TRANSITION_GPU`.
- `VFX_TRANSITION_TARGET_SWITCHES` counts process-wide Prism target/state changes,
  including startup/shutdown. It is neither GPU submissions nor an interval
  composition count. The wrapper requires a positive numeric counter.
- Focus loss, compilation warmup, stack sampling and GPU profiling affect
  measurements. Instrumented results are diagnostics, not ordinary FPS acceptance.

## Menu redraw and ripple profiling

The menu profile runs five five-second phases: closed idle, initial opening,
open-menu ripples, closed-menu ripples and repeated opening/closing. Ripples
spawn every 0.5 seconds; the final phase toggles the menu every 0.7 seconds
with ripples off. `MENU_PERF` reports pulse rate, p95/max gaps and focus loss.
Current logs are `artifacts/logs/vfx-menu-<renderer>-safe-<default|full>.log`.

Small patches update only dirty rectangles of unreferenced GPU textures.
Referenced textures receive a new immutable revision. Packed pixels are uploaded
synchronously in command order; the host does not queue a full CPU shadow.
Full replacements and unsupported layouts retain the full-update path. See
[bridge-protocol.md](bridge-protocol.md) for ownership details.

The 2026-11-12 mobile/safe comparison observed 19.524 versus 59.928 pulses/s
with open-menu ripples, and 36.135 versus 59.776 during sliding, for full uploads
versus region uploads. Historical filenames include `rd0`:
`vfx-menu-mobile-safe-rd0-{full,default}.log`. The post-removal default run observed
59.903 and 59.996 respectively (`vfx-menu-mobile-safe-default.log`). These focused
samples support this workload, not universal speedups or physical scanout claims.

## Optional diagnostics

`GODOT_JFX_PROFILE_COMMANDS=1` enables host command timings. The `-Trace` and
`-Profile` wrapper options enable it for their run and restore the environment.
`GODOT_JFX_OFFSCREEN_PROFILE=1` enables engine canvas/resource phase timing;
its periodic counters are disabled otherwise. `GODOT_JFX_PASS_SYNC_INTERVAL`
controls the diagnostic per-pass sync interval (default 0, relying on the normal
batch boundary); GPU resource ordering remains the renderer's responsibility.

`GODOT_JFX_GPU_TIMING=1` enables optional target/window measurements in the relevant
fixtures. The default 256 timestamp slots can overflow with many effect passes.
The 2026-11-13 diagnostic table/transition rerun used a temporary project override
of 8192, then removed it; ordinary project settings were unchanged. All 68
transitions passed, with 1691 window samples averaging about 512 us. Offscreen
samples still remained zero on the direct path. Logs are
`vfx-table-scroll-mobile-safe.log` and `vfx-transition-mobile-safe.log`; the initial
capacity failure is preserved in `artifacts/dead-code-audit/table-default-timestamp-limit.log`.
Do not disable error checks or treat the failure run as a passing benchmark.

`GODOT_JFX_STACK_SAMPLE=<positive milliseconds>` enables bounded Java stack
sampling. Remove the variable to disable it; zero is invalid. The sampler caps
unique stacks at 4096, joins its worker at shutdown and reports dropped samples.
Thread state and stack snapshots may race and do not measure CPU utilization.
`test-stack-sampler.ps1` checks lifecycle and budget rules.

The host's one-shot VSync pacing fallback can be disabled with
`GODOT_JFX_VSYNC_FALLBACK=0`. It preserves explicit FPS caps and restores only
settings still matching values it applied. A low cadence alone does not prove
a particular driver or presentation cause. Broader performance and memory
limits are recorded in [acceptance-status.md](acceptance-status.md).
