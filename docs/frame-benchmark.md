# VFX frame benchmarks and diagnostics

The supported host path is **Viewport + safe**. Windows driver choices are `d3d12` (default),
`vulkan` and `opengl`; native JavaFX/D3D runs are explicit comparisons. No
performance environment variables are required for the Demo or ordinary tests.
Run GUI measurements serially with the test window focused, without concurrent
builds or GPU-heavy work. Historical RD/separate measurements are in
[progress.md](../agentdir/docs/progress.md) and Git history, not available backend choices.

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
| `./scripts/profile-vfx-loading.ps1` | Ripple animation plus a LoadingStage/alert window; pulse rate per phase |
| `./scripts/profile-vfx-gpu.ps1` | Built-in Godot GPU profile plus host command timing; diagnostic project uses 8192 timestamp slots |

On macOS, use `./scripts/profile-vfx.py frames|transitions|menu|loading|gpu`.
Select Metal or OpenGL with `--driver`. The frames command accepts `--trace`,
`--host120` or the native JavaFX Metal comparison `--native`. The menu command
accepts `--full-uploads` and `--host120`. The latter disables swapchain VSync and caps the Godot host loop at 120 FPS for that run. GPU profiling requests 4096 timestamp slots on
Metal. Each sample occupies eight bytes, which fills the M1's 32 KiB
counter buffer. The GPU command checks that the captured timings include
a positive frame duration. Logs include the driver in the filename under
`agentdir/logs`.

The OpenGL profile uses the project's 8192-slot setting. On the M1 the
OpenGL 4.1 driver reports zero counter bits for `GL_TIMESTAMP` and 32 for
`GL_TIME_ELAPSED`. The compatibility renderer uses successive GPU elapsed
queries to measure intervals between profile markers on that driver.
The first three total GPU frame times in the VFX capture were 3.680,
4.785 and 6.595 ms. The driver probe and frame profile are recorded in
`agentdir/logs/macos-gl-timestamp-capabilities.log` and
`agentdir/logs/vfx-gpu-opengl.log`.

The Windows frame, transition, table, menu and GPU profiling scripts accept `-Driver`.
The mailbox diagnostic requires `-Driver vulkan`. See [TESTS.md](../TESTS.md) for
additional options, prerequisites and physical-input fixtures.

For a frame trace:

```powershell
./scripts/benchmark-vfx-frames.ps1 -Trace
python scripts/analyze-frame-trace.py agentdir/logs/vfx-frame-benchmark-safe-trace.log
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
Current logs are `agentdir/logs/vfx-menu-<driver>-safe-<default|full>.log`.

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

## Loading window and ripple profiling

`./scripts/profile-vfx-loading.ps1` keeps the ripple effect animating on the
Demo page, then opens the LoadingStage demo window, waits for its completion
alert and dismisses it. `LOADING_PERF` reports the pulse rate of each four-second
phase (baseline, ripple, loading, alert, dismissed, ripple-off) and the host
logs `LOADING_STATS` counters; require `VFX_LOADING_PERF_PASS` and
`GODOT_VFX_LOADING_PERF_PASS`. On the fixed presentation path every phase stays
at display cadence; previously each animating native window held the shared
frame queue until its own post-draw composition, capping all windows near
20 pulses/s. The fixture fires synthetic events only. Timing is diagnostic,
not a fixed FPS acceptance threshold. Log: `agentdir/logs/vfx-loading-perf-mobile-safe.log`.

## Optional diagnostics

`GODOT_JFX_PROFILE_COMMANDS=1` enables host command timings. The `-Trace` and
`-Profile` wrapper options enable it for their run and restore the environment.
`GODOT_JFX_OFFSCREEN_PROFILE=1` enables engine canvas/resource phase timing;
its periodic counters are disabled otherwise. `GODOT_JFX_PASS_SYNC_INTERVAL`
controls the diagnostic per-pass sync interval (default 0, relying on the normal
batch boundary); GPU resource ordering remains the renderer's responsibility.

`GODOT_JFX_GPU_TIMING=1` enables optional target/window measurements in the relevant
fixtures. The default 256 timestamp slots can overflow with many effect passes.
[Historical verification](../agentdir/docs/frame-benchmark.md) records the diagnostic rerun with a larger timestamp pool.
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

Wayland/EGL on the B390 exposes swap intervals 0 and 1.

For Linux/Wayland interaction profiling, use `scripts/test-vfx-blackhole.sh --profile --driver vulkan` (or `opengl`). The probe moves the active lens for 90 JavaFX pulse intervals, reports the pulse rate and p95 interval, then runs the visual comparisons. `scripts/test-vfx-table-scroll.sh --profile --driver opengl` reports table displacement and render work, and `python3 scripts/profile-vfx.py menu --driver opengl` reports separate open-ripple and sliding phases. These timings measure JavaFX pulses. The isolated B390 measurements at desktop scale 2 are archived under `agentdir/artifacts/wayland-interaction-hQ6x4vwN`.

| Wayland/B390, scale 2 | Table drag p95 (ms) | Menu sliding p95 (ms) | Moving lens p95 (ms) |
| --- | ---: | ---: | ---: |
| Vulkan, default | 50.426 | 60.243 | 18.191 |
| Vulkan, LCD region copy | 46.107 | 83.584 | 17.658 |
| OpenGL, default | 264.371 | 143.965 | 47.420 |
| OpenGL, LCD region copy | 200.058 | 145.287 | 26.200 |

These are single observations, not performance gates. Logs are in
`retained-off-*` (default), `retained-on-*` and `restart-3RmktF9w` (opt-in
`GODOT_JFX_LCD_REGION_COPY=1`). Some opt-in samples followed a WSL restart.
On the OpenGL table drag, offscreen passes fell from 15,431 to 1,104, but
the host still spent 3.21 s processing the 10,041 quad commands that
carried vertex data. The default run spent 4.13 s on 9,946 such commands.
The counter `profile_geometry_us` covers `QUADS` and `TEXTURED_QUADS`,
including mesh construction and draw setup. It excludes `QUADS_REF`
(1,665 opt-in versus 20,887 default) and does not measure GPU time. The
JavaFX probe reported the same 2,325-pixel displacement in both runs.
Fewer passes did
not consistently improve menu latency; the option remains off by default.

The Java sampler-binding step runs for every Prism quad batch. An allocation
probe using JDK 25, the Linux graphics JAR and two 2×2 textures measured the
calling thread after 15,000 warm-up calls. With no samplers, returning the
existing shader snapshot reduced allocation from approximately 389 bytes to
zero per call. With two samplers, reusing the immutable wrap and filter
constants reduced it from 1,472 to 1,256 bytes. The probe checked all seven
Prism wrap modes with filtering both on and off, including two texture units
with different filter settings. Application frame times need a separate run
with the updated JAR. Results are under
`restart-suite-n8jhXQQK/sampler-bind-vBICV9Iy` in the B390 release archive.

### Linux table dragging on the published runtime

A separate scale-1 test opened the packaged VFX JAR on private labwc. It
clicked Next 19 times to reach the 50-row table, then held the Wayland
pointer button while moving 216 pixels per stroke, alternating direction
six times. Matching distinctive text scanlines between compositor grabs
accounted for every pixel of travel in all four launches. The table moved
1,296 pixels and returned to its initial row after the sixth stroke.

| Linux package | Driver | Distinct shifts captured during the six strokes | p95 gap between sampled shifts during motion |
| --- | --- | ---: | ---: |
| `da0a4ee0ac9a` | OpenGL | 52 | 66.8 ms |
| `906cf6d68fa4` | OpenGL | 100 | 52.4 ms |
| `906cf6d68fa4`, repeat | OpenGL | 98 | 51.7 ms |
| `906cf6d68fa4` | Vulkan | 110 | 48.7 ms |

Each stroke contained 36 pointer moves over roughly 0.6 seconds. Counts cover
visible vertical shifts during motion. Additional shifts arrived while the
pointer was held at each endpoint. The sampler can miss intermediate frames.
The command-line JAR, mapped library digest, input timestamps, screenshots
and row displacement measurements are recorded under
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-release-MIuxEnnx/table-jar-input-JnpgaxJA`.

The ordinary table-scroll fixture moved the table by 2,325 pixels on both B390 backends at scale 2. A JDK 25 Flight Recording covered the same gesture as the native counters. The recording window starts with the idle summary and ends with the drag summary. Log timestamps were observed at 80 ms intervals.

| Measurement | Vulkan Mobile | OpenGL Compatibility |
| --- | ---: | ---: |
| JavaFX pulses | 96 | 96 |
| Pulse p95 (ms) | 41.8 | 215.6 |
| Recording window (s) | 2.01 | 6.66 |
| Queue-full responses | 0 | 81 |
| Host command encoding (s) | 0.60 | 3.49 |
| Direct offscreen rendering calls, elapsed time (s) | 0.12 | 2.24 |

On OpenGL, the JavaFX Application Thread spent 3.97 s waiting for painting to finish. All 42 native-method samples on the Prism renderer were in `GodotBridge.awaitTick`, called by `GodotRenderCommands.submit` while publishing the window. The host wakes a capacity waiter immediately after taking a batch. These observations point to the host's rate of consuming queued rendering work. Enlarging the queue would also allow more input-to-display latency. On Vulkan, the application thread spent 1.92 s waiting for the next event and the renderer spent 1.88 s waiting for its next job. These are per-thread observations over overlapping intervals. Native host times measure elapsed CPU-side calls, including waits inside the driver.

The recordings, stack summaries and per-case logs are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/verified-release-lZUp7QMq/restart-suite-n8jhXQQK/` under `drag-profile-Yjtsj1qQ/` and `nonrobot-full/{286,287}-test-vfx-table-scroll/`.

On the same B390, a diagnostic build timed the CPU-side call to `ArrayMesh::add_surface_from_arrays` during the 2,325-pixel drag. On OpenGL, 3,162 mesh submissions took 3.53 s out of the 3.64 s spent on quad commands carrying vertices. Material lookup and retained draw-slot setup took 21 ms and 33 ms respectively across all draws. On Vulkan, 3,127 submissions took 0.55 s. These wall times include time waiting inside the graphics stack.

A separate diagnostic build kept all Prism vertex attributes and used an unindexed triangle strip for a single quad. In four runs on each backend (indexed, strip, strip, indexed), OpenGL drag p95 was 248.2, 195.6, 191.3 and 229.1 ms. Vulkan p95 was 41.0, 36.5, 39.2 and 49.1 ms. The mesh-transform, blit, LCD overlap and node-shader fixtures passed on each backend. Of 14 comparable images, 13 were identical to the prior release. One OpenGL LCD capture differed by at most one 8-bit channel level.

Using the existing Godot dynamic-buffer hint for vertex and attribute uploads on Mesa D3D12 further reduced OpenGL drag p95. With single-quad strips throughout, static, dynamic, dynamic and static runs measured 191.9, 93.5, 87.3 and 196.2 ms respectively. All eight strip-comparison and four buffer-hint runs completed 96 drag intervals and moved the table 2,325 pixels at scale 2. These are isolated Weston measurements from diagnostic binaries. Per-run logs are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-jfx-revision-xsBlG2d3` in `native-timing-xHIlveCA`, `quad-strip-g051yJ3X` and `gl-mesh-usage-3C17lsol`.

Applying the dynamic hint to the index buffer of a dynamic 2D mesh on Mesa D3D12 reduced drag p95 to 47.2 and 49.1 ms. With only the vertex and attribute buffers using that hint, the same build recorded 87.4 and 82.1 ms. Both configurations used single-quad strips. Total mesh submission time fell from 0.73–0.80 s to 0.046–0.060 s. Using an index buffer even for single quads gave 55.1 and 55.5 ms with all three buffer hints enabled. The same build passed the OpenGL mesh-transform, blit, LCD and node-shader checks. With all changes enabled, menu opening measured 18.4 ms and sliding measured 46.7 ms, versus 48.1 and 134.9 ms in one ordinary indexed run. Moving the lens measured 19.4 versus 18.7 ms. Menu and lens each had one run per configuration. The six drag logs and phase results are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-jfx-revision-xsBlG2d3/gl-index-usage-CncvbdFd/verified.json`.

The uninstrumented source build `da0a4ee0ac9a…` passed the same table fixture at 51.2 ms on OpenGL and 41.9 ms on Vulkan. For a separate comparison, both published builds ran the complete menu and moving-lens fixtures once per driver. The mapped library hash, Wayland display and B390 renderer were checked in each process. The archive is `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-release-eVFhfCPk/interaction-RFvVIM0A/verified.json`.

| Published engine | Driver | Opening menu p95 (ms) | Sliding menu p95 (ms) | Moving lens p95 (ms) |
| --- | --- | ---: | ---: | ---: |
| `20e839a2fcf2…` | opengl | 37.1 | 154.9 | 23.2 |
| `20e839a2fcf2…` | vulkan | 19.5 | 52.6 | 18.1 |
| `da0a4ee0ac9a…` | opengl | 19.8 | 41.2 | 21.6 |
| `da0a4ee0ac9a…` | vulkan | 25.7 | 50.6 | 18.3 |

A control run on the same optimized package held the VFX page content fixed, allowed 800 ms after each effect change and measured 90 pulse intervals per phase. It compared identical synthetic pointer sweeps with the lens off and on, plus an enabled stationary lens. A second launch reversed phase order. Every launch ran the original visual assertions afterward. Values below are forward/reverse observations from the isolated 60 Hz desktop. These controls measure steady motion after settling. The ordinary moving-lens numbers above include motion immediately after the unwarped capture.

| Driver | Lens off, moving p95 (ms) | Lens on, still p95 (ms) | Lens on, moving p95 (ms) | Moving pulses/s |
| --- | ---: | ---: | ---: | ---: |
| opengl | 17.72/16.99 | 17.28/17.11 | 19.06/19.11 | 59.80/59.80 |
| vulkan | 17.02/18.51 | 17.00/17.21 | 17.62/17.43 | 59.98/59.97 |

Logs and the checked native-library hashes are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-release-eVFhfCPk/lens-controls-OzmCSKup/verified.json`.

One further run per driver sampled changes in the private Weston's final output.
The test read 31 horizontal scanlines of the private 3120×2080 framebuffer
while the JavaFX application used its normal Wayland window. The probe marked the
90 pulse intervals of each phase using the same monotonic clock as the sampler.
All lines stayed constant with the effect disabled during motion and with the
effect enabled at rest. During enabled motion, lines at y=1504 and y=1568
each changed 87 times in 1.500 s on Vulkan and 81 times in 1.505 s on OpenGL.
At y=1504 the observed interval between changes had p95 of 19.7 ms on Vulkan
and 22.2 ms on OpenGL. The sampling interval itself had p95 of 4.0 and 4.9 ms
respectively during motion. These are counts of observable line changes on
the isolated compositor. Identical pixels and changes between samples can
reduce the count. Timing on the physical Windows monitor remains unmeasured.
The raw samples, phase logs and per-line results are in
`agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/lens-output-xrIZzBdK/`.

The published runtime also ran the original VFX drawer animation on the
isolated Weston display. The probe timed the menu button or cover action
from its handler, sampled the attached drawer's JavaFX layout position
each pulse and recorded the final output using the same scanline sampler.
The VFX animation graph specifies 300 ms. On 22 lines the open and closed
endpoints had distinct checksums which repeated across the complete
transitions. The output time below is the first sample after a line's last
mismatch with its settled endpoint. Each gesture contributed the median
across those lines. The table gives the median of four openings or three
closings per driver.

| Driver | Open, JavaFX layout settled | Open, output settled | Close, JavaFX drawer detached | Close, output settled |
| --- | ---: | ---: | ---: | ---: |
| Vulkan | 435 ms | 488 ms | 439 ms | 437 ms |
| OpenGL | 412 ms | 510 ms | 414 ms | 440 ms |

Attachment and sampled pixels can reach their endpoints on different pulses.
The opening sweep contained 5–7 distinct intermediate layout positions,
and closing contained 7–9. Each driver completed the original menu and
resource-cleanup checks. These measurements cover one launch per driver
on the private virtual display. The samples and the results for each
gesture are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/menu-output-xStRZTe8/verified.json`.

On the same published engine, a region copy before every eligible LCD text
node reduced OpenGL table-drag pulse p95 from 50.2 to 27.0 ms. Offscreen
passes during the 2,325-pixel drag fell from 6,205 to 1,704. Vulkan measured
39.1 and 40.7 ms respectively. Every mode passed the overlap comparison
against Prism's LCDBuffer reference. OpenGL menu opening slowed with
unconditional copies. The median time for all 22 scanlines to reach and hold
the default open endpoint was 569 ms, compared with 506 and 510 ms in the
two default launches. This measure requires a matching endpoint for at least
15 ms until the next action.

In the OpenGL table probe, 11,442 of 11,776 observed LCD samples used one
2016×928 target. Most menu samples used a 2560×1600 target, often with an
active 900×1598 clip. A candidate limited copies to unclipped text whose
padded rectangle occupied at most 1/32 of the target. Table p95 was 28.0 ms,
and the repeated open and closed menu endpoints remained stable. It passed
35 frozen navigation pages, ending with zero host-owned resources. Against
the same release, 33 page content regions matched pixel for pixel. Differences
on pages 18 and 19 were confined to regenerated table values. The A/B records
and visual comparisons are in `menu-lcd-LQax2BLn` and `lcd-small-region-wAmfOb6n/visual`
under the November 25 mesh publication archive.

The isolated source package with engine `906cf6d68fa4…` selected the small
copy automatically on Mesa D3D12 OpenGL. It measured 30.2 ms table p95 with
1,799 offscreen passes. Vulkan kept its existing path and measured 41.1 ms.
For the menu on Vulkan, four openings reached the common 22-line endpoint
in 462–497 ms and three closings in 409–445 ms. In the first OpenGL run,
gaps of 309 ms and 705 ms in the sampler prevent timing the first two
gestures. In a second run, three openings reached the endpoint in 495–528 ms
and three closings in 438–481 ms. Sampling stayed within 7 ms during the
final 698 ms opening interval, but neither the layout nor the sampled output
reached its open endpoint before measurement ended. The longest JavaFX pulse
in that sliding phase was 286 ms. Menu latency remains open. Per-action
sampling coverage and endpoint matches are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-release-MIuxEnnx/menu-coverage.json`.

The VFX drawer defines a 50 ms opening delay followed by 250 ms of sliding.
Its animation timer initializes on one pulse and starts an edge on a later
pulse. A listener on the drawer's layout property measured the first movement
after each open action. The window stayed at 1280×800 logical units at both
output scales. These medians come from one run per driver and scale. Four
openings contributed to layout and settling time. Three also had a confirmed
closed output immediately before the action, which allowed timing the first
sustained change across 22 sampled lines.

| Driver | Wayland scale | First layout movement | First sampled output change | Stable open output |
| --- | ---: | ---: | ---: | ---: |
| Vulkan | 1 | 135 ms | 184 ms | 461 ms |
| Vulkan | 2 | 147 ms | 242 ms | 490 ms |
| OpenGL | 1 | 170 ms | 238 ms | 530 ms |
| OpenGL | 2 | 136 ms | 267 ms | 558 ms |

Replaying the original VFX graph against the recorded pulse times predicted
the first intermediate layout position on pulse 7, 8 or 9 after each action.
Across all 16 openings the property change occurred within 0.14 ms of the
predicted pulse sample. VFX starts a timer for the 50 ms preparation edge and
then a second timer for the 250 ms slide. Each timer initializes on its first
pulse and starts its edge on its second. The replay is in
`animation-replay.json` beside the scale measurements.

At scale 2, the opening handler returned within 3 ms in all eight actions.
After the first change in layout position, the sampled output took another
107–158 ms to change on OpenGL and 94–99 ms on Vulkan in the three paired
openings per driver. Measurements are from the private compositor. Its
property events, pixel samples, device checks and individual gestures are in
`menu-scale-hjgdseUB/measurement.json` under the LCD release archive.

A separate OpenGL run on the B390 recorded the native host counters, Java Flight
Recorder events and Linux thread scheduling during 20 seconds of menu movement.
Across 29 opening and closing actions, 892 JavaFX pulses had a 43.58 ms p95
interval and a 73.62 ms maximum. All seven intervals above 50 ms coincided
with the JavaFX application thread waiting for its next event, with no recorded
GC pause overlapping them. During the longest gap, an overlapping 67.1 ms
host interval included 39.6 ms of draw/synchronization and 8.8 ms of texture
handling. Four of seven native main-thread samples inside the gap observed a
synchronous WSL graphics request. Sampling cannot partition driver and device
time. The earlier 286 ms stall did not recur in this recording. Trace data
and the per-gap join are in `menu-stalls-rYZR3230/attribution.json` under
the LCD release archive above.

A second scale-2 measurement joined admitted JavaFX window publication
sequences with the first Godot frame-post-draw callback reporting that
sequence or later. At ordinary admission a median of three earlier window
publications had yet to reach that callback on both drivers. In a temporary
comparison the Prism thread waited after each publication for that
acknowledgment. The published runtime and VFX graph were identical in the
two modes. The callback measures host progress. The final two columns
come from independent compositor scanline samples after the opening action.

| Driver | Mode | Sliding publications | Admission to post-draw p50 | p95 | First output change, median | Stable open output, median |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Vulkan | ordinary | 182 | 55 ms | 153 ms | 275 ms | 580 ms |
| Vulkan | wait | 188 | 17 ms | 44 ms | 247 ms | 476 ms |
| OpenGL | ordinary | 186 | 65 ms | 183 ms | 288 ms | 634 ms |
| OpenGL | wait | 159 | 24 ms | 54 ms | 222 ms | 504 ms |

These are single launches per driver and mode. The wait was diagnostic.
The first output change was measurable on three openings per launch, and
the stable output on four. Earlier launches of the ordinary package also
had faster endpoints than these ordinary runs. The raw sequence traces
and gesture results are in `menu-queue-dvIGBPJo/` under the LCD release archive.

A separate native build varied how many queued batches publishing a window
could await consumption. Other command batches retained the normal capacity.
At limits of 1, 2 and 3, median stable opening times were 500, 566 and 478 ms
on OpenGL and 585, 565 and 566 ms on Vulkan, respectively. These six launches
showed no consistent advantage from lowering the admission limit. The
packaged engine retains its original queue. The comparison and build records
are in `menu-present-limit-ICR66crd/comparison.json`.

On the scale-2 Weston fixture the Vulkan menu with a 120 FPS cap and VSync
disabled reached stable open output in a median 440 ms, compared with 577 ms
in the same series at ordinary pacing. OpenGL measured 557 and 482 ms,
respectively. Run `scripts/profile-vfx.py menu --driver vulkan --host120`
inside the isolated Linux Wayland session to exercise this option. The
scale-1 standalone JAR tests on labwc used actual compositor pointer events.
There the timing bounds from ordinary and 120 FPS launches overlap. The
compositor grab intervals bound the time of the last change in the sampled
region. Both launch modes reproduced the same settled appearance within
each run. These measurements support keeping pacing selectable. The fixture
results are in `menu-host-pacing-tcrGglPW/comparison.json`. The JAR observations are in
`menu-jar-input-CZcigH7P/input-output.json` in the same archive.

Wayland traces of those six scale-1 JAR launches also identify which buffers
Mesa submitted. In the first 500 ms after each of 48 button releases, all 836
buffer commits on the VFX toplevel used 1280×800 shared-memory buffers and
marked the entire buffer as damaged. Each menu opening had 3–6 buffer commits
within 100 ms of the client receiving the release. The first visible change
came later. At ordinary pacing, the median bounds from pointer release to
that change were 176–216 ms and 183–221 ms on the two Vulkan launches, and
244–288 ms and 255–305 ms on OpenGL. Comparing the settled open image with
the closed image, 81.3–81.4% of window pixels changed by more than four levels
in at least one RGB channel. This includes the cover across the content. A
surface commit alone cannot identify which menu state reached the output.
The per-action counts are in `menu-jar-input-CZcigH7P/presentation.json`
beside the input and pixel observations.

On the same packaged engine and virtual seat, a second set of six launches
used a 3120×2080 output at scale 2. Each of 48 clicks reached the client.
The screenshots showed a 2560×1600 physical window (1280×800 logical).
On four scanlines through the open drawer, the start of the uniform cover
was at 450.5 logical pixels from the left edge of the window, versus 451
at scale 1. All four openings and closings per launch reproduced their
settled states. The median grab took 35.9 ms at scale 2 and 17.2 ms at
scale 1, which widens the measurement bounds at the higher scale.

| Scale-2 packaged VFX JAR | Ordinary open, launch 1 | Ordinary open, launch 2 | Open, VSync off with 120 FPS cap |
| --- | ---: | ---: | ---: |
| Vulkan Mobile | 475–560 ms | 456–533 ms | 458–531 ms |
| OpenGL Compatibility | 635–717 ms | 576–678 ms | 600–674 ms |

Entries bound the median time from pointer release to a stable open drawer,
with four gestures per entry. The two driver ranges at ordinary pacing
separated on this virtual desktop. For each driver the capped interval
overlapped its ordinary intervals. The corresponding captures, protocol
counts and cross-scale geometry are in `menu-jar-scale2-XyHKP2ht/` under
the LCD release archive.

A private GLES3 engine on the same GPU compared shader-based copies of the
LCD background with same-size framebuffer blits. The blit was limited to
RGBA8, single-view, single-sample targets without mipmap generation or
overridden attachments. The OpenGL blit, LCD overlap and render-target
fixtures passed on the experimental engine. All six menu launches matched
the reference open and closed output at the 22 sampled lines.

| OpenGL copy policy | Median settled opening, shader / blit / shader repeat | Median settled closing, same order |
| --- | --- | --- |
| Published region selection | 555 / 564 / 577 ms | 462 / 485 / 495 ms |
| Request region copies for clipped text too | 624 / 549 / 624 ms | 534 / 475 / 498 ms |

At ordinary region selection, the last counter sample in all three runs
covered 9,984 copies averaging about 3.52 million pixels. CPU time issuing a
copy fell from 10.1–10.4 µs to 1.6 µs with framebuffer blits. Requesting region
copies for clipped text averaged 2.04 million pixels per copy. A blit recovered
most of the extra opening time of that policy. The combined result was only
6 ms faster than the faster ordinary control, with one blit trial per policy.
The published default is unchanged. Counters and per-action timing comparisons
are in `menu-copy-region-aXmcA4kn/result.json` in the LCD release archive.

A second diagnostic used JavaFX's node cache on the sliding drawer of the
original Intro. On OpenGL, the scale-2 fixture recorded 60.1 JavaFX pulses
per second during sliding, versus 42.7 and 41.7 in the two uncached controls.
Sliding pulse p95 was 20.0 ms with caching and 41.8 / 46.0 ms without it.
The four cached openings had a median of 14 intermediate layout positions,
versus 6 and 6.5. The animation graph and duration stayed the same.

The standalone comparison changed only the Intro class in the 8,221-entry
JAR. Each driver ran twice at scale 2 with real compositor clicks. All 32
open and closed drawer crops in the candidate matched the reference
pixel-for-pixel. Both drivers also scrolled to the Blackhole checkbox,
enabled the lens, moved it, disabled it and recovered the original pixels.
Across eight OpenGL openings per setting, the median number of distinct
intermediate screenshots rose from 3 to 4.5. Bounds for the median first
visible change moved from 424–524 ms to 359–440 ms. The stable opening
bounds moved from 610–696 ms to 638–731 ms. Vulkan also produced more
intermediate images during opening, with no improvement in the time to
reach stable output. The node-cache change remains experimental. Optical
samples and JAR membership are in `menu-cache-jar-Xgrr5Be0/`, with the
fixture controls in `menu-drawer-cache-OWG4vQik/` under the LCD release archive.

A separate Weston run observed the private compositor output directly.
It used actual seat button events on the Wayland window and verified all
presses and releases in the client's protocol trace. During each gesture the
observer read screen memory about every 3 ms. Five scanlines from the title
and welcome text were used to locate the window, with at least three matching
the reference at a common origin. Across eight launches the largest sampling
gap was 11.2 ms. Drawer content crops matched across the two JARs for all
32 paired endpoints. The table pools eight gestures per driver and setting.
Times are measured from release injection to a sustained pixel change or to
the final stable sampled appearance.

| Scale 2 | First opening change | Stable open | Stable closed | Distinct intermediate samples, open / close |
| --- | ---: | ---: | ---: | ---: |
| OpenGL, ordinary | 264–268 ms | 482–485 ms | 390–395 ms | 6 / 6 |
| OpenGL, cached drawer | 214–217 ms | 489–492 ms | 436–440 ms | 8 / 11 |
| Vulkan, ordinary | 266–270 ms | 475–478 ms | 435–439 ms | 5.5 / 7 |
| Vulkan, cached drawer | 222–225 ms | 486–490 ms | 448–452 ms | 8 / 12 |

Caching made the opening visible sooner and produced more intermediate
states. The normal JAR completed closing sooner on both drivers. Measurement
bounds, individual clicks and endpoint captures are in `menu-seat-calibrated-Jo2mb7YQ/`
under the LCD release archive.

A private menu experiment compared consecutive writes to the same mask
texture and rectangle. Of 11,040 sampled alpha patches, 7,883 had identical
bytes. Suppressing identical Prism mask-atlas uploads in the experimental
classpath reduced texture patch input at host tick 1,080 from 714 MB to
132 MB on OpenGL and from 753 MB to 133 MB on Vulkan. The sliding-phase
JavaFX p95 changed from 45.1 to 41.2 ms on OpenGL and from 46.9 to 40.8 ms
on Vulkan in one pair per driver. Independent framebuffer sampling still
measured 479–580 ms from opening the menu to stable OpenGL output and
464–529 ms on Vulkan. On OpenGL the first intermediate drawer position was
sampled 155–193 ms after the opening action. The optical results do not
establish a shorter visible transition. The trial stayed outside the
published package. Its counters, layout samples and endpoint comparisons
are in `menu-mask-trial-Jz901ant/{result,motion}.json` in the LCD release
archive.

Four OpenGL repeats used geometry-cache capacities of 1,024, 4,096, 4,096 and 1,024, respectively. All four moved the table by 2,325 pixels in 96 pulses. The two runs with exactly 5,820 offscreen passes provide the closest comparison. Increasing capacity cut geometry uploads from 9,831 to 3,096, while time handling the upload commands changed from 3.44 s to 3.41 s and pulse p95 changed from 229.2 ms to 237.7 ms. The remaining two runs measured 251.7 ms at 4,096 entries and 228.9 ms at 1,024 entries. These results support retaining the 1,024-entry default. The four logs and per-run counts are in `table-cache-ab-omTrJJfn/` under the same release archive.

Sampling the JVM process with Linux user-mode CPU-clock events during one five-second sliding-menu phase also captured copies below the graphics driver. On Vulkan, 34 samples showed libc's memory-copy routine below dzn and Godot's Vulkan queue submission/presentation call. On OpenGL, 22 samples showed the same routine below Mesa EGL and `RendererViewport::draw_viewports`. In a separate protocol trace on private labwc, Mesa EGL created a 1152×648 shared-memory buffer and attached that exact buffer to the window surface. Godot identified the B390 as its OpenGL rendering device in the same run. These observations distinguish window presentation from the JavaFX-to-Godot draw-command path. CPU samples describe time executing on a CPU and cannot measure GPU stalls or predict timing on the Windows desktop. Records are in `native-drag-profile-mzKdPr6k/` and `owned-vstage-gLGPe6s1/secondary-opengl/app.log` under the same release archive.

### VFX animation timing on Linux Wayland

On the Intel Arc B390 the original VFX animation timer spent its first pulse recording a timestamp, then reset the start time on its second pulse. A late transition also subtracted an overflow measured in milliseconds from a nanosecond timestamp. The corrected timer starts the first edge immediately and advances the timestamp by each completed edge’s duration. A deterministic JavaFX application-thread test uses a 50 ms edge followed by a 250 ms edge. It checks interpolation, both endpoints, late pulses and reversal. The original runtime failed the first-pulse assertion.

In ten isolated scale-2 Weston launches the probe sent real seat input and sampled the compositor output about every 3 ms. Each launch opened and closed the menu four times. The table gives median bounds on the first visible movement and the median number of distinct intermediate positions. Each driver had one baseline launch and two launches for each changed configuration.

| Driver and configuration | First opening movement | First closing movement | Intermediate positions, open / close |
| --- | ---: | ---: | ---: |
| OpenGL, baseline | 266–270 ms | 156–160 ms | 5 / 6.5 |
| OpenGL, corrected timer | 249–254 ms | 145–149 ms | 5.5 / 7 |
| OpenGL, corrected timer and cached drawer | 175–179 ms | 187–190 ms | 7 / 11.5 |
| Vulkan, baseline | 270–274 ms | 168–171 ms | 6 / 7 |
| Vulkan, corrected timer | 233–236 ms | 142–146 ms | 5.5 / 7 |
| Vulkan, corrected timer and cached drawer | 200–204 ms | 145–148 ms | 8 / 12 |

The first Linux Godot Intro implementation cached the whole moving drawer. Both drivers showed more intermediate positions with the cache, and settled drawer pixels matched the baseline. OpenGL took about 30 ms longer to show the first closing movement in this comparison. The probe’s output timing applies to its private compositor. Measurements and individual launches are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/menu-graph-time-NUZN2ztk/verified.json`.

The source-built VFX JAR subsequently passed the deterministic timing test and smoke launch on both drivers. In four real menu openings per driver, its first visible movement took 176–180 ms on Vulkan and 167–171 ms on OpenGL. Closing first moved at 155–158 ms and 186–190 ms respectively. The median counts of intermediate opening/closing positions were 8.5/12 and 7.5/11. The raw samples are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-timeline-release-vJsyDaug/validation/menu/`.

### Caching the scrollable drawer content

Two comparisons on isolated Weston at scale 2 kept the corrected VFX timer and animation durations fixed. Both used the same real pointer gestures and sampled final compositor output. Each row summarizes eight opens and eight closes across two launches. Times are median bounds in milliseconds. Caching the navigation VBox leaves the enclosing scroll pane and drawer background to render separately.

| Driver and cache location | First opening movement | Stable open | First closing movement | Stable closed | Intermediate positions, open / close |
| --- | ---: | ---: | ---: | ---: | ---: |
| OpenGL, whole drawer | 183–188 | 464–469 | 186–189 | 411–414 | 7.5 / 10.5 |
| OpenGL, content VBox | 181–185 | 401–406 | 98–102 | 383–386 | 11.5 / 15 |
| Vulkan, whole drawer | 190–193 | 449–453 | 155–158 | 396–400 | 8 / 11.5 |
| Vulkan, content VBox | 192–197 | 428–433 | 108–111 | 406–409 | 9 / 11 |

The Linux Godot Intro uses the content VBox cache. OpenGL started closing about 88 ms earlier and showed more intermediate positions in both directions. Vulkan also started closing earlier, with a roughly 10 ms longer median time to settle closed. Every sampled endpoint matched the preceding source-built JAR pixel for pixel in the drawer comparison region. In separate launches the real checkbox changed on both drivers, moving the active lens changed the image, and switching it off restored the original pixels. The combined measurements and dynamic-control results are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-geometry-release-MrQkS9GG/menu-repeat-FLvQA7Bz/verified.json`.

The subsequent source-built Intro JAR produced the following independent measurements at scale 2. The table moved by 2,325 physical pixels in 96 JavaFX pulses on each driver. The lens profile used 90 intervals and passed its visual assertions. The menu probe used four physical openings and four closings per driver. The table and lens values measure JavaFX pulse intervals. The menu bounds measure changes in final compositor output.

| Driver | Table drag p95 | Moving lens p95 | First menu opening movement | First closing movement | Stable open / closed |
| --- | ---: | ---: | ---: | ---: | ---: |
| Vulkan | 38.2 ms | 18.2 ms | 205–210 ms | 111–115 ms | 434–437 / 406–409 ms |
| OpenGL | 35.6 ms | 20.8 ms | 161–165 ms | 107–112 ms | 403–406 / 395–401 ms |

The two extra demo JARs matched the preceding geometry-fix build in all 8,586 and 8,585 file entries respectively. Only two Intro class entries differed in the 7,874-entry VFX JAR. The source-built Intro and the diagnostic content-cache JAR had identical disassembled Intro instructions. Results are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-content-release-1JbNFKJu/verified-tests.json`.

The Intel Arc B390 run with engine `ace7814e1e52…` and the shutdown-corrected Toolkit used a 3120×2080 isolated Weston desktop at scale 2. The table and lens columns measure JavaFX pulse intervals. The menu columns give median time from pointer-button release to the first visible change in the sampled drawer region over four openings and four closings per driver.

| Driver | Table drag p95 | Moving lens p95 | First opening movement | First closing movement |
| --- | ---: | ---: | ---: | ---: |
| Vulkan | 41.8 ms | 17.7 ms | 199–202 ms | 113–117 ms |
| OpenGL | 26.8 ms | 21.5 ms | 176–179 ms | 96–101 ms |

The opened and closed drawer regions matched the preceding content-cache release pixel for pixel across all 16 observations. Raw intervals and comparison results are in `wayland-toolkit-publication-QI3DyI7e/performance-verified.json` and `menu/endpoint-comparison.json` under the LCD publication archive.

### Horizontal table drag without VFX node caching

The 50-row, seven-column Intro table ran on the B390 in private Weston at
scale 2. Each direct run used the outer horizontal viewport, 96 JavaFX pulse
intervals and 1,500 logical pixels of total movement. The comparison uses
the same uncached VFX classes. Pulse intervals measure the application clock.

| Horizontal drag p95 | Vulkan before | Vulkan after | OpenGL before | OpenGL after |
| --- | ---: | ---: | ---: | ---: |
| Direct drag | 156.8–163.9 ms | 20.8 ms | 72.9 ms | 26.0 ms |
| Synthetic pointer through the input pipeline | 101.7 ms | 26.4 ms | 75.9 ms | 31.2 ms |
| Moving Blackhole lens | 166.8 ms | 31.6 ms | 114.8 ms | 40.4 ms |

The earlier Vulkan synthetic input run moved 1,375 pixels; the other input
runs moved 1,500. In the ordinary Vulkan direct drag, full geometry uploads
fell from 28,905–28,941 to 409 and offscreen passes from 15,434–15,445 to
4,896. The host recorded 79 backpressure events before and zero afterwards.
The rebuilt SDK, local platform JAR and VFX Demo JAR contained identical
copies of the five changed graphics classes.

A separate packaged-JAR comparison injected six horizontal strokes through
a private labwc seat at scale 1. The median of the six stroke-level p95 gaps
between visible table movements fell from 161 to 48 ms on Vulkan and from
203 to 53 ms on OpenGL. Counts of matched movements during the strokes rose
from 29 to 114 and from 37 to 95 respectively. One Vulkan stroke still had
a 152 ms p95 gap. These measurements sample the private compositor output.
The sampler can miss frames, and Windows monitor latency is outside the
measurement. A deterministic scale-2 table gave identical RGB crops on both
drivers at offsets 0, 213, 470.25 and back at 0 logical pixels.
Run data, pixel comparisons and compiler logs are archived in
`agentdir/artifacts/table-drag-axis-iHbKZuXw/`.

### Earlier VFX column-cache experiment with the Blackhole effect

An experiment enabled JavaFX node caching for bounded, vertically scrollable
VTableView columns on Linux with Prism-Godot. The demo currently uses ordinary
uncached columns. The following historical figures compare that experiment
with its uncached control before the horizontal drag renderer changes.

The 50-row, seven-column Intro scene ran on a private Wayland desktop at
scale 2. Each run moved the table **vertically** 2,325 pixels in 96 JavaFX
pulses. Each range covers two launches with an identical gesture.

| Renderer and driver | Plain drag, uncached | Plain drag, cached | Drag with lens, uncached | Drag with lens, cached |
| --- | ---: | ---: | ---: | ---: |
| mobile / Vulkan (dzn) | 40.5–41.7 ms | 17.9–18.1 ms | 163.1–164.3 ms | 17.9–18.5 ms |
| gl_compatibility / OpenGL (D3D12) | 27.9–31.1 ms | 23.2–23.7 ms | 66.4–70.5 ms | 24.5–24.8 ms |

With the lens active, host offscreen draw calls per run fell from about 22,700 to 2,600 on Vulkan and from 18,450 to 2,300 on OpenGL. Queue backpressure fell from 215–225 and 30–34 events, respectively, to zero. Vulkan command encoding fell from 5.03–5.16 seconds in aggregate to 0.076–0.088 seconds. An independent run toggled the actual menu checkbox and moved the lens with every drag event. Its p95 was 20.1 ms on Vulkan and 28.7 ms on OpenGL. Both drivers passed the table edit and lens restoration probes.

The packaged JAR also ran on private labwc at scale 1. A virtual pointer made six 216-pixel strokes per launch while a compositor capture tracked matching scanlines in the table. Across two launches, the median of the six stroke-level p95 gaps between visible movements fell from 46.0–52.8 ms to 20.2–24.9 ms on Vulkan, and from 50.5–55.4 ms to 36.2–44.8 ms on OpenGL. Two strokes in the second baseline Vulkan run moved 210 pixels, and one had a 285 ms gap. All optimized strokes traveled 216 pixels. These intervals measure the private compositor output. The Windows monitor and its final presentation latency are outside this measurement.

At the initial scroll position, cached and uncached table regions matched pixel for pixel on both drivers. At an offset of 470.25 logical pixels (half a physical pixel at scale 2), sampling the cached texture changes edge antialiasing. About 1.1–1.2% of compared pixels differed by more than 16/255 in any channel. Disabling the cache restored the original image on both drivers. A 500-row stress fixture traveled 17,856 pixels in 192 pulses using the normal uncached fallback. Its p95 was 25.7 ms on Vulkan and 27.9 ms on OpenGL. An experimental moving cache band increased p95 to 762 and 377 ms respectively and was discarded.

A separate offscreen Vulkan program ran the same SPIR-V radial warp on the same 2560 × 1600 input and B390 under Windows native Vulkan and WSL dzn. Two launches per platform each measured 120 dispatches with the warp active. GPU timestamp medians were 0.36–0.39 ms on Windows and 0.30–0.34 ms on WSL. Submission through completion took 0.74–0.79 ms and 0.70–0.79 ms, respectively. The microbenchmark isolates texture sampling and arithmetic. It excludes Godot scene composition, render-target changes, image transfer to a compositor and WSLg presentation. The full application reproduced its stalls with WSLg isolated, and reducing repeated table rendering relieved them under both drivers.

The release profiles, compositor frames, fractional-position comparisons, 500-row control and paired Windows/WSL GPU measurements are archived under `agentdir/artifacts/table-lens-AAnp4078/`. The successful OpenGL baseline retry is recorded separately in `release/results`.

### Direct WSLg presentation during a table drag

The same 50-row VFX scene ran directly on WSLg 1.0.73 and on isolated Weston. Each run used native Wayland, the B390, a 1280 × 800 logical window at scale 2, the real moving lens, and 96 application-driven drag steps covering 2,325 pixels. The instrumented probe requested Wayland presentation feedback on the main surface before each step. It used the compositor's clock to measure time until presentation of the next submitted surface update. The callback can correspond to previously queued drawing. The compositor supplied software timing flags in all runs, so the measurements do not identify the physical scanout time of the pixels changed by a particular event. [Wayland presentation-time protocol](https://wayland.app/protocols/presentation-time)

Each range below contains two launches in opposite comparison orders. Pulse p95 describes drag cadence. The median in the last column measures the time from the step marker to the next presentation timestamp among requests that received a presented result.

| Driver | Desktop | Pulse p95 (ms) | Median time to next presentation (ms) |
| --- | --- | ---: | ---: |
| Vulkan, automatic pacing | isolated | 18.4–19.9 | 28.6–29.4 |
| Vulkan, automatic pacing | WSLg | 19.2–35.4 | 39.1–39.4 |
| OpenGL, automatic pacing | isolated | 29.6–31.0 | 23.9–24.3 |
| OpenGL, automatic pacing | WSLg | 23.0–29.9 | 23.5–24.1 |
| Vulkan, keep initial VSync | isolated | 28.6–33.6 | 25.5–25.7 |
| Vulkan, keep initial VSync | WSLg | 25.0–30.9 | 21.5–22.7 |

Under automatic pacing, the paired Vulkan median was 9.7–10.9 ms longer on WSLg. Godot logged that the host tried CPU pacing and the WSLg Vulkan swapchain fell back to enabled VSync. Two process-local control runs per desktop used `GODOT_JFX_VSYNC_FALLBACK=0` to retain the initial VSync. In those pairs the WSLg median was 2.8–4.2 ms shorter than isolated Weston. The observed difference depends on the application's pacing policy and the compositor path. These variants share the same dzn driver. The OpenGL median differed by less than 0.5 ms in both pairs. One WSLg OpenGL launch counted 12 unfocused drag ticks, while the second launch remained focused.

One previous-version run on each path also confirmed the table optimization under direct WSLg. Pulse p95 for the previous classes with the moving lens reached 149.7 ms on Vulkan and 77.4 ms on OpenGL. The previous WSLg OpenGL run recorded 69 unfocused ticks. All 16 runs passed the fixture assertions. Of 1,536 feedback requests, 18 were explicitly discarded by the compositor and 1,518 produced presentation timestamps. The per-step evidence and run-level outcomes are in `agentdir/artifacts/table-lens-AAnp4078/direct-wslg-mvZy0bsu/summary.json` and the adjacent run logs.

### WSL Vulkan pacing comparison with the moving table lens

Direct WSLg Wayland launches through `scripts/wsl-gpu.sh vulkan` retain initial VSync by default. Set `GODOT_JFX_VSYNC_FALLBACK=1` to repeat the automatic pacing comparison. The wrapper applies this default only when the selected Wayland connection leads to the WSLg compositor.

Four launches per policy ran on the actual WSLg desktop with the identical B390 Vulkan engine, 50-row Intro table and moving lens. Each launch recorded six drag sweeps, 192 JavaFX pulses and 4,650 pixels of displacement at 1280 × 800 logical pixels and scale 2. The run order was old/new, new/old, old/new, new/old. All eight runs remained focused. All four old-policy runs logged the automatic CPU pacing switch.

| Measurement | Automatic fallback | Keep initial VSync (direct WSLg Vulkan default) |
| --- | ---: | ---: |
| Drag marker to next Wayland presentation, median | 39.62 ms | 22.68 ms |
| Drag marker to next Wayland presentation, p95 | 40.57 ms | 31.48 ms |
| Interval between distinct presentation timestamps, p95 | 18.20 ms | 27.31 ms |
| Presentation intervals over 25 ms | 1 / 764 | 67 / 763 |
| Presentation intervals over 40 ms | 0 | 0 |
| Feedback requests explicitly discarded by WSLg | 0 / 768 | 0 / 768 |

Timing rows show the median of the four run-level statistics. Counts cover all four runs. One pair of new-policy feedback requests shared a presentation timestamp, so that policy has one fewer distinct interval. At the reported 60 Hz refresh rate, 25 ms corresponds to 1.5 refresh periods. Keeping initial VSync reduced typical presentation wait by about 17 ms, with less regular motion in this workload. The feedback measures the next surface update reported by WSLg. Measuring a specific input through to physical scanout requires additional instrumentation. Raw timestamps and per-launch outcomes are archived in `agentdir/artifacts/wslg-vulkan-pacing-GS4EZR2d/`.
