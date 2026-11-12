# Acceptance status

## Full post-baseline cleanup audit — 2026-11-13

The follow-up inventory is `artifacts/dead-code-audit/audit.json`, with source
paths and hashes for 477 root source/test/script entries, 20 Godot files,
64 JFX files and the four VFX integration files. It records the baseline and
current heads, dynamic entry points, removed code and reasons for retention.
VFX integration is compared after the explicit revert of its unrelated Tauri
port; restored upstream business code is not treated as new host code.

The broader review includes inline header methods, field reads/writes, protocol
consumers, shader generation, inherited dispatch and diagnostic entry points.
It found and removed an unwritten `window_gpu_time_us` field and unused setter,
the redundant inherited offscreen-timing getter, and the full-shadow input branch
of the region-upload API (all callers supply packed patches). The host no longer
reports a fabricated zero `window_gpu_us`; transition GPU samples still come
directly from the actual window viewport. Both storage backends retain the
packed-patch path and unsupported-layout fallback.

The shared layer compositor is live in primary and native secondary window
presentation, despite its old legacy-only comment. Its implementation and
protocol diagnostics are retained. Public Godot extensions, JavaFX overrides,
COM callbacks, JNI callbacks and generated shader entry points are not dead
merely because they lack a direct call in the defining file.

Editor and Runtime source builds pass after the storage-API cleanup. RGBA8 and
RGBAF partial updates pass on mobile/OpenGL; Viewport-state and batch-boundary
tests pass on mobile. Protocol validation also passes. Profiled table scrolling
and all 68 transitions pass with a temporary 8192-element timestamp pool; the
default 256-element pool failed with timestamp-capacity errors (preserved in
`artifacts/dead-code-audit/table-default-timestamp-limit.log`). The temporary
`override.cfg` was removed afterward; error checks were not relaxed.

The transition fixture still reports actual window GPU samples (1691 samples,
about 512 us average in this diagnostic run). Offscreen GPU samples remain zero
on the default direct-pass path: its timestamp mapping is cleared by the regular
viewport draw before results are consumed. This is a measurement limitation,
not evidence of zero GPU cost or an unused field; the non-direct diagnostic
path still uses the engine's normal viewport measurement lifecycle. These
instrumented runs do not establish performance acceptance.

## Removal follow-up audit — 2026-11-13

Compared the host and submodule additions against root baseline
`9d1f2a2be0744d05ff9aed94e6c116de6a391d09` (Godot `7be59b463a`,
JFX `73d8b63bab`). The deleted RD spike left an unused
`benchmark_offscreen_cycle` host method and ClassDB binding; both are now removed.
Safe-only offscreen drawing no longer needs two callback wrappers or a stored
timing result. Packed region uploads now call texture storage synchronously,
without a Callable dispatch wrapper. Obsolete headers and separate-mode trace
descriptions have been removed as well.

Call-site review included JNI registration, ClassDB bindings, Java callers and
test fixtures. A second audit additionally removed unused `clipboardWriteText`
and `clipboardHasText` Java/JNI entry points, plus the obsolete render-target
`draw_prism_mesh` wrapper/binding. Clipboard writes and format queries continue
through the full-format APIs; actual mesh draws use the instance-aware method.
All 34 remaining native declarations have registrations and callers, including
Java method references. The 493-file tracked host/test/script/document scan found
no orphan Java reference probes or Godot test scripts. No further unreferenced
host methods or Godot Java adapter methods were identified in this review.
Godot's remaining region-upload implementation, Viewport drawing,
profiling hooks and window/resource-lifetime fixes have current consumers and
are retained. Historical RD measurements below remain historical records.

After the JNI cleanup, the source JFX SDK, Editor and Runtime rebuilds pass;
`javap` confirms the removed JNI methods are absent from the SDK. Clipboard
encoding tests pass without accessing the system clipboard, and Demo smoke,
Viewport-state texture tests and Runtime window controls pass with the rebuilt
Java/native pair. This does not re-establish end-to-end system clipboard
acceptance or constitute a formal proof that all code is reachable.

Source Editor and Runtime rebuilds pass. Render-target and partial-texture tests
pass on mobile and OpenGL; Viewport-state and both batch-boundary checks pass
on mobile. Runtime window controls and video playback, and unsupported-mode
rejection pass. The safe/mobile frame trace and its Python analysis complete:
59.999 pulses/s, zero unfocused intervals. These CPU timings are not physical
display FPS. Evidence uses the corresponding `artifacts/logs/render-targets-*`,
`queued-texture-update-*`, `vfx-window-controls-mobile-safe-runtime.log`,
`media-video-mobile-runtime.log`, `render-mode-rejection.log`, and
`vfx-frame-benchmark-safe-trace.log` / `.analysis.json` files.

## Viewport + safe consolidation — checked 2026-11-13

The custom JavaFX RD-direct backend, translator, capability JNI query, build
option and dedicated probes have been removed. Separate-only host fences,
queued texture proxies and Windows GL/render-worker ownership patches have
also been removed. Godot's own RenderingDevice, renderers and shared texture
region-upload implementation remain. Host startup and target initialization
reject separate rendering. The command protocol and JavaFX thread ownership
remain unchanged.

Source Editor, Runtime, JFX SDK and Media builds pass. Current Editor tests pass
for Demo startup/close, texture revisions (including partial uploads and batch
boundaries), render-target lifecycle, shader-cache limits, Node shaders, ripple,
blackhole, transformed GodotView, native windows and immediate-close handling.
Viewport target/cache/shader/ripple checks include both mobile and OpenGL.
Editor/Vulkan and Runtime/OpenGL Robot fixtures pass. Media plane validation,
Editor/Runtime video playback and controls, Runtime window controls, Runtime
immediate-close handling and 12-cycle Stage churn pass. Effects match the native
D3D reference on Editor/mobile and Runtime/OpenGL. VFX all-page navigation, LCD overlap comparison and menu-render progress pass.
The revised GPU/host profiling wrapper also completes after removing the
backend-specific Vulkan wait hooks.
Menu profiling reports 59.903 pulses/s with menu-open ripples and 59.996 pulses/s
during repeated sliding, with zero unfocused intervals in those phases; this is
CPU pulse timing, not physical display FPS.

Clipboard end-to-end exchange was refused before writes because the existing
clipboard contains an unverified `DataObject` format. Its contents were not
cleared or replaced. Snapshot-guard and clipboard-ownership unit tests pass;
they do not establish current end-to-end clipboard exchange acceptance.

Both Editor and Runtime module archives contain none of the deleted RD source
members, and `javap` confirms the SDK no longer exposes `isRDDirectCompiled`.
All PowerShell scripts parse; source searches find no obsolete RD backend symbols
or environment switches in the host/JFX implementation and tests. The sole
separate launch in scripts is the explicit rejection fixture.

Evidence: `artifacts/logs/godot-editor-javafx.log`, `godot-runtime-javafx.log`,
`jfx.log`, `jfx-media-native.log`, `queued-texture-update-mobile-safe*.log`,
`render-targets-*-safe.log`, `shader-cache-*-safe.log`, `node-shaders-*-safe.log`,
`vfx-blackhole-mobile-safe.log`, `vfx-ripple-*-safe.log`,
`godot-view-mobile-transform.log`, `robot-mobile-safe.log`,
`robot-gl_compatibility-safe-runtime.log`, `media-planes-mobile.log`,
`media-video-mobile*.log`, `effects-mobile.log`, `effects-gl_compatibility-runtime.log`,
`vfx-intro-mobile-safe-all-pages.log`, and `vfx-menu-mobile-safe-default.log`.
The clipboard refusal is the PowerShell guard result, not an old clipboard log.
The removed-mode rejection fixture uses OpenGL: it verifies the host refuses
separate before starting the JVM and releases its resources. A Vulkan/separate
negative attempt reached the expected rejection but also exposed the upstream
RenderingDevice shutdown-thread error after removal of the separate-only fix;
that unsupported engine configuration is not claimed to have clean shutdown.


> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


## Configurable tool paths — checked 2026-11-12

MSYS2 now uses `MSYS2_ROOT`, falling back to `D:\msys64`.
JFX and native test helpers use `VSINSTALLDIR`, falling back to the standard
VS 2022 Community directory under Program Files. Explicit PowerShell parameters
still take precedence. VS paths are normalized for the vendor setup scripts;
modified process environment variables are restored. Java retains the
`JAVA_HOME` defaults described below. The clipboard fixture's real checkout
path was replaced with matching synthetic data in Java and PowerShell.

JFX and native Media incremental builds pass with environment-selected paths,
including a VS path containing spaces, forward slashes and no trailing separator;
environment restoration checks pass. The protocol native test passes with both
the default VS location and an environment override. The clipboard ownership
native test passes; the changed Java clipboard observer compiles. No system
clipboard exchange or physical drag test was run. VFX `-Smoke` passes on
mobile/safe; this is bounded startup/close coverage, not full regression acceptance.
PowerShell syntax and `git diff --check` pass; parameter-default checks cover
unset and overridden MSYS2/VS variables without executing physical fixtures.

Logs: `artifacts/logs/jfx.log`, `jfx-media-native.log`,
`tool-path-protocol.log`, `tool-path-protocol-default.log`,
`tool-path-clipboard-ownership.log`, and `vfx-demo-mobile-safe.log`.

## JAVA_HOME script defaults — checked 2026-11-12

Build/run/test PowerShell scripts now default `-Jdk` to `JAVA_HOME`; the two
JNI-header native `.cmd` fixtures use the same environment variable. No script
contains the former fixed JDK installation path. The existing local jdkman
configuration selects Temurin 25.0.3+9 with `.java-version`; both `java -version`
and `javac -version` confirm 25.0.3. This file alone does not configure an
uninitialized shell; see build-windows.md for environment setup.

Without an explicit `-Jdk`, sequential incremental source builds pass for
Godot Editor/Runtime (JavaFX module, RD compiled in), JFX SDK, native Media and
VFX. VFX `-Smoke` and local Media video playback/control/cleanup pass on the
Editor with Vulkan/mobile and safe rendering. Both JNI native fixtures pass,
and the test sequence preserves `JAVA_HOME`. This is not a clean rebuild,
a full regression run, or physical audio/device acceptance; Runtime was built
but not launched in this check.

Evidence in `artifacts/logs`: `godot-editor-javafx-rd-yes.log`,
`godot-runtime-javafx-rd-yes.log`, `jfx.log`, `jfx-media-native.log`,
`vfx-build.log`, `vfx-demo-mobile-safe.log`, `media-video-mobile.log`,
`java-home-clipboard-ownership.log`, and `java-home-dnd-drag-image.log`.
PowerShell parsing and `git diff --check` also pass.

## RD-direct build option — checked 2026-11-12

The JavaFX module now supports `javafx_rd_direct=yes/no` (default `yes`),
exposed by `build-windows.ps1 -JavaFXRDDirect`. Source-built Windows x64
Editor configurations `no` and default `yes`, plus the updated JFX SDK, build
successfully. Module library member/symbol inspection confirms the three
RD implementation files are absent with `no` and present with `yes`.

The build fixture passes on mobile/safe and mobile/separate, and on OpenGL:
it checks build capability, backend selection, GPU pixel readback and forced
Viewport targets. Both host builds pass the registered JNI capability query
with the same graphics SDK (hash checked). A Viewport-only host explicitly
rejects RD requests at target creation, JVM startup and all three RD probe
entry points. Viewport render-target lifecycle coverage passes with RD omitted;
RD regressions pass on safe/separate with RD included.
The original VFX Demo also passes bounded startup/close checks with Viewport
in the `no` build and explicit RD in the `yes` build.

Evidence is under `artifacts/logs`: `godot-editor-javafx-rd-{no,yes}.log`,
`jfx.log`, `rd-build-*.log`, `rd-build-{no,yes}-hashes.json`, and
`rd-regressions-{safe,separate}.log`. The dedicated fixture is
`scripts/test-rd-build.ps1`. The older `test-bridge.ps1` attempt stopped at
Java compilation because other legacy probes still call removed encoder
overloads; it is not counted as passing. The dedicated build fixture verifies
the new JNI API independently without relaxing those older assertions.

This change does not establish macOS/Linux support or new performance results.
Runtime build commands accept the same option, but Runtime was not rebuilt or
tested in this validation round. Earlier acceptance evidence remains below.

## Previous review — checked 2026-11-11

The shared-target-mesh repair is built and passes GL/Vulkan budget, peer/final
owner release and queued-pixel checks. Three-round mobile soak passes navigation
and cleanup: homepage static memory is now 211/226/234 MiB, versus the classified
pre-fix 401/566/650 MiB. The shared geometry cache stays within 4096 entries;
a six-round same-configuration run now passes without forced GC. Targets hold
at 232 in rounds 3–6; homepage texture memory is unchanged in rounds 5–6, and
static memory is 240.61/241.24 MiB. Bounded caches still fill incrementally; this
is finite-workload evidence, not a zero-growth or all-duration guarantee. The
fixed source review is complete (156 original + 52 cumulative closeout paths),
separate from the platform compatibility limits below.
Evidence: artifacts/reference/review-soak-classified-before.analysis.json and
review-shared-mesh-after.analysis.json. The still-earlier 404/578/670 MiB run is
preserved as review-final-soak-growth.analysis.json, not the latest measurement.

Most recent recorded 68-transition measurements on mobile/safe:

| Configuration | Pulse FPS | Host-composition FPS | Evidence in artifacts/logs |
| --- | --- | --- | --- |
| RD1/LCD1, shared mesh-cache build | 59.662 | 56.786 | review-shared-mesh-transition-rd1.log; rates/hashes in artifacts/review-shared-mesh-performance.json |
| RD0/LCD1, shared mesh-cache build | 58.604 | 55.741 | review-shared-mesh-transition-rd0.log; same rates/hashes report |
| RD1/LCD1, earlier normal Editor run (2026-11-11) | 58.742 | 56.542773 | review-final-transition-full.log; independent rates and binary hashes in artifacts/review-final-performance-{rates,binaries}.json |
| RD1/LCD1, earlier Editor; maximum-counter reporting corrected | 59.184 | 56.353 | review-transition-max-counter-full.log |
| RD1/LCD1, earlier Editor after native clipboard enumeration fix | 59.386 | 56.668 | review-current-rd-transition-full.log; independent recalculation and binary hashes in review-current-rd-transition-rates.json |
| Viewport (RD0/LCD1), after immutable material/collision repair | 58.700 | 56.133 | review-material-collision-transition-full.log |

These runs had zero unfocused samples and passed cleanup. The older material-collision Viewport measurement
predates the later non-default synchronous-fallback callback fix; these are
measured snapshots, not a claim that every binary/configuration was benchmarked. The earlier
57.553/54.325 and 59.125/56.547 runs remain historical evidence. These are workload
averages, not physical scanout or stable 60 on every page. A separate 960-pulse
horizontal workload measured 53.707 FPS; the subsequent 96-pulse physical
horizontal regression measured 60.004 FPS with 867px displacement. Different
workloads must not be treated as a causal speedup; see frame-benchmark.md.

Recent repairs include expired sampler-material retirement, immutable materials
under real parameter-hash collisions, and waiting for object-bound callbacks in
the separate-thread synchronous fallback. Editor/Runtime source builds and the
targeted tests are recorded in review-open-items.md. An accumulated render-completion notification can make the shader-cache fixture
read the previous frame. The explicit queued-notification regression reproduces
this at cycle 275; waiting for a fresh pre-draw and then post-draw fixes it
(review-shader-queued-notice-old.log / review-shader-queued-notice-fresh.log).
The original occasional failure had no pixel capture, so identical causality
is not established. Clipboard interoperability and exact original-byte restoration
passed earlier on mobile Editor and Runtime (review-clipboard-postclose-* logs).
After subsequent snapshot/JNI repairs, the latest full rerun refused an unknown
Chromium private format before any clipboard write. Those repairs have focused
failure-path coverage, but full interop on that revision remains unverified.
No restoration is pending from that refused run. The harness reacquires the
clipboard lock after CloseClipboard and verifies ownership before recording its
sequence; restoration still rejects external changes.
Virtual-keyboard call/liveness checks passed with an OS close-request
access-denied warning; actual visibility/closure is not accepted by that result.

The latest native lifecycle repairs cover the OLE callback shutdown gate and
JNI exception/reference cleanup, allocation failures in drag requests and screen
snapshots, transactional custom-cursor queue insertion, launch-method lookup
failure, and restoring the default cursor only when owned and only once.
Focused before/after failure fixtures and source Editor/Runtime builds are
recorded in review-open-items.md. Runtime physical external drag and cursor tests
pass within their recorded configurations. The latest normal performance run
above postdates these builds; no paired native-JavaFX benchmark was rerun.

SceneTextureProbe now counts actual tick advancement rather than await calls,
uses a ten-second deadline per wait phase, and rejects unexpected host stops.
Current mobile normal/resize/missing-scene runs pass, preserving pixel, scene
identity and resource-cleanup assertions. No stalled-tick fault was injected.

The fixed original-source review and cumulative closeout are tracked separately
from feature acceptance; see [open review items](review-open-items.md).
HoverDemoProbe now has bounded FX dispatch, FX-confined scene access, propagated
failures and shutdown cleanup; its host now checks eight cycles and settled pixel
samples with current screen scaling. Java compilation and GDScript/PowerShell
parsing pass. With user authorization, the revised mobile/safe physical run now
passes all eight cycles (enters=8, flickers=0) and settled pixel checks (861 hold,
511 gap samples). See artifacts/logs/hover-demo-mobile-safe.log. This validates
this bounded LoadingStage fixture, not every page or rendering configuration.

MenuClickProbe now uses host-synthesized input and bounded FX/host timelines,
requires one successful original menu action plus continued completed-render and
composition counters, and reports PASS after application cleanup. The
mobile/separate test-menu-click.ps1 run passes without physical input. This
replaces the old Robot probe's unreliable timeout handling; it is not full menu
pixel or physical pointer acceptance.

The 2026-11-10 audio probe revision requires AudioTrack metadata and finite
clock/duration values, propagates callback and disposal failures, and checks AIFF
file-close errors. WAV/MP3/AIFF all pass on the current source Editor/SDK using
mobile/safe (test-media-audio.ps1 -Codec all). Playback is muted: this covers
control/metadata/normal cleanup, not audible output or injected disk/dispose failures.

Current performance scope (2026-11-10): the user requests FPS near 60 and defers
occasional long-frame fixes. The earlier source Editor/SDK run completed 68 VFX
transitions on mobile/safe, RD1/LCD1 without diagnostic sampling: 57.343 pulse FPS,
54.538 host-composition FPS, 1625 pulses, zero unfocused samples. Independent rate
recalculation matches the log (review-vfx-current-scope.log). This is workload-average
evidence, not stable 60 for every page or a physical scanout measurement; recorded
long frames are not a current fix gate. See frame-benchmark.md for full conditions.

The 2026-11-10 Windows drag-registration fix publishes DropTarget/delegate state
only after registration succeeds, releases failed temporary targets and reports
failure to the JavaFX host. Final COM Release now invokes the C++ destructor.
Editor/Runtime source builds and mobile/separate OLE injection (normal and timeout)
pass. These checks cover the successful registration and delivery paths; OS
registration failure was not injected. A subsequent physical cross-process run
passed; see the ExternalDragProbe evidence below.

The 2026-11-10 touch-keyboard review preserves HRESULT failures from COM
activation, Toggle and WM_CLOSE posting, with a first-failure host warning per
operation. test-tabtip-result.cmd passes injected failure/release checks without
using the real keyboard; source Editor/Runtime builds and Java probe compilation
pass. Existing virtual-keyboard PASS records establish Java-call completion and
host liveness only. Actual visibility, closing and repeated Toggle behavior have
not been revalidated and are not established by these checks.

LCD stock-shader loading now rejects an incomplete screen-sampler rewrite.
The source SDK including Media builds successfully; test-lcd-shader-load covers
both stock variants, both LCD modes and independently patched resource formats.
The pre-fix loader reproduces silent acceptance (review-lcd-shader-before.log).
The mobile/separate lcd-overlap pixel comparison also passes on the rebuilt SDK.
This validates shader loading and overlapping text, not Media playback or FPS.

ExternalDragProbe's 2026-11-10 lifecycle revision propagates FX callback errors,
stops and joins drivers, and attempts every input/window cleanup action before
reporting success. The source SDK compile and PowerShell parser checks pass;
the authorized mobile/separate physical cross-process run now passes three
outbound phases and one inbound transfer, including payload and drag-image gates.
Its first startup exposed exclusive helper-log sharing; using _wfsopen with
_SH_DENYWR restores concurrent launcher reads. The helper ASan checks also pass
(review-dnd-helper-sharing-asan.log). A later Runtime mobile/safe physical run
also passes (review-drag-request-runtime-external.log); this does not cover every
renderer/thread configuration.

Full-runtime compatibility acceptance remains open. This is an evidence map,
not blanket sign-off. The
objective attachment requires a Windows x64 source-built Godot-hosted JavaFX
runtime and real VFX Demo acceptance. The user's later correction requires each
secondary Stage to be an independent native window. Historical progress entries
describe what was true at their date; this file distinguishes current evidence
from remaining work.

Latest scope clarification (2026-11-03): Media support is required; WebKit is
excluded. The earlier exclusion of both components is superseded. Media native
build, PCM audio, local MP4 controls and encoded 1080p60 MediaView rendering pass
the documented fixtures. Editor repeats reach 60.140/60.163/60.145 draws/s;
packaged Vulkan/safe reaches 60.037. Glass/Prism class checks prove these are
Godot runs. Broader codec coverage and physical A/V synchronization remain open;
bounded memory evidence and the earlier unexplained 33-FPS plateau are recorded
in media-godot.md. WebKit remains excluded.

Previously recorded Media/VFX regression scope passed: paired Editor/Runtime source builds,
encoded 1080p60 timing, media controls/color/alpha/padding, packaged VFX controls,
table editing and GPU motion, plus all 35 original Demo pages and inspected GPU
captures. The current R8/explicit-disposal 120-player run plus 30 seconds idle
keeps 23 resources/4,644,864 texture bytes, ETW 313 and final resources zero.
Private-MB block medians 792.062/803.066/809.497/807.342/809.798 plateau after
warmup; latter-half OLS +0.196 MB/minute is small relative to the 38.457-MB
range. Packaged Runtime's 24-cycle check also passes. This accepts the measured
regression workloads; the wider compatibility and physical limits below remain.

## Current implementation re-review (2026-11-10)

Hover-flicker now asserts the previously statistics-only FusionButton phases:
all six hold/gap cycles must have settled samples, with no more than 5% wrong
brightness after the transition allowance. It uses current monitor scale and
rejects JVM failure, timeout and rendering errors. Mobile/separate synthetic
verification passes (588/588 bright hold, 224/224 dark gap), as does resize-cursor.
This covers the current 2x/60-Hz setup, not other DPI or physical Robot input;
the per-frame GPU readback test is not a performance benchmark.

Queued vertex-ring uploads now retain the existing COW byte storage rather
than allocate and memcpy another full batch. Editor/Runtime builds and RD
multi-pass ring-pressure regressions pass (separate/safe), as does the real
VFX direct-handler table run with RD enabled (`review-vertex-upload-cow.log`).
The single table sample is 55.785 pulses/s, p95 25.364 ms, displacement 2325 px
and no focus loss; it does not establish a causal speedup or stable 60 FPS.

The RD translation diagnostic had an invalid-ID free after its LCD PASS marker
and exit code 0: destroying the screen stand-in invalidated its uniform set
before explicit set retirement. Descriptor cleanup now precedes texture/shader
cleanup and checks set validity. The new strict `test-rd-lcd.ps1` rejects the
old artifact and passes rebuilt Editor separate / Runtime safe with max_diff=0
and no teardown errors; the 262-source Editor corpus still passes. This probe
is separate from production OffscreenPass and real JavaFX LCD overlap testing.

The cumulative current-source unit checks pass: protocol (including 10,000
concurrent frames), bounded LRU, private clipboard ownership/parsing and OLE
data-object/drag-image storage (`artifacts/logs/review-test-*.log`). Java render
command validation and hosted Glass scheduler checks also pass; the scheduler
run uses GL compatibility and covers nested loops, exceptions, cancellation
and receiver termination. These do not establish system clipboard interop,
physical input, cross-process OLE behavior or visible drag-preview correctness.

The drag/resize fixture now propagates FX-call failures via FutureTask, cancels
queued work on timeout/interruption, checks stable trace snapshots and joins
its driver at shutdown. Final-code synthetic mobile/separate and GL/safe runs
pass exact 10-step drag and 8-step resize checks. Its Robot lifecycle cleanup
also passed the authorized mobile/separate physical run with exact drag/resize
checks (physical_drag-mobile-separate-robot.log); no timeout fault injection is claimed.

The NativeTableDrag physical-input comparison was rewritten to remove shared
cross-thread frame data, incomplete-run PASS and missing exception cleanup.
Scene access, sampling and Robot cleanup stay on the FX thread; completion is
checked after launch returns. It compiles against the source SDK/VFX artifacts.
Subsequent authorized native D3D runs passed the minimum actual-displacement
check: vertical 62.475 FPS / 1581px and horizontal 62.530 FPS / 867px
(review-native-table-displacement-v.log / review-native-table-displacement-h.log).
These are short native comparisons, not Godot acceptance.

Table-host observation now counts idle and drag focus separately; older drag
focus fields actually covered only idle and cannot prove background dragging.
Growth samples now use strictly increasing drag ticks at eight-tick intervals,
including endpoints. Maxima are reported as lifetime maxima rather than
subtracted as interval counters. `review-table-host-counters.log` passes with
61 idle ticks, 95 drag ticks, zero focus loss in each and 13 consistent growth
samples. This focused direct-handler run does not establish background or
physical-input behavior, or long-term memory stability.

The large-table diagnostic now shares the bounded, joined ThreadStackSampler
with the transition probe. Its idle percentiles are computed after sorting;
drag GAPS_MS preserves chronological order instead of printing sorted gaps.
A 20-ms-sampled RD mobile/separate direct-handler run passes and its 96 reported
gaps reproduce the summary quantiles within log rounding. Zero-ms configuration
is rejected. These are diagnostic checks, not unsampled performance acceptance;
older idle quantiles and sorted "time series" are superseded.

The scroll-wheel fixture now checks position after all three events have been
handled; previously its third-event filter observed only two notches and passed
80 pixels as a three-notch result. Current mobile/separate and GL/safe runs
produce the expected 120 pixels within 0.01 px. This uses synthetic input and
the current system setting, not physical wheel or all preference combinations.
FIFO/LIFO ImagePool and mobile source Media WAV/MP3/AIFF playback-control tests
also pass in this review; the muted audio probe does not verify audible output.

The cumulative post-Shader-fix VFX RD run passes all 68 transitions with zero
focus loss: 57.296 pulses/s, 54.614 host compositions/s, p95 20.486 ms and maximum
188.866 ms (`review-vfx-post-shader-fixes.log`). FIFO pacing switched to CPU
pacing after startup; this is not stable 60 FPS or continuous VSync evidence.
Subsequent module teardown repair restricts cleanup to the SCENE level.
Profile-enabled Editor separate and Runtime safe RD regressions pass with one
summary each, replacing the four repeated Editor summaries reproduced before
the repair. Both source artifacts were rebuilt successfully.

The separate Canvas instance-uniform name memo now uses a 256-entry / 4 MiB
payload LRU instead of an unbounded global table. Name lists return COW ownership
so eviction cannot invalidate a caller's list. The Editor mobile/separate cache
fixture passes 305 cycles, reaching 256 entries before byte pressure reduces
the cache to 31 entries / 4,079,724 bytes. The real JavaFX Node shader test also
passes with RD explicitly disabled. The budget covers retained source/name
payload, not driver memory or all other shader caches. Editor/Runtime source
builds pass; Runtime mobile Canvas Effect comparison against native D3D also
passes (`review-instance-memo-runtime-effects.log`).

RD readback now transfers copy-on-write pixel storage to the returned Image,
clears static staging ownership and rejects an unexpected byte count instead
of returning a blank image. Editor/Runtime source builds and RD regressions
(separate/safe) pass, including image independence across mutation, repeated
readback and target destruction. The Java queued-texture-update readback test
also passes on Editor separate. Device-failure injection was not performed;
this readback allocation improvement is not a rendering FPS measurement.

Screen-sampler declarations now retain their original names. The previous
partial rename broke direct fragment references and differently named samplers.
Editor/Runtime builds and RD regression checks (separate/safe respectively)
pass for helper, direct and renamed-source variants. A channel-swapping pixel
assertion also rejects dropped draws that leave the background untouched.
The real JavaFX LCD overlap comparison on Editor separate still passes.
The reproduced failure is `review-rd-screen-sampler-before.log`.

RD pixel-coordinate translation now matches Canvas framebuffer orientation;
the prior 76 edge-exempt corpus cases were caused by an extra Y flip. All 262
generated shaders now pass the strict full-image 2/255 channel tolerance, with
no edge/deferred exemptions. Blend modes are read from parsed render-mode
declarations, preventing ADD/MULTIPLY helper names from changing pipeline state.
After both fixes, Editor and Runtime source builds and RD regressions
(Editor separate, Runtime safe) pass. Explicit RD_DIRECT=1 mobile Effect
comparisons against native JavaFX D3D pass on both artifacts; preserved logs are
`review-rd-blend-mode-editor.log` and `review-rd-blend-mode-runtime.log`.
The Runtime GPU capture `godot-effects-mobile-runtime.png` was also inspected.
These are fixture-input checks, not universal shader or frame-rate acceptance.

The uninstrumented post-retirement-fix Editor VFX transition run completed 68
transitions without focus loss: 56.744 pulses/s, 53.972 host compositions/s,
p95 26.212 ms and maximum 181.025 ms. See frame-benchmark.md and
`artifacts/logs/review-vfx-transition-retirement.log`. This is not stable-60-FPS
acceptance or a controlled performance comparison. Shared RD pipelines now have a 256-entry / 16-MiB text-payload cache budget,
with separate ownership for queued draws. The new churn regression checks
eviction and pending-draw pixels: Editor separate, Editor safe without batching
and Runtime safe pass on rebuilt source binaries. RD/mobile/safe VFX all 35
pages also pass. These checks do not measure total driver memory. The subsequent uninstrumented
cache follow-up records 58.242 pulses/s and 55.604 host compositions/s, p95
24.686 ms, p99 39.301 ms and maximum 212.925 ms with zero focus loss
(`review-vfx-bounded-pipelines.log`). It does not establish stable 60 FPS or a
causal speedup; see frame-benchmark.md.

The active re-review covers the combined root diff from 9ae5a635 (excluded)
through 04e4ba1, the associated engine submodule changes, and the current
uncommitted repairs. It remains incomplete. The sections below dated November 9
describe earlier evidence, not acceptance of all current changes.

- Current source Editor and Runtime both pass `test-media-video -Renderer
  mobile` (Runtime with `-Runtime`), including seek/end/stop/replay and the
  Godot host markers. Logs: `media-video-mobile[-runtime].log`. These checks do
  not establish 60 FPS, codec completeness, or physical A/V synchronization.
- The RD/mobile/safe VFX all-pages failure is now repaired for the measured
  workload. RID-correlated diagnostics showed Surface retired textures being
  freed before pending RD batches sampled them. Retirement now commits those
  batches first. The two-page diagnostic reproduction and the uninstrumented
  35-page run pass, as does Editor RD separate pixel regression. Before logs:
  `review-vfx-rd-texture-trace.log`; after logs:
  `review-vfx-rd-retire-fence.log`, `vfx-intro-mobile-safe-all-pages.log`.
  A separate uniform-buffer dependency defect also has a failing-before,
  passing-after pixel regression (`review-uniform-retirement-before.log`).
  These results do not establish stable 60 FPS or all device-loss behavior.
- Local regressions for bounded caches, ownership, input termination, Windows
  GL window lifetime, clipboard parsers, OLE replacement/reentrancy and temporary
  RD texture fallback are recorded with their limits in `progress.md` and
  `TESTS.md`; they are evidence for their stated scope rather than a blanket sign-off.
- RD screen sampling now snapshots after the current pass clears and draws its
  background, immediately before its first screen-sampling draw. Previously the
  regression read the preceding red pass instead of the current blue background
  (`review-rd-screen-snapshot-before.log`). Rebuilt Editor separate, safe without
  batching, and Runtime safe pass both blue-background and clear-only cases;
  RD/mobile/safe VFX all 35 pages also passed at that step. The subsequent LCD
  repair restores text-node pass boundaries and removes the extra snapshot Y
  flip. The top-blue/bottom-green RD fixture and actual overlapping LCD text
  versus the Godot LCDBuffer path pass (safe/separate, 2/255 tolerance).
  The subsequent RD transition failure (`review-vfx-lcd-node-snapshot.log`)
  exposed Surface clearing texture-reference flags before queued RD draws
  consumed them. A one-transfer regression reproduced old red content changing
  to blue after an intervening upload. Flags now remain set while RD batches
  are pending. Safe/separate queued-texture regressions and separate LCD
  comparison pass; rebuilt Editor's explicit RD 68-transition follow-up passes
  without binding errors (`review-vfx-texture-reference-fence.log`): 58.183
  pulses/s, 55.530 host compositions/s, p95 19.964 ms, max 158.954 ms, no focus
  loss. The previous failed run remains diagnostic evidence only.
- Current Editor GodotView lifecycle checks pass on mobile and OpenGL: 100
  load/resize/synthetic-input/retain/release cycles per backend, including parent
  destruction before the wrapper. The mobile scene-texture resize check also
  passes and its GPU screenshot was inspected. Logs:
  `scene-views-mobile.log`, `scene-views-gl_compatibility.log`,
  `scene-textures-mobile-resize.log`. These cover the fixture's node/resource
  ownership and pixels, not all driver-memory or physical-input behavior.
- Java custom clipboard encoding now rejects oversized buffers before copying
  and validates serialized String lengths before decoding. A 32-MiB heap probe
  reproduced the prior OutOfMemoryError with a 64-MiB direct buffer and passes
  after the Media-enabled SDK rebuild (`review-clipboard-encoding-before.log`,
  `clipboard-encoding.log`). This probe does not access the system clipboard.
- System clipboard interoperability is still unverified after the parser and
  restoration changes. The latest attempt refused Chromium private metadata
  during backup, before any test writes. No protection was bypassed. Private
  allocation/parser tests and the restoration guard tests pass, but are not an
  end-to-end restoration certificate.

## Prior review repair status (2026-11-09)

The review covers the combined diff from 9ae5a635 (excluded) to b0bed86, including
both engine submodules. Earlier PASS/floor/decision statements below are dated
historical evidence, not a sign-off for the current RD implementation.

Repairs now include staging open-pass draws before ring reuse, render-thread
buffer updates, the initialize script default, seven-float rectangle/copy
vertices and premultiplied color, accepting RD copy sources, preserving uniform
defaults with the engine parser, one-element arrays/integer vectors, Java geometry
validation before cache mutation, and cancellation of queued OLE requests.
Source Editor/Runtime and Media-enabled SDK builds pass. Verification:

- `test-rd-regressions`: Editor safe/separate, safe with ring off, safe with
  batching off, and an isolated source-built Runtime fixture pass. Full-image
  checks cover 48 draws in one pass, repeated preserve/clear, premultiplied
  rectangles, copying a pending source, source retention/retirement, uniform
  defaults and overrides, array[1], and ivec3. Logs: `rd-regressions-*.log`.
- `test-render-command-validation` passes repeated rejection of NaN, nonzero Z
  and float-overflow transforms, then verifies first registration and later
  reference of valid geometry; no toolkit or JNI is needed.
- OLE module injection passes normally on Vulkan and in timeout/recovery mode
  on Vulkan/OpenGL. Expired queued Enter/Drop callbacks do not run after FX
  unblocks, and the next valid drop succeeds (`ole-inject-*-timeout.log`).
- Existing render-target and node-shader tests pass on Vulkan/OpenGL. Vulkan
  node shaders also pass with RD enabled (preserved log:
  `review-node-shaders-mobile-safe-rd.log`). Protocol unit tests pass.
- `review-rd-corpus.log`: 212 Prism + 50 Decora sources present, 186 exact and
  76 accepted by the existing edge-precision criterion, zero failures. The
  fixture now rejects missing/incomplete corpus directories. This is not a
  claim that all 262 shaders matched pixel-for-pixel.

The new regressions also exposed and fixed off-thread buffer_update calls and
copy-source references retained past finish_pass. Tests use GPU readback or
in-process injection, not physical input. Cancellation prevents a queued OLE
callback from starting; application code already running on FX is not interrupted
or transactionally rolled back. No clipboard contents were touched.

Follow-up cache audit: FIFO ImagePool reuse (`GODOT_JFX_IMAGE_POOL_LIFO=0`)
skipped the adjacent live entry after removing an expired/lost entry. The new
`test-image-pool-reuse.ps1` failed before repair (`review-image-pool-before.log`),
then passed in FIFO and LIFO after rebuilding the Media-enabled SDK. Cases cover
cleared references, lost images, consecutive invalid entries and unchanged tie
ordering without GPU or GC timing. Encoder validation also remains green.

The recorded RD 56.96fps/P95 27.6ms result supersedes the old ~44fps floor as a
historical comparison, but does not meet the original P95 <25ms gate. This repair
review does not claim a new performance measurement or physical-input acceptance.

## Last lever API-blocked; floor confirmed (2026-11-07, tenth batch)

Scoping the final recorded lever (effect inputs out of material
parameters) against the engine's public rendering API: per-item binding
supports exactly one texture (already used for QUADS; effect chains need
2-4 samulators), sampler2DArray exists in the shader language but no
public render target can be an array layer, and instance uniforms
cannot carry samplers. The ~120 us/pass descriptor-set recreation on
texture change is therefore a platform cost for multi-texture canvas
materials. The ~44 fps transition floor now rests on four independent
evidence classes: nine implemented levers with same-binary A/B, the
viewport-cycle spike (5.9-37.5 us), the GPU re-attribution (window
0.50 ms/frame; ~314 us/pass CPU submission), and this API survey.
Remaining paths are engine-level (RD-direct backend — premise already
measured out — or engine API extensions). In that historical batch, all work was committed; the
workspace is clean. User decision on accepting the floor stands
offered.

## Material patching implemented (2026-11-07, ninth batch)

The lever named by the re-attribution was implemented end to end
(texture-RID-only changes patch the cached material instead of
recreating; pixel gates green including the D3D comparison). Measured
honestly: transitions 44.5 vs 44.0 — inside the 42-45 band, not the
estimated 5-8 fps; the rebuild counter dropped only 4.70 -> 4.50 s
because the per-rebuild cost is dominated by descriptor-set recreation
that fires on any real texture change. The table drag reached its best
real-input numbers (p50 16.6 ms, p95 22.7 ms, 59.9 fps). Eliminating
the remaining per-pass cost requires moving effect inputs out of
material parameters entirely (per-item textures or a shared texture
array) — recorded as the remaining path. Decision on accepting the
floor remains with the user.

## Re-attribution from GPU timing (2026-11-07, eighth batch)

GODOT_JFX_GPU_TIMING instruments the window viewport; fresh post-fence
CPU counters complete the picture: presentation GPU is 0.50 ms/frame
(3 % of budget — excluded), while per-pass CPU submission costs ~314 us
(material uniform rebuild ~120 us, dirty processing ~45 us, encode
~30 us) x ~18 passes/frame = ~5.4 ms/frame, reproducing the observed
43 fps frames. The earlier "~13 % material constant" phrasing
understated it: it is the largest per-pass component. Identified next
lever (not started): patch cached effect materials on texture-RID change
instead of recreating them (one queued rebuild instead of create + N
params), ceiling ~3 s per run, est. 5-8 fps on transitions. Decision on
accepting the floor vs pursuing this lever is with the user.

## RD-direct premise falsified by P0 spike (2026-11-07, seventh batch)

With the architecture decision unanswered twice, a premise-checking spike
was run instead of unilaterally starting the 4-6 week rewrite:
The now-removed `JavaFXHost.benchmark_offscreen_cycle` measured the bare offscreen
viewport render cycle at effect-pass resolution — 5.9 to 37.5 us per
cycle for 0-64 draw items. The RD-direct plan's core assumption
(~440 us/pass cycle cost) was the sync-inclusive wall time of the removed
per-pass fence, not the cycle cost. The rewrite's recoverable ceiling is
~30 us/pass and cannot close the 17-20 fps transition gap;
the retired RD design notes (available in Git history) now states "premise falsified, do not
start on the original grounds", protecting a multi-week investment from
being spent on a falsified premise. The residual gap requires
re-attribution (real GPU work of effect passes, presentation pipeline,
material-rebuild constant) before any new project is sized.

## Pass-sync pipelining (2026-11-07, sixth batch)

The per-pass full-device sync behind every offscreen effect pass became a
configurable interval (`GODOT_JFX_PASS_SYNC_INTERVAL`, default 0 = batch
fence per host tick). Pixel gates and regressions pass on the batch fence
(editor/runtime rebuilt). Measured honestly: today's six runs span
42.4-45.2 fps across interval settings — the third-batch regression does
not reproduce after the material/instance fixes, but neither does a
reproducible gain. Combined with the five prior levers' data chain, the
remaining transition gap to native 62 fps and the drag p95 gap to the
render floor sit in the per-offscreen-pass viewport render cycle itself;
closing them requires a RenderingDevice-direct render backend (renderer
rewrite), which is sized by the recorded evidence but out of scope for
bridge-level patches.

## Effect image pool frame affinity (2026-11-07, fifth batch)

The fifth recorded lever was implemented: `ImagePool.checkOut` scans the
unlocked pool most-recently-checked-in first (LIFO frame affinity;
`GODOT_JFX_IMAGE_POOL_LIFO=0` restores FIFO). Pixel gates pass and the
full regression batch is green (12 items incl. protocol, mesh x2,
composite, drag-drop, scroll-wheel, godot-view, vfx-table, intro
-AllPages, table-scroll, glass-scheduler; the six pixel gates of the
fourth batch also re-passed). Honest verdict: transitions 42.7 (LIFO) vs
41.8 (FIFO) — within the 41.8-44.4 band all recent levers land in — and
the material rebuild counter did not drop: during sliding transitions
the effect images' quantized size classes change every frame, so keys
stay novel regardless of tie-break. After five levers with a complete
data chain (Java idle; pass count below native; value-constant rebuilds
eliminated; sampler churn un-fixable by tie-break), the residual
transition gap to native 62 fps is the per-offscreen-pass viewport
render price inside the Godot RenderingServer and a ~13 % constant of
genuine per-frame rebinds. Further bridge-level tuning is exhausted;
the recorded next step is a RenderingDevice-level render backend.

## Instance-uniform material migration (2026-11-07, fourth batch)

The recorded next lever was implemented end to end: target-path shaders
compile value uniforms as per-instance uniforms, SHADER_STATE splits
constants accordingly, and slot draws push instance values through
`canvas_item_set_instance_shader_parameter` (direct instance-buffer
write). All thirteen pixel/regression gates pass (composite-edges against
D3D included) and the value-constant share of material uniform rebuilds
is eliminated (5.47 -> 4.56 s per 37 s run). Honest verdict: transition
fps is unchanged (43.2 on vs 43.3 off) because every remaining rebuild is
a cold miss driven by the effect chains' `inputTex` naming a different
pooled render target on every command (proven by a sampler-RID trace;
glyph atlas and mask texture RIDs are stable). The next recorded lever is
frame-affine reuse in the Prism effect image pool so material keys stay
stable across frames.

## Per-pass host cost optimization (2026-11-07, third batch)

Acting on the unit-price diagnosis, phase instrumentation inside Godot
(`GODOT_JFX_OFFSCREEN_PROFILE`, `GODOT_JFX_RES_PHASES`) showed the per-pass
cost splits into canvas-update 225 us (of which material uniform rebuilds
dominate — 4.4 s per 37 s run) and viewport render 96 us. Two fixes:

- Slots skip `canvas_item_set_material` when the material RID is unchanged
  (each rebind queued a dependency update); the draw phase dropped to
  34 us/pass.
- `acquire_material` caches RID-bearing parameter sets with hit-time
  liveness validation against a live-sampler set maintained at every
  texture retire/free site, plus pressure purge and oldest-insertion
  eviction. This restores RID-material caching with the retired-revision
  hazard excluded by construction.

Measured (after fixing an evaluation-order bug that initially measured
44 fps while reusing stale slot materials — caught by the pixel
comparisons, bisected, corrected; full regression 16/16 green):
transition benchmark 42.5 fps (within its band — the fresh-path material
switches there are genuine); real-input table drag p95 26.0 -> 23.6 ms
and p99 67.0 -> 63.8 ms (8 events/frame); render-only floor at its best
(59.9 fps, p50 16.7 ms, p95 18.4 ms, p99 41.2 ms). The material cache
also validates full identity on every hit (hash bucketing only). Remaining distance to native (62 fps/p95
16.9) is dominated by ~44k per-run material uniform rebuilds for effect/
clip constants that genuinely change every animated frame — a Prism
shader-model mapping question (instance parameters), recorded as the next
architectural lever.

## Native-comparison gap analysis: page turns and drag (2026-11-07, second batch)

User re-test against the native D3D build found page turns still clearly
slower and held-button table drag janky while wheel scrolling is smooth.
Both are now attributed with reproducible data:

- Same-benchmark native comparison: 62.0 fps / p95 16.9 ms (D3D) vs
  43.1 fps / p95 ~60 ms (Godot) across the same 68 transitions; worst
  table page p50 16 ms native vs 72.7 ms Godot.
- Java is idle during transitions (in-process sampler: QuantumRenderer
  ~88% parked); the host main thread is ~71% busy. Render-target switch
  counts prove the point: native performs 70,428 switches and stays at
  62 fps; Godot performs 27,675 and runs at 43 — the per-switch host cost
  (~440 us per viewport render vs microsecond D3D SetRenderTarget) is the
  gap. Recorded as the engine-architecture limit; closing it needs a
  RenderingDevice-level or engine viewport-lightweight path.
- Held-drag vs wheel: real-input fixture modes (synthesized full-pipeline
  and Glass Robot physical cursor) show event rate is irrelevant (p95
  24-26 ms from 60 Hz to ~2 kHz); the delta over render-only (18.5 ms) is
  genuine hover-highlight re-rendering as the pointer crosses cells
  (~1,500 extra full uploads per drag window) — work native also performs
  at lower per-batch cost. The wheel does not move the pointer, hence
  smooth.
- Diagnostic tooling added: `GODOT_JFX_DRAG_MODE=direct|real|robot` in
  the table-scroll fixture, `GODOT_JFX_REAL_EVENTS`, the transition
  probe's `GODOT_JFX_STACK_SAMPLE` sampler, the
  `VFX_TRANSITION_TARGET_SWITCHES` counter, and environment-gated host
  burst budget (`GODOT_JFX_PASS_BUDGET_US`, `GODOT_JFX_BATCH_CAP`).

## Architectural change: draw modulation protocol (2026-11-07)

Implemented the retained/differential rendering architecture (the reachable
form of the kimi session's "option C"):

- Every quad draw now carries a uniform modulation float (opcodes 4/8/29,
  validated 0..1). The Java pipeline no longer bakes the graphics extra alpha
  (node opacity) into vertex colors — `vertexColorModulation` returns 1 and
  the value rides the wire, with a flush invariant keeping one flush batch at
  exactly one modulation. Fading batches are therefore byte-identical across
  frames and hit the geometry cache instead of re-uploading every vertex.
- The encoder skips identical back-to-back SHADER_STATE/CLIP emissions (the
  host treats them as persistent state), invalidated at every host-side
  reset point and disabled if a second encoder ever exists.
  `GODOT_JFX_DRAW_MODULATE=0` / `GODOT_JFX_STATE_SUPPRESS=0` restore the
  previous behavior for A/B; `get_render_stats()` exposes
  `quads_uploaded`/`quads_referenced`.
- Honest measurement (alternating same-binary A/B, all runs focused): the
  68-page transition benchmark is fps-neutral within run-to-run noise
  (41.6 vs 42.2 fps average) while full-quad uploads drop 8% (23,565 vs
  25,626) and references rise; the table drag holds 59.9 fps with p95
  19.4 -> 18.5 ms and p99 42.4 -> 41.1 ms. Page-turn frame rate remains
  bounded by rounded-clip offscreen passes (~15 per presentation on heavy
  pages, the same work native pipelines perform), not by encoding.
- Pixel correctness held: D3D comparison fixtures (composite-edges) pass at
  the existing tolerance; the one-rounding-step color difference (quantize
  before vs after the alpha multiply) is within it.

## Large-table drag and page-turn deep optimization (2026-11-06 late evening)

User report: the large-table demo (50 rows x 7 columns) still janks while
dragging, and page turns still drop frames. Root-caused and fixed:

- Profiling with a new foreground-independent fixture
  (`scripts/test-vfx-table-scroll.ps1`; the probe drives the viewport's own
  drag handler, so no OS input or window focus is required — verified with
  all 62 measured ticks while another application held focus) showed 117
  offscreen passes per dragged pulse. ~97 of them came from Prism's LCD-text
  per-text-node LCDBuffer round-trip; the rest are VFX rounded-corner shape
  clips that native pipelines also pay.
- The second-pass LCD shader now samples the destination through Godot's
  renderer backbuffer (`hint_screen_texture`), and the per-node copy pass is
  skipped via a pipeline capability (`GODOT_JFX_LCD_SCREEN=0` restores the old
  behavior for A/B). Same-binary A/B: drag offscreen passes 11,420 -> 1,900
  (-83%), fps 54.6 -> 59.6, p95 25.0 -> 19.4 ms, p99 97.4 -> 51.2 ms; the
  scrolling sweeps themselves run at the display refresh interval (~17 ms).
  All four renderer/thread combinations improve: mobile/safe 54.6 -> 59.6,
  mobile/separate 51.1 -> 55.2, gl_compatibility/safe 25.9 -> 47.8 fps.
  Page-turn benchmark: 30.9 -> 35.0 fps, worst page (the same table page)
  7.5 -> 11.5 fps. Text verified visually and by pixel-change regression
  (test-vfx-intro -AllPages, test-vfx-table).
- Recorded limits: the destination snapshot is now per render pass instead of
  per text node (differs only for overlapping text within one pass); the
  remaining transition cost is rounded-clip offscreen passes (native parity)
  plus Java-side re-encoding of genuinely changed geometry; a protocol-level
  shader-state deduplication was measured (0.16 s of a 37 s run) and
  deliberately not implemented. The fixture's own clamped tail segment shows
  an 18->50 ms monotonic creep that only occurs while the synthetic drag is
  clamped at the top edge (no scene change); real scrolling is unaffected.

## Kimi follow-up issues and geometry deduplication (2026-11-06 evening)

The three issues raised in the later kimi session are closed:

- Scroll-wheel speed (kimi's SPI/40px fix) re-verified green this batch.
- Title-bar drag / corner resize with the pointer escaping the window:
  physically verified by `test-physical-drag.ps1` — both gestures follow the
  clamped physical cursor exactly (window moves to -14 where the cursor rests
  at y=0; resize reaches exactly 740x576). The probe's original expectations
  were corrected: physical cursors clamp to the screen, and button-held
  MOUSE_EXITED is Quantum's standard pick-change synthesis (native parity,
  proven not to end the gesture) — only button-less MOUSE_MOVED breaks it.
- Parent-container translation frame drops: command-level profiling put 65%
  of host encode time in geometry command application (11.2 s/36 s), and the
  content-hash mesh cache alone did not move it. Implemented protocol-level
  geometry deduplication (QUADS_REF/GEOMETRY_FREE handles with a projected
  GeometryLedger), persistent offscreen draw slots and RID-free material
  sharing. Host geometry application halves (11.1 s -> 5.2 s per 35 s run);
  `benchmark-vfx-frames.ps1` holds 59.93 fps (no regression). The overall
  68-page transition rate is unchanged (38.9 vs 39.2 fps) because Java-side
  per-frame Prism re-encoding and the per-presentation offscreen pass count
  dominate — recorded as the known architectural limit, not claimed as fixed.
  Four real defects found and fixed on the way: a 4-byte QUADS length
  mismatch, material-cache keys pinning retired sampler RIDs (blank effect
  chains), `canvas_item_set_visible(false)` racing pending UPDATE_ONCE
  renders (blank output), and `canvas_item_clear` resetting clip state.

Full regression batch green this change set: protocol (new ledger/wire
cases), effects x2, mesh-transform x2, m1, render-targets, composite,
shader-cache (owned-count formula extended), stage, stage-churn,
scroll-wheel, glass-scheduler. TESTS.md now classifies fixtures by
foreground/topmost dependence, following the established background-friendly
patterns (synthesized input and the ole-inject module hook).

## Drag preview images (2026-11-06)

`Dragboard.setDragView(image, offsetX, offsetY)` previously threw
`UnsupportedOperationException` once a drag left the hosted windows (the OLE
handoff rejected the `application/x-java-drag-image` mime), and no preview
existed. The Quantum drag-view buffers now ride the OLE handoff: the bridge
forwards them to the host, the host builds a 32-bpp bitmap from the BGRA
payload and registers it through `IDragSourceHelper::InitializeFromBitmap`,
and the OLE `IDataObject` accepts the formats the shell writes back via
`SetData` (HGLOBAL storage only), mirroring the Win Glass `setDragImage`
path. Image-center offsets apply when none were set. The OS renders the
preview for the OLE portion of a gesture; no preview is drawn while the
pointer stays inside hosted windows.

Verification:

- All four source builds pass (editor, runtime, JFX SDK, Media SDK).
- New `tests/native/dnd_drag_image_test.cpp`
  (`scripts\test-dnd-drag-image.cmd`) passes: the shell helper stores
  DragImageBits with the exact published 8x6 size and 5,3 offset, and shell
  `SetData`/`GetData`/`EnumFormatEtc` round-trips work.
- `test-drag-drop-ole-inject.ps1` passes on Vulkan/safe with the new
  DataObject (module regression), and `test-glass-scheduler.ps1` passes with
  the extended JNI registration.
- `test-drag-drop-external.ps1` sets a drag view and asserts the helper
  endpoint observes matching DragImageBits during DragEnter. After the user
  unlocked the machine again it passed on all three combinations —
  Vulkan/safe, OpenGL/safe and the packaged Runtime — with the helper log
  recording `image=8x6@5,3 bytes=216` during DragEnter
  (`drag-drop-external-mobile-safe.log` and siblings). The in-app
  `test-drag-drop.ps1 -Renderer mobile` rerun also passes all seven cases.
  This closes the blocked verification below for the drag/drop batch.

## Machine locked again: GUI fixtures blocked, then cleared (2026-11-06)

LogonUI was running with the lock screen in the foreground and presents paced
at ~60 ms/frame (the documented machine-level plateau state), so interactive
fixtures could not validate during that window: JVM startup alone consumed
62-86 s and exceeded the external fixture's 60 s scene deadline, Robot
(SendInput) presses never reached the application (no DRAG_DETECTED was
printed), and `test-drag-drop.ps1` stalled at case 2 after cases 0-1
complete — with or without the vsync fallback. A bisect that stashed all
drag-image changes and rebuilt the pre-change binaries from the same sources
reproduced the same case-2 stall, so the stall was environmental and
predated that batch. After the user unlocked the machine, the serial reruns
of `test-drag-drop-external.ps1` (Vulkan/safe, OpenGL/safe, Runtime) and
`test-drag-drop.ps1 -Renderer mobile` all passed, closing the gap. One
operational note: the Runtime fixture's headless editor import failed once
with a stale `.godot` cache from an earlier build
(`EditorNode::is_cmdline_mode` null singleton); deleting
`artifacts/runtime-dnd-external/.godot` before rerunning fixed it.

## VFX interactivity fixes (2026-11-05)

Four reported VFX Demo issues were measured and addressed:

- Resize-grip hover cursor: JavaFX cursor commands reached the OS cursor, but
  the Godot Viewport re-asserted the Input default (arrow) on every mouse
  motion over the hosted surface. The host now syncs that default through the
  new `Input.set_default_cursor_shape_quiet` (no synthesized motion event) and
  restores the pre-runtime shape on JVM stop. `test-resize-cursor.ps1` passes
  on OpenGL safe/separate.
- Title-bar drag follow: input waited for the next host tick, and the window
  moves it produced only applied a frame later. Fixed by normalizing the
  post-event mouse-button mask (Quantum's press-drag-release gesture semantics),
  a dedicated input-receiver thread waking on a new queue input tick, and a
  second host-command application point at `frame_pre_draw`.
  `test-window-drag.ps1` measures 2.0 frames average lag (max 3) on all four
  renderer/thread combinations; the probe briefly warps the physical cursor.
- Low frame rate on animation-heavy pages: the benchmark had regressed to a
  stable ~32.8-FPS plateau. Bare-Godot probes (no JavaFX) reproduce it on
  Vulkan and OpenGL alike while native D3D stays at 62.5, so the plateau is a
  machine-level present-pacing state, not a bridge cost. A one-shot host
  pacing check now falls back to VSync-off plus `Engine.max_fps = refresh`
  (windowed presents are DWM-composited; opt out with
  `GODOT_JFX_VSYNC_FALLBACK=0`). The animation benchmark recovers from 32.751
  to 58.050 compositions/s; with the knob off it stays at 32.751.
- Low frame rate on next/prev page flips: the new
  `benchmark-vfx-transitions.ps1` records light pages at 40-55 pulses/s with
  the fallback. The heavy table pages remain at 10.8 cold / 31.2 warm because
  their per-frame cost (full re-encode, per-batch mesh rebuild, 30-70
  offscreen passes) exceeds the frame budget; this content-side optimization
  is an architectural item and is recorded as a known limitation in
  frame-benchmark.md.

Regressions after these changes: window-drag x4, resize-cursor x2,
image-cursor, godot-view (mobile/Transform), drag-drop, glass-scheduler and
VFX smoke all pass. The plateau trigger itself is environmental and
unresolved; investigate the machine's virtual display adapter/driver state if
it recurs.

## Drag/drop completion work (2026-11-04)

The new `test-drag-drop.ps1` passes seven cases on Vulkan/safe,
Vulkan/separate and OpenGL/safe: same-window COPY, independent-Stage MOVE,
LINK, rejected drop, Escape, target hiding and source hiding. The three
successful drops verify text/HTML/RTF/URL/file-list/custom data; all seven
report exactly one completion, and host-owned resources finish at zero.
Logs are `artifacts/logs/drag-drop-<renderer>-<thread>.log`. The SDK was rebuilt
from source with Media enabled (`jfx-media-native.log`).

OpenGL/separate initially completed the Java and host assertions but failed the
runner's error gate: `GLManagerNative_Windows::window_make_current` reported
Windows error 170 (ERROR_BUSY) while switching context. Root cause: with the
render thread holding the single shared native-GL context, main-thread
`wglMakeCurrent` calls from `window_set_vsync_mode` and sub-window creation
raced it. Fixed upstream by marshalling native-GL vsync switches and the
post-`window_create` make-current onto the render thread
(`display_server_windows.cpp`, `gl_manager_windows_native.cpp`; single-threaded
mode keeps the direct call). OpenGL/separate now passes with no ERROR lines,
and OpenGL/safe, Vulkan/safe and Vulkan/separate regressions still pass
(`drag-drop-gl_compatibility-separate.log` and siblings, 2026-11-04).

Native-stage input (Vulkan/safe), Glass scheduler and host-stop
(Vulkan/separate) regressions pass. The older input-cancel/lifecycle fixtures
initially timed out because they still used embedded-window counts and
root-relative injection for child Stages. They now use native-window counts,
window IDs, local coordinates, DPI scaling and focus readiness, preserving the
original Java assertions. Both pass when rerun serially on Vulkan/safe.

This is progress toward the active goal, not final Glass acceptance. Drag
preview/cursor feedback and
other unsupported adapters listed below still require implementation/verification.

## Cross-application OLE drag/drop (2026-11-04)

Windows OLE transfer to and from other processes is implemented and verified.
Godot keeps its `RegisterDragDrop` ownership on every hosted HWND; the module
injects a delegate into `DropTargetWindows` instead of registering a second
target, and foreign payloads without a supported format still fall through to
Godot's file-drop path. Outbound gestures leaving every hosted window snapshot
the drag clipboard into a native `DoDragDrop` source exposing CF_UNICODETEXT,
HTML Format, Rich Text Format, UniformResourceLocator(W) and CF_HDROP;
completion returns as input-record kind 20 with the performed effect. Inbound
OLE callbacks re-dispatch to the FX event thread with a bounded wait, and the
callback thread is attached/detached per call so VM destruction cannot hang on
an attached Godot main thread.

`test-drag-drop-external.ps1` drives the gesture with the JavaFX Robot against
two real Win32 OLE endpoint processes: drag-out of text+URL+files, drag-in of
text/URL/files, and an Escape-cancelled drag-out. The fixture passes on
Vulkan/safe, OpenGL/safe and packaged Vulkan/safe Runtime
(`drag-drop-external-gl_compatibility-safe.log`,
`-mobile-safe-runtime.log`); helper placement is DPI-scaled physical pixels.
The in-app seven-case fixture, its Robot variant and the Glass scheduler
regression also pass after these changes. Drag preview images and
physical-device validation remain open. Custom formats were added later: the
OLE data object and inbound extractor now carry `application/x-godot-custom-*`
payloads in both directions and the fixture asserts them; after the session
blockers cleared this passed on Vulkan/safe, OpenGL/safe and the packaged
Runtime (2026-11-05). The rerun exposed that the Win32 helper endpoint
advertised formats only through QueryGetData: inbound custom discovery
enumerates the source's IDataObject, so `dnd_helper.cpp` now implements
`EnumFormatEtc` listing every advertised format. The payload path additionally
has a background-friendly fixture (2026-11-05): `test-drag-drop-ole-inject.ps1`
loads the module's own source DataObject through the real inbound delegate via
the host's `simulate_external_drop` entry and asserts the full Dragboard
content, all without physical mouse input; it passes on Vulkan/safe,
OpenGL/safe and Vulkan/separate (`ole-inject-*.log`).

## Completion batch: keyboard, audio codecs, GL/separate (2026-11-04)

Verified on this machine:

- Virtual keyboard: `GodotWindow._requestInput/_releaseInput` no longer raise
  pending-unsupported; they reach the native host commands 26/27, which summon
  the Windows touch keyboard through the shell `ITipInvocation` toggle and
  close `IPTip_Main_Window` on release. `test-virtual-keyboard.ps1` passes
  (`virtual-keyboard.log`): the full Java→JNI→native chain completes without
  exceptions and the host keeps ticking. Actual keyboard visibility and closure remain unverified on the OS;
  later close requests reported access denied.
- MP3/AIFF audio smoke: `test-media-audio.ps1 -Codec all` passes WAV, MP3 and
  AIFF (`media-audio-mobile.log`, `-mp3.log`, `-aiff.log`). Fixtures are
  encoded locally by `tests/native/make_audio_fixture.cpp` (Media Foundation
  MP3, hand-written AIFF container); MP3 duration tolerance absorbs encoder
  padding (measured 2058 ms for a 2000 ms signal). Assertions cover metadata
  duration, decoded track, pause, seek and end-of-media — not audible output.
- GL/separate error 170 fixed (see the drag/drop section above):
  `test-drag-drop.ps1` now passes all four renderer/thread combinations.

## Session blockers resolved (2026-11-05)

Both environmental blockers from 2026-11-04 (the session-wide
`OpenClipboard` ERROR_ACCESS_DENIED and explorer's pointer-swallowing
`LockScreenBackstopFrame`) cleared after the user unlocked/restarted the
machine. The deferred fixtures were rerun and now pass:

- `test-clipboard.ps1` passes on Vulkan/safe (six consecutive runs) and on the
  packaged Runtime, covering CF_HDROP files, CF_DIB pixels, the ANSI-only URL
  fallback and custom-format round-trips in both directions, with the
  snapshot/restore guard verifying exact restoration
  (`clipboard-mobile.log`, `clipboard-mobile-runtime.log`).
- `test-drag-drop-external.ps1` passes on Vulkan/safe, OpenGL/safe and the
  packaged Runtime including the OLE custom-format assertions
  (`drag-drop-external-mobile-safe.log` and siblings).

The rerun surfaced and fixed four real defects rather than test noise:

- `ClipboardSnapshot.cs` `WideCharToMultiByte` P/Invoke lacked
  `CharSet.Unicode`, so the peer's ANSI URL fixture bytes were marshaled
  garbage; Java and native code were correct (the native ACP conversion was
  proven byte-exact with diagnostics before the fix was found).
- `dnd_helper.cpp` implemented no `EnumFormatEtc`, while inbound custom-format
  discovery legitimately requires enumeration (see the OLE section above).
- `QuantumClipboard.hasContent` stopped at the first HTML mime when checking
  for images, so rich content containing both HTML and an image reported no
  image; the upstream-style fix continues scanning remaining mimes.
- Windows clipboard transients are now absorbed, not asserted away: the peer
  retries a null `Clipboard.GetDataObject()` (documented when another process
  holds the clipboard), and the Godot scene retries its cross-API
  `DisplayServer.clipboard_get()` read for up to two seconds. Both keep the
  same exact-content assertions.

The packaged Runtime binary also needed a rebuild after the custom-format JNI
signature change; it is current again.

## Robot desktop validation (2026-11-04)

Source Editor/Runtime and Media-enabled SDK builds pass after adding GodotRobot
and native desktop capture/cursor calls. `test-robot.ps1` passes Vulkan/safe,
OpenGL/safe and packaged Vulkan/safe at 2× DPI: committed A text, button action,
wheel direction, mouse-coordinate conversion, scaled and physical capture sizes,
blue desktop pixels, WritableImage reuse and repeated captures. The fixture
rejects off-FX-thread Robot creation, non-finite coordinates and oversized capture.
Logs are `robot-mobile-safe.log`, `robot-gl_compatibility-safe.log` and
`robot-mobile-safe-runtime.log`. The actual desktop capture
`artifacts/reference/robot-desktop.png` was inspected and shows the committed A,
button and blue patch. It is a fixture capture, not final VFX desktop acceptance.

The same seven drag/drop cases also pass with `test-drag-drop.ps1 -Robot
-Renderer mobile`, using Windows-synthesized events rather than host injection
(`drag-drop-mobile-safe-robot.log`). The default injected fixture also passes.
Initial diagnostics found foreground denial and an IME candidate window covering
a click target; the fixture is topmost and explicitly commits/dismisses input
before continuing. No input-layout setting is changed. Mixed-monitor DPI,
physical keyboard/IME behavior, external OLE drag/drop and full VFX desktop
acceptance remain unverified; these results do not close the overall goal.

## Native file-dialog validation (2026-11-04)

Windows native open/multiple-open/save/directory selection is implemented.
The Media-enabled SDK and Runtime source builds pass. After correcting owner-chain
modality, all six `test-file-dialog.ps1` cases pass on Editor Vulkan/safe,
Editor OpenGL/safe and packaged Runtime Vulkan/safe. Checks include returned paths,
filter identity, native dialog class/process/owner, disabled ancestor windows,
restored owner-chain state, null on cancel/owner close, continued FX pulses and
zero final host-owned resources. Save selection does not create a file.

Packaged Vulkan/safe `-StopHost` also passes: the driver first observes an actual
native chooser, then the host stops, the chooser returns cancellation and cleanup
finishes. Logs are `file-dialog-mobile-safe.log`,
`file-dialog-gl_compatibility-safe.log`, `file-dialog-mobile-safe-runtime.log`
and `file-dialog-mobile-safe-runtime-stop.log`, with `.native`/`.stderr` companions
under artifacts/logs. The driver sends native button notifications; this is not
physical-input acceptance. Simultaneous/reentrant choosers are explicitly rejected
and remain a compatibility limitation. Full Glass/drag/drop acceptance stays open.

## URL clipboard work (2026-11-04)

JavaFX URI_TYPE now maps to Windows UniformResourceLocatorW, alongside existing
text/HTML/RTF. The fixture adds URL-only discovery, Unicode values, invalid NUL
rejection, clear and external Windows Forms read/write checks. Editor and
Media-enabled SDK source builds pass. The updated Java fixture compiles, but
the integration runner stops before launching Godot or writing clipboard data:
its native backup OpenClipboard call fails with Windows error 5 (access denied).
See `artifacts/logs/clipboard-url-preflight.log`. No system interoperability or
restoration PASS is claimed. Clipboard access failure does not block other goal work.

Extended on 2026-11-04: file lists (CF_HDROP), images (CF_DIB), ANSI-only URL
read fallback and `application/x-godot-custom-*` registered formats are now
implemented for the system clipboard (see glass-godot.md/bridge-protocol.md),
the probe and Windows Forms peer assert them in both directions, and the
runner's backup guard snapshots/restores CF_HDROP and CF_DIB as well as the
registered formats present at capture time. After the locked-session
`OpenClipboard` failure cleared, the integration run passes on Vulkan/safe
(six consecutive runs) and the packaged Runtime, including exact restoration
(2026-11-05); no clipboard content was cleared to bypass the guard.

## Historical review verification (2026-11-04)

Source OpenJFX Media SDK and integrated Godot Editor builds pass. Protocol tests,
Vulkan/OpenGL media-plane tests, and 24-player Vulkan churn with the AAC assertion
pass; churn finishes with zero host resources. The 1080p60 Editor review sample
records 60.059 MediaView draws/s, 601 compositions over 10,026.61 ms, and zero
focus loss/backpressure (`media-frame-benchmark-safe-1080p60-sample20.log`).
VFX records 59.954 compositions/s, 59.985 pulses/s, p95 18.654 ms and maximum
54.074 ms, also without focus loss/backpressure (`vfx-frame-benchmark-safe.log`).
These review runs do not revalidate every page, Runtime or the longer workloads;
the earlier evidence remains separately identified below. The D3D `-NoVSync`
runner now passes `-Dprism.vsync=false`; JVM property output and successful
playback were checked in `media-frame-benchmark-d3d-sample19-novsync.log`.

## Architecture and implementation requirements

| Objective section | Current evidence | Remaining acceptance |
| --- | --- | --- |
| 3.1, 5: sole Godot host and JavaFX thread semantics | JavaFXHost, Glass-Godot scheduler, native-window transport and Prism command queue; scheduler, host-stop, pulse-stop and shutdown probes | Broader timing/performance and physical interaction |
| Stage correction | Primary uses root Window; secondary Stage/Popup use force_native JavaFXNativeWindow. Native-stage, input, modality, owner lifetime, VFX window-control and churn probes | OS-desktop screenshots and real mixed-monitor behavior |
| 3.2, 4.1: GPU 2D primitives, glyphs, textures, clipping and blending | Prism-Godot BaseShader integration, bridge/render-target/composite probes, VFX 35-page GPU captures at scale 2 | Representative cadence passes; occasional long frames, earlier unexplained 33-FPS plateau and broader workloads remain open |
| Controls, CSS and FXML | Controls/CSS exercised by Stage/VFX fixtures; test-fxml.ps1 verifies FXMLLoader, fx:include, bundle/location injection, initialize, private handlers, relative CSS/GPU color, Chinese text input and a second independent Stage on GL/Vulkan/Runtime | Representative FXML coverage; arbitrary custom component/module/controller combinations are not exhaustive |
| 4.2: 2D effects | 39-case effects fixture, standard effect chains and all Blend modes, GL/Vulkan comparisons | Not every parameter/extreme combination; see prism-godot.md for supported paths |
| 4.3: per-node CanvasItem shader | GodotShaderEffect, node-shader fixture with uniforms, UVs, clip/opacity and chained effect | Additional sampler uniforms and geometry beyond input bounds are unsupported |
| 4.4: GodotView | Public Region/peer, live GPU SubViewport, resize/reload/clip/opacity and mouse/key/touch probes; combined scale/shear/translation passes GL/Vulkan/separate/Runtime with D3D clip reference | Logical-resolution output on HiDPI; arbitrary transform and physical interaction stress incomplete |
| 6: Glass adapters | Application/Window/View/Screen/Timer, window-addressed input, text/HTML/RTF clipboard, cursors and synthetic/native IME probes | See unsupported inventory below; physical IME candidate/conversion behavior unverified |
| 7: source builds | Editor, template_release Runtime, custom module/JNI bridge and source OpenJFX SDK builds; Media-enabled SDK now includes all four native Media libraries | WebKit excluded by user; godot-cpp is not used |
| 8: M0–M6 flow | Architecture, build scripts, module, standard Stage, NodeShader, GodotView and original VFX implementations exist | Milestones are not blanket-accepted while explicit gaps remain |

## Section 9 acceptance items

| Item | Evidence and limit |
| --- | --- |
| 1: real VFX startup | Source-built SDK + original VFX Intro; 35-page runs complete |
| 2–3: controls, positions, dimensions, hierarchy | Paired GPU captures with stock D3D; targeted native-window, popup, menu and table tests. Not exhaustive control coverage |
| 4: Chinese/English text and layout | Reference scene, text input/IME and table edit captures; physical IME remains open |
| 5–6: images, gradients, alpha, transforms, clips | Prism/effect/GodotView fixtures and page captures; representative coverage |
| 7: effects | 39-case GL/Vulkan image comparison evidence |
| 8: node shaders | Per-node fixture verifies shader output and uniform updates |
| 9–10: embedded Godot scene and mixed content | GodotView fixture verifies scene texture, sibling order, clip, opacity and input |
| 11: mouse, keyboard, focus | Host-injected interaction probes, including original VFX table, dialog, loading/cancel and animation graph. Physical-device acceptance missing |
| 12: resize and rendering | Native Stage/VFX resize, maximize/restore and render-scale fixtures; real monitor transitions missing |
| 13: no visible defects/flicker | GPU captures inspected, including full-page D3D triage; GPU motion and near-60 average cadence pass; OS-desktop visuals and occasional long frames remain open |
| 14: no sustained memory/GPU leak | 180-cycle no-forced-GC Stage tests; WinRT callback and Vulkan descriptor retention fixed; corrected 537-second real-Demo three-round soak, stable homepage native resources and final-zero cleanup |

Item 14 remains bounded evidence: actual process memory is now sampled over a
537-second real application workload; arbitrary-duration/driver memory remains
unverified. The most recent primitive/Stage
churn results are described in progress.md. Passing a resource-count check does
not prove the whole process is leak-free.

A real-Demo repeated 35-page forward/backward workload now records process
private/working-set memory, handle count, Java heap/natural GC and per-page native
resources. The corrected three-round run completed 205 observations and final-zero
cleanup. All three homepage endpoints have identical owned-resource/texture
counts; round-2/3 Godot static memory differs by -24 bytes. Actual engine private
memory in the latter half has median 2.29 GB and fitted slope +0.114 MB/minute,
within much larger page/allocator fluctuations. This does not show clear sustained
accumulation at the measured duration, but cannot exclude small leaks or other
workloads. Earlier console-launcher process samples are invalid and excluded.
See memory-validation.md for commands, timing and interpretation limits.

GPU animation motion passes the >=20-pixel centroid displacement check on
OpenGL/safe, Vulkan/separate, packaged Vulkan/separate and packaged Vulkan/safe.
Only newly completed presentations are sampled, so capture does not starve the
render queue. This proves visible GPU motion; the timing benchmark independently
measures cadence without readback.

The 2026-11-03 compact-media SDK ordinary Vulkan/safe (the interactive launcher's default)
reaches 58.654 completed compositions/s and 58.722 Java pulses/s, p95 18.535 ms
and maximum 128.103 ms, with zero focus loss/backpressure/upcalls. The preceding
R8 run reached 59.907 compositions/s, p95 18.229 ms, maximum 43.165 ms. The saved
post-AAC-fix native D3D comparison is 62.498 pulses/s, p95 16.728 ms, maximum
19.754 ms; earlier D3D runs also varied considerably. Native GPU presentations
are not independently counted. These results support near-native average
cadence for the tested VFX animation, with occasional long frames remaining.
They do not establish stable 60 FPS across all pages or physical display scanout.
See frame-benchmark.md for paired logs and the earlier unexplained 33-FPS plateau.

Seven render/scheduling switches and exclusive CPU shadow-image reuse are enabled
by default, with explicit `0` overrides. GPU region uploads and asynchronous
render-target texture proxies remain opt-in because consistent long-frame benefit
has not been demonstrated. The safe-mode trace has 1,324 CPU shadow reuses and
zero clones. Source-built Editor/Runtime functional coverage includes effects,
GPU motion, resize/render-scale, readback, transparent perimeter and resource
cleanup. See frame-benchmark.md for exact logs and progress.md for historical
experiments; superseded 3-49 FPS measurements are not the current default result.

The latest default Vulkan/safe regression also passes packaged Runtime transparent
perimeter, VFX scrolling, table editing, loading completion and cancellation,
plus the Editor VFX dialog test. These exercise real Demo actions after the
performance changes; they do not substitute for physical input acceptance.
Fresh 35-page Vulkan/safe captures complete at 2560x1600, scale 2, with final
tracked resources zero. The paired D3D contact sheet and both high-difference
table pages were visually inspected: no obvious new layout regression; random
table data/time differs as expected from VFX source. The comparison remains
triage rather than a blanket visual pass. See artifacts/reference/vfx-comparison-mobile.png
and vfx-pages-mobile/run.json.

Transparent Stage empty areas and the full GPU-image perimeter pass alpha checks,
including the latest packaged Vulkan/safe run. The user confirms transparency
and has explicitly asked to ignore the remaining white edge; white-edge/DWM
investigation is no longer an acceptance blocker or an active task. The last desktop-capture attempt
failed because @oai/sky could not be imported; no newer desktop capture is recorded. Existing GPU
captures and native-window behavior tests remain the available visual evidence.

## Known unsupported or unverified paths

Standard Stage icons are now implemented, including per-window replacement,
clear and hide/reshow. Seven-state tests inspect the installed native icon's
pixels and validate opaque/half-alpha colors, transparent corners and window
independence on GL/Vulkan and packaged Runtime. Desktop taskbar appearance is
not asserted. Native protocol bounds/order tests, Stage churn and Demo smoke pass.

Within the Glass platform capability inventory, system menus remain explicitly
unsupported; this is not an exhaustive list of limits in rendering or other APIs.
Virtual keyboard request/release reaches the Windows touch-keyboard API through
ITipInvocation; `test-virtual-keyboard.ps1` verifies Java-call completion and host
liveness, not visible appearance or closure. The latest close request reported
access denied; actual OS behavior remains a physical acceptance item. Image (CF_DIB),
file (CF_HDROP), ANSI-URL fallback and custom
(`application/x-godot-custom-*`) system clipboard formats are implemented and
their bidirectional integration runs pass on Vulkan/safe and the packaged
Runtime (2026-11-05). Application-local
drag/drop now has an implementation and a dedicated lifecycle fixture, and
cross-application OLE transfer passes the external endpoint fixture below.
Drag preview images register through the shell drag-image helper (see the
2026-11-06 section); the OS-rendered preview on screen and the in-window
portion of the gesture remain unverified/unrendered respectively. These are
distinct implementation states, not passing
adapters. Returning zero for the GL framebuffer or view offset
is not by itself evidence of a missing feature: those are GPU-command integration
contracts and must be assessed in context.

Prism-Godot explicitly rejects 3D geometry/material/mesh, depth/perspective targets,
MSAA and mipmaps. The requested rendering scope is 2D; 3D is outside it. Planar
YCbCr conversion now uses the stock GPU shader; color/alpha/padding probes pass.
Native Media libraries build, and silent PCM plus local MP4 MediaView playback
pass GL/Vulkan/Runtime, including video resize/clip/opacity checks. A focused
ten-second 30-FPS MP4 comparison measures 29.957 Prism draws/s on Godot versus
30.099 on native D3D. Vulkan/OpenGL Editor and Vulkan Runtime have completed 24-player churn
with final tracked resources zero. Encoded 1080p60 now passes the measured
>=55 draw/composition-FPS threshold on Editor/Runtime; arbitrary-duration and
all-codec Media/native-process stability remain unverified.
For a 2x-rate 30-FPS source, a bounded two-pending-frame fix removes pulse-boundary
replacement loss: three focused Godot trials measure 59.710/59.911/59.990 draws/s,
versus 60.066 with the same source fix on native D3D. Control/seek/replay and
24-player Vulkan cleanup regressions pass after this change. The subsequent
locally encoded 1080p60 fixture is documented in media-godot.md; independently
measured physical A/V synchronization remains unverified.
A pre-fix 120-player process-sampled Media run showed private-memory growth and
handle medians rising from 956.5 to 1040; native D3D reproduced it. Provider
metadata localized +1/player to Microsoft-Windows-MSMPEG2ADEC. DirectShow pin
search leaked a media-type enumerator, retaining its decoder; success/failure
COM releases are now balanced and the source Media SDK has been rebuilt.
Post-fix Godot Vulkan/safe 120 players plus 30 seconds idle pass pictures and final
GPU zero. ETW stays 313; handle block medians are 928/924/920/921/919. Private
memory warms up then plateaus: block medians 800.821/827.601/837.978/832.385/
834.902 MB; latter-half OLS -0.916 MB/minute. No forced GC is used. This accepts
the bounded churn regression for this MP4; arbitrary-duration/all-codec stability
remains unverified. The AAC regression assertion rejects pre-fix and accepts
post-fix evidence. Java threads stay 13.
See media-godot.md. WebKit is outside the user-confirmed scope. Uploads
into scene/render-target textures are deliberately restricted. No unsupported
exception should be described as an implemented feature.

## Section 11 delivery inventory

| Deliverable | Location / status |
| --- | --- |
| 1: modified file list | scripts/write-delivery-inventory.ps1 generates artifacts/change-inventory.json, including submodule-local changes and untracked files |
| 2: architecture changes | Repository README indexes architecture.md, native-module.md and bridge-protocol.md; obsolete pending claims for implemented Prism/effects/GodotView/windows corrected |
| 3: Prism description | prism-godot.md |
| 4: Glass description | glass-godot.md, ime-godot.md |
| 5: GodotView description | godot-view.md |
| 6: shader integration | node-shaders.md |
| 7: Windows build commands | build-windows.md and scripts/build-windows.ps1, scripts/build-vfx.ps1 |
| 8: build outputs | godot/bin, jfx/build/sdk, artifacts/vfx; selected hashes in generated inventory |
| 9: actual Demo screenshots | artifacts/reference/vfx-pages-* and targeted captures are GPU readbacks; OS desktop capture remains missing |
| 10: implemented/unimplemented list | This audit and subsystem documents; no final feature-completeness claim |
| 11: issues and recommendations | This audit and progress.md; finish compatibility gaps and physical/performance acceptance before final sign-off |

Earlier project work added drag/drop and Glass compatibility to acceptance.
Those project-level requirements remain recorded here; they must not be confused
with the current code-quality review of the fixed original changes and subsequent
repairs. The current review also considers performance and memory safety, with
FPS near 60 and occasional long-frame fixes explicitly deferred.

Remaining project-level acceptance includes desktop drag/drop and Glass adapters,
physical input/IME/window/DPI behavior and actual
audio/A/V synchronization, clipboard compatibility/restoration acceptance,
and reproducible cadence regressions. On 2026-11-10 the user explicitly renewed
permission for Robot and other tests. This permits the current serial physical-input
validation run; it does not itself prove any remaining acceptance item.
Source-build coverage exists;
it is not an unstarted milestone. Keep unsupported Glass features distinct from
the original explicitly requested items: system menus, file dialogs, Robot,
virtual keyboard and drag/drop are additional compatibility work. Robot and file
dialog evidence is recorded separately; it does not close the remaining gaps. Bounded memory checks pass; arbitrary-duration/all-codec certainty
is a limitation, not an achievable infinite test requirement. Complete OS visual
acceptance when computer-use access is available. The previous computer-use initialization failed
because @oai/sky was unavailable; no alternative hidden UI automation was used.
