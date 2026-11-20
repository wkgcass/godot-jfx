# Media support

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


Media is required by the latest user clarification. WebKit is excluded. The
earlier instruction excluding both is superseded.

The measurements below retain their original workload, logs and historical build
context. They are not a fresh rerun of every later host/JFX change. Current review
validation and remaining limits are tracked in acceptance-status.md and
review-open-items.md; a source or binary change requires relevant verification
before reusing an old result as evidence for that new build.

## Encoded 1080p60 validation (2026-11-03)

`make-media-fixture.ps1` builds a local Windows Media Foundation Sink Writer
fixture generator with the configured MSVC/Windows SDK. It encodes 960 distinct
moving-pattern frames as 1920x1080 H.264 Main, 60/1 FPS, 16 seconds, then checks
the native video type and all 960 samples with an independent Source Reader.
The benchmark verifies the MP4 and generator source hashes. No downloaded encoder
or prebuilt media SDK is used. Reproduce sequentially:

```powershell
.\scripts\make-media-fixture.ps1
.\scripts\benchmark-media-frames.ps1 -Native60
.\scripts\benchmark-media-frames.ps1 -Native60 -Runtime -ClockSkew -Sample 12
.\scripts\benchmark-media-frames.ps1 -Native60 -Backend d3d
```

The source SDK uses compact single-channel transfers and R8 media-plane storage
(protocol operations 27/28). This removes Java RGBA expansion and cuts plane
storage/transfer by four compared with RGBA. Replacing the entire plane also
avoids copying/blitting the old CPU image. MediaView is 640x360 logical
pixels in both backends; decoding/upload remains 1920x1080. These measurements
do not establish full-resolution-window scanout performance.

The original 1080p60 Godot run drew 23.590 FPS with 972 queue backpressure
events; the matched native D3D control drew 60.051 FPS. Intermediate compact/R8
runs still plateaued near 33 FPS, also reproduced by a small Oracle fixture at
2x (`media-frame-benchmark-safe-rate2-sample13.log`). Thus traffic reduction
alone does not explain the cadence change. Later same-build alternating phase
observers off/on/off drew 60.140/60.163/60.145 FPS, with 601 host compositions
per sample and zero backpressure/focus loss (1080p60 samples 9/10/11). Observer
instrumentation is not required to reach 60. The earlier plateau's trigger is
unresolved and must remain visible if it recurs.

Packaged Vulkan/safe sample 12 draws 60.037 FPS and composes 601 frames over
10.016985 seconds, with zero backpressure/focus loss and launch upcalls. Software
media-clock minus latest-frame timestamp has median 44.996 ms, p95 46.014 ms,
first/last-half means 44.986/45.207 ms. This is bounded software timing evidence,
not physical audio/display synchronization; the generated fixture has no audio.
Log: `media-frame-benchmark-safe-1080p60-sample12-clock-runtime.log`.
After the explicit-disposal fix below and a fresh source SDK build, packaged
Runtime sample 14 draws 60.137 FPS, with 601 compositions over 10.016451 seconds,
zero backpressure/focus loss and no phase observers. Log:
`media-frame-benchmark-safe-1080p60-sample14-runtime.log`.

Both frame benchmark scripts now default to Godot and print their backend.
Media and VFX probes report the actual Glass and Prism class names; runners
reject a different backend. Native D3D requires explicit selection and is a
comparison. With `-Backend d3d -NoVSync`, the runner now passes
`-Dprism.vsync=false`; without the switch it preserves the native default.
The 2026-11-04 check verified the JVM property and a successful benchmark in
`media-frame-benchmark-d3d-sample19-novsync.log`. Native60 at rate 1 additionally requires >=55 MediaView draws/s;
Godot must also compose >=55/s with zero backpressure. A measurement-completed
marker alone is not performance acceptance. Java pulse/MediaView draw counts
and Godot composition counts are separate from physical display refresh.

Reducing per-frame Java allocations exposed a second lifetime issue: cached
PrismMediaFrameHandler planes were released only after GC, because MediaPlayer
dispose never called its existing releaseTextures path. dispose now removes
the provider's handler from the weak cache and queues texture disposal on the
render thread. It does not free shared planes when just one MediaView detaches,
nor change pause/stop/replay behavior. The churn fixture reuses a WritableImage
destination so each picture check does not introduce a fresh snapshot RTT cache.
Player, MediaView and decoder lifetimes remain fresh; thresholds are unchanged
and no forced GC is used. The saved pre-cleanup R8 run fails at cycle 7 with
72 owned resources. Rebuilt-SDK packaged Runtime completes all 24 cycles with
23 owned resources at every checkpoint from cycle 3 onward, about 4.64 MB of
GPU texture memory and final_owned=0. AAC provider deltas remain empty after
the first census. Evidence: `media-churn-mobile-runtime-cycles24-process-types-providers.log`
and the `-r8-before-cleanup.log` failure. These snapshots are bounded evidence;
they do not prove arbitrary-duration/all-codec memory stability.

The final R8/explicit-disposal 120-cycle Vulkan/safe run plus 30 seconds idle
also passes every decoded-picture, resource and AAC assertion. GPU resources
stay 23 and texture memory stays 4,644,864 bytes, with final zero. ETW stays
313 and post-baseline provider deltas are empty. Handle block medians are
928/920/918.5/919/917; private-MB block medians are
792.062/803.066/809.497/807.342/809.798. Latter-half private memory spans
787.751–826.208 MB, median 809.218 MB, OLS +0.196 MB/minute within the much larger
allocator variation. Idle ends at 812.556 MB and 900 handles; 33 natural GCs,
no forced GC. Godot static memory changes by only 16 bytes in the latter half.
This supports bounded stability for the tested workload; a small fitted slope
alone cannot certify or disprove a leak. Evidence stem for that run:
`media-churn-mobile-cycles120-process-idle30-types-providers`; raw reports and
the `.analysis.json` summarize the same PID and all 120 checkpoints. The earlier
RGBA run is preserved with a `-rgba` suffix. Packaged Runtime passes its own
24-cycle check against this rebuilt SDK.

## Source build

Build the JavaFX SDK with Media enabled:

```powershell
.\scripts\build-windows.ps1 -Target jfx
```

The script uses the existing MSYS/UCRT64 toolchain and a workspace-built,
checksum-pinned makedepend. It runs the upstream Gradle SDK task with Media enabled
and WebKit disabled. The source-built SDK now contains `jfxmedia.dll`,
`glib-lite.dll`, `gstreamer-lite.dll` and `fxplugins.dll`. No binary JavaFX SDK or
prebuilt Media DLL substitutes for these sources. See build-windows.md for tool
path conversion, linker selection and dependency-scan details.

For module-path launches, the Java application resolves `javafx.media` and enables
native access for `javafx.graphics` and `javafx.media`. The Demo Shadow JAR bundles
the platform Media libraries and declares native access in its manifest.
JavaFX MediaPlayer handles playback through the source-built native media
pipeline. Glass and JavaFX continue to handle UI events on their existing threads.

## Verified audio workload

```powershell
.\scripts\test-media-audio.ps1
.\scripts\test-media-audio.ps1 -Renderer gl_compatibility
.\scripts\test-media-audio.ps1 -Runtime
.\scripts\test-media-audio.ps1 -Codec all
```

The script generates a two-second mono 16-bit 44.1-kHz silent PCM WAV locally.
`-Codec mp3/aiff/all` additionally builds `tests/native/make_audio_fixture.cpp`
with the MSVC toolchain and encodes a two-second 440 Hz sample: MP3 through
Media Foundation, AIFF as a hand-written big-endian container (Python 3.14 no
longer ships `aifc`). The probe's duration expectation/tolerance come from
`GODOT_JFX_MEDIA_EXPECT_MS`/`GODOT_JFX_MEDIA_TOLERANCE_MS`; MP3 gets 300 ms to
absorb encoder padding (measured 2058 ms against the 2000 ms signal).
MediaAudioProbe checks the decoded track, duration, advancing playback clock,
pause stability, seek position while paused, resumed end-of-media callback and
dispose. Playback is muted. WAV/MP3/AIFF pass on Vulkan/safe; earlier GL/safe
and packaged Vulkan/safe WAV runs pass,
and the Godot host returns tracked GPU resources to zero. Logs are
`artifacts/logs/media-audio-*.log`. This proves native playback operation; it does
not test audible speaker output, every codec, streaming or long-running native
Media memory stability.

## Verified video workload

Prism-Godot allocates three/four-plane YCbCr 4:2:0 frames as BYTE_ALPHA/R8 textures
and uses the existing JavaFX YV12 shader on the GPU. Encoded plane dimensions
remain separate from visible dimensions. Frames without alpha bind the unused
alpha sampler to luma; the stock shader's zero alpha scale prevents sampling it.
Allocation failures dispose partial planes and balance the MediaFrame hold.
Packed frames allocate only the visible picture extent, while upload preserves
the decoder's source stride. This prevents edge filtering into encoded padding.
Allocation does not upload the first frame twice; the media handler owns upload.

```powershell
.\scripts\test-media-planes.ps1
.\scripts\test-media-planes.ps1 -Renderer gl_compatibility
.\scripts\test-media-video.ps1
.\scripts\test-media-video.ps1 -Renderer gl_compatibility
.\scripts\test-media-video.ps1 -Runtime
.\scripts\test-media-video.ps1 -NativeD3D
```

The plane tests pass on Vulkan/safe and GL/safe: red/green/blue conversion,
half-alpha output, read-only padded buffers, visible cropping and switching from
four planes to three. The extended plane fixture also checks a packed
INT_ARGB_PRE frame with 6x6 visible pixels, 8x8 encoded extent and 40-byte row
stride, exact green edge pixels and balanced holds on invalid dimensions.
Environment setup downloads and verifies two MediaView inputs. The Oracle MP4
referenced by OpenJFX's HelloMedia also serves the AAC and frame-rate tests.
`Lk.mp4` is a silent 1920×1080, 30 FPS H.264 clip used for playback and
resize regression. The playback checks on the Oracle sample have passed on
Vulkan/safe, GL/safe and packaged Vulkan/safe. They cover ready dimensions,
play/pause/resume, nonuniform decoded picture, resized/clipped half-opacity
pixel checks and disposal with final host resources zero. GPU snapshot PNGs are
in `artifacts/reference/media-video-*.png`; they are not OS desktop captures.

The resize probe pauses playback and compares a 320×180 MediaView transformed
to 200×120 with a MediaView fitted directly to 200×120. Both snapshots sample
the same output pixel centers. It then clips the latter to 160×100, applies 50%
opacity and checks every visible pixel against its opaque value blended with
the magenta background. Pixels outside the clip must remain magenta.

In the Windows Lk diagnosis, the old comparison used (100,65) in the original
snapshot and (70,50) after resizing. Godot Vulkan and native D3D both returned
RGB (222,166,236) at the original point and (126,67,142) at the resized opaque
point on the same paused frame. The two ways to resize produced identical
snapshots on both backends. In the clipped region, the largest blend error was
one channel level on either backend.

The video fixture additionally pauses/seeks to 1.2 seconds before the end, resumes,
requires the end event, stops, waits for confirmed STOPPED and starts again. It
must observe a PLAYING timestamp near zero before checking the restarted decoded
picture. This exposed an upstream MediaPlayer bug also reproduced with native
D3D: `isEOS` was not reset by `onStop`, so `getCurrentTime()` kept returning the
previous end time after replay. The source now clears that flag on the FX thread
when stop is confirmed, before notifying STOPPED listeners. The fixture checks
the actual clock and picture rather than accepting status alone; replay PNGs are
saved alongside the original captures. Native D3D mode provides the same control
regression without the Godot adapter.

## Video frame-rate evidence

`benchmark-media-frames.ps1 -Backend d3d` and `-Backend safe` run the same local
MP4 at 640x360, warm up for two playback seconds and measure ten wall-clock
seconds without snapshots. The test reads upstream MediaView counters via a
process-local module opening. These count frame delivery and Prism draws, not
independent display scanout or unique displayed frame timestamps. Both JavaFX
and native-host focus observations must remain focused for an accepted sample.

The sample MP4's video `mdhd`/`stts` tables contain 2,294 frames, time scale 15,360
and a constant 512-tick duration: exactly 30 FPS. The recorded focused measurements were:

| Backend | Seconds | Delivered / Prism-drawn frames | Draws/s |
| --- | ---: | ---: | ---: |
| Source SDK, native D3D | 10.000349 | 301 / 301 | 30.099 |
| Source SDK, Godot Vulkan/safe | 10.014261 | 300 / 300 | 29.957 |

Godot reports 300 presentation submissions, zero backpressure, 300 JNI submits
taking 95.496 ms total, 1,806 metadata calls taking 8.069 ms total and zero Java
launch upcalls during measurement. Tick-wait time is blocking wait time summed
across calls, not CPU cost. The native media counter and Godot measurements have
slightly different boundaries because title changes cross the command queue.
Logs: `artifacts/logs/media-frame-benchmark-{d3d,safe}.log`.

This bounded 30-FPS workload runs within about 0.5% of native D3D draw rate.
It does not establish 60-FPS video, all codecs, larger resolutions or sustained
playback behavior. JavaFX pulse rate is intentionally not used as video FPS.

### Two-times playback diagnostic and bounded-frame buffering fix

`benchmark-media-frames.ps1 -Backend safe -Rate 2 -Sample N` and the equivalent
`-Backend d3d` request 2x playback of the same 30-FPS source. This exercises a
nominal 60-frame/s delivery load, not a native 60-FPS encoded stream. Ten-second,
focused D3D trials measured 53.699, 53.297 and 53.047 draws/s. Godot trials measured
58.596, 59.011, 40.135, 59.615, 46.830 and 41.638 draws/s. All retained approximately
60 JavaFX pulses/s with zero host backpressure. Samples 2 onward verify roughly
20 seconds of media time advanced in ten wall-clock seconds.

The benchmark now also counts raw VideoRendererListener callbacks without holding
or reading video buffers. Instrumented Godot samples 4/5/6 receive 601/600/601
callbacks, but MediaView reports 597/469/417 delivered-and-drawn frames. This
localized the loss before Prism drawing, between media callback delivery and FX
view updates; at that stage it did not identify whether callback bursts, pulse alignment,
frame replacement or a concurrency problem is responsible. JNI/GPU backpressure
is not observed in these samples. Before the fix below, stable near-60 video was **not accepted** on the
basis of the best sample. Logs preserve every trial under
`media-frame-benchmark-*-rate2[-sampleN].log`; a benchmark PASS means successful
measurement, not meeting a frame-rate threshold.

Subsequent timing histograms found decoder intervals clustered around 8–12 and
20–25 ms while Godot pulses stay around 16.7 ms. Before the fix, one sample had
13 intervals containing two callbacks and forwarded exactly 13 fewer frames:
the single pending frame slot discarded frames at pulse boundaries.

MediaPlayer now retains at most two pending frames and consumes one per pulse.
If the consumer falls behind, only the newest two are retained, so the queue
cannot grow. Seek/release clears pending references; backwards timestamps discard
pending frames from the previous timeline. Publication and consumption share
renderLock, replacing the unsynchronized dirty flag. A queued second frame requests
the next pulse. This can retain one additional native decoded frame and introduce
one extra queued frame of presentation delay; A/V synchronization has not been
independently measured.

After rebuilding, focused Vulkan/safe samples 9/10/11 achieve **59.710, 59.911 and
59.990** Prism draws/s. Sample 10 has 182 pulse intervals with two callbacks yet
draws all 600 received frames; sample 11 has 120 such intervals and draws 601
frames. Backpressure remains zero. Native D3D sample 9 with the same source fix
measures 60.066 draws/s. Tiny count differences at measurement boundaries can
include a frame already pending when counters start. These results establish
near-60 performance for this bounded 2x, 640x360 presentation workload, not every
codec, native 60-FPS source or physical display scanout.

### Software clock versus selected video frame

`benchmark-media-frames.ps1 -ClockSkew` adds an explicitly separate diagnostic.
On each AnimationTimer callback it obtains a held reference to the currently
selected video frame, reads its PTS and the native media presentation clock, then
releases the frame in a finally block. It never reads the pixels. The reported
wall-time-equivalent offset is `(nativeClock - framePTS) * 1000 / playbackRate`.
This observes an FX sampling point, not GPU completion, display scanout or audio
hardware output. These diagnostic runs are separate from the FPS-only logs.

| Backend / rate | Median offset ms | p95 ms | Max ms | First / last half mean ms | Draws/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Godot Vulkan / 1x | 104.082 | 124.082 | 127.415 | 103.382 / 103.583 | 29.999 |
| Native D3D / 1x | 94.082 | 117.415 | 124.082 | 95.536 / 95.529 | 29.997 |
| Godot Vulkan / 2x | 64.082 | 70.748 | 84.082 | 65.682 / 64.370 | 59.907 |
| Native D3D / 2x | 64.082 | 77.415 | 80.748 | 57.043 / 69.740 | 59.905 |

Each focused measurement lasts ten seconds. The Godot offsets do not exhibit
growing backlog over these samples; 1x differences include sampling/pulse phase
and cannot be attributed solely to the new queue. Both backends use the current
source fix. These results do not prove physical lip synchronization. Exact logs:
`media-frame-benchmark-{safe,d3d}[-rate2]-clock.log`.

## Historical process-growth investigation (before the AAC/R8 cleanup fixes)

The results below record earlier states, not the current acceptance status.
The AAC reference leak was subsequently fixed and bounded 120-player regression
checks pass, as documented above. Historical commands may now produce post-fix
results; preserve archived logs when comparing. Remaining acceptance concerns
physical audio/A/V synchronization and broader workloads, not the resolved
per-player AAC retention.

### Extended process sampling: growth observed before the fix

The runner now supports `-Cycles 120` and collects current-process metrics from a
test-only Java FFM helper, using Windows GetCurrentProcess,
K32GetProcessMemoryInfo and GetProcessHandleCount. It only queries its own host
process; there is no external process control or forced termination. A 24-cycle sampler check and a 120-cycle Vulkan run both completed.

The 120-cycle run lasts 336.447 seconds, with 51 natural GCs and final tracked GPU
resources zero. However, **native resource stability is not accepted**: private
memory block medians (24 cycles each) are 803,973,120 / 829,464,576 / 837,468,160 /
839,608,320 / 845,330,432 bytes. The latter-half fitted slope is approximately
+4.716 MB/minute. Handle block medians are 956.5 / 973.5 / 993.5 / 1018 / 1040,
with the final block ranging 1028–1053. Godot tracked GPU/static resources still
recover, so those counters alone miss this growth. Decoder/runtime allocation,
delayed cleanup and other process resources have not yet been isolated.

Commands and evidence:

```powershell
.\scripts\test-media-churn.ps1 -Cycles 120
python scripts/analyze-media-churn.py artifacts/reference/media-churn-mobile-cycles120-process.json
```

The JSON and `.analysis.json` preserve every post-dispose checkpoint. These are
not continuous peak samples; trend analysis is separate from the runner's
playback/cleanup result. The shorter historical results below do not override
the extended run's unresolved growth.

Isolation with `test-media-churn.ps1 -NativeD3D -Cycles 72 -SettleSeconds 30`
reproduces growth without Godot. The same SDK and MP4 complete all 72 decoded
picture checks. Private-memory block medians are 501,757,952 / 511,090,688 /
537,862,144 bytes; handle medians are 861.5 / 908.5 / 929.5. Java thread count is
13 at every checkpoint. During the final 30-second idle period, handles fall from
941 to 923 after 20 seconds but stay there; private memory changes only from
541,659,136 to 541,450,240 bytes. Some cleanup is delayed, but the remaining
growth is not explained by that wait. This narrows investigation to shared
JavaFX/Windows media or runtime behavior; it does not prove a particular backend
allocation is leaking or compare leak rates fairly across different run lengths.

The runner now records monotonic process-sample time and Java thread count, and
can wait 0/30/60 seconds after disposal without forcing GC. Idle samples use
`cycle` as elapsed idle seconds and are separate from numbered player cycles.
Native D3D runs have no Godot GPU samples, represented as unavailable rather than
fabricated zeros. Evidence: `media-churn-mobile-d3d-cycles72-process-idle30` log,
JSON and analysis JSON. Next investigation is retained Windows handle types and
their media-backend lifetime.

Optional `test-media-churn.ps1 -HandleTypes` now samples current-process handle
types at cycles 1/12/24 and every post-dispose idle checkpoint. The test uses
PSS handle snapshots with NtQueryObject type fallback; snapshots and walk markers
are freed. It does not inspect other processes or change antivirus settings.
`analyze-media-handles.py` preserves counts and first-to-last deltas. Native D3D
24-cycle evidence (`media-churn-mobile-d3d-cycles24-process-idle30-types.log`)
shows EtwRegistration 329/340/352, still 352 after 30 seconds idle: one retained
registration per additional player. Thread/event counts partially recover.
The provider and relation to private-memory growth remain unknown; this is not
yet a source-level diagnosis or a Godot acceptance result. The runner explicitly
prints its backend so native comparison runs are identifiable.
The matching Godot Vulkan/safe 24-cycle run also passes picture checks and ends
with `final_owned=0`, but EtwRegistration grows 314/325/337 and remains 337 after
30 seconds idle. Evidence: `media-churn-mobile-cycles24-process-idle30-types.log`
and its `.handles.json`, plus process JSON/analysis. Both backends therefore
reproduce the same +23 registration delta across cycles 1–24. No attribution to
a specific DLL or leak-free claim follows from this comparison.

`-AudioOnly` isolates the same churn lifecycle using a generated two-second
mono PCM WAV, checks audio-only track metadata/duration and advancing playback,
and does not create a MediaView. The default MP4 path still checks decoded pixels.
Godot Vulkan 24-cycle PCM plus 30-second idle passes: EtwRegistration stays 227
at every census; latter-half private memory ranges 781.541–781.738 MB, with
15 tracked resources and 4,296,704 texture bytes throughout that half. Final host
resources are zero. Private memory after idle is 774.197 MB. These bounded
observations narrow the per-player ETW growth to paths added by MP4 (demux and/or
compressed audio/video decoding), not specifically the video decoder. They do
not establish long-run leak freedom or audible output. Evidence stem:
`media-churn-mobile-pcm-cycles24-process-idle30-types` (log, process analysis and
handle analysis). Native pipeline source selects `wavparse` for WAV and
`mfdemux`/`dshowwrapper` for this MP4 path, with a shared DirectSound sink.
After adding this mode, default Godot MP4 churn was rerun for 24 cycles and
passes picture checks/final zero resources; ETW again grows 314 to 337. Evidence:
`media-churn-mobile-cycles24-process-types`.

A standalone `MediaFoundationLifecycleProbe` also performs 24 balanced
MFStartup/MFShutdown pairs on its COM-initialized main thread, without JavaFX,
readers or codecs. ETW stays 103 before startup and after cycles 1/12/24; all
HRESULTs succeed. This rules out bare repeated startup/shutdown as a sufficient
reproducer on this machine, not every MF lifetime issue. Log:
`artifacts/logs/media-foundation-lifecycle.log`. Reproduce with JDK 25:

```powershell
& "$env:JAVA_HOME/bin/javac.exe" -d artifacts/reference tests/reference/CurrentProcessHandles.java tests/reference/MediaFoundationLifecycleProbe.java
& "$env:JAVA_HOME/bin/java.exe" --enable-native-access=ALL-UNNAMED -cp artifacts/reference MediaFoundationLifecycleProbe
```

The test follows the paired calls required by Microsoft's
[MFStartup](https://learn.microsoft.com/en-us/windows/win32/api/mfapi/nf-mfapi-mfstartup)
and [MFShutdown](https://learn.microsoft.com/en-us/windows/win32/api/mfapi/nf-mfapi-mfshutdown)
documentation. No native initialization policy has been changed.

Passing the MP4 path to `MediaFoundationLifecycleProbe` additionally creates a
Windows Source Reader from the file and releases its COM interface each cycle,
before MFShutdown. All 24 releases return zero references. ETW rises from 122
before first use to 162 after cycle 1, then stays 162 at cycles 12 and 24.
Evidence: `media-foundation-reader-lifecycle.log`. This tests reader open/close,
not reading samples, JavaFX's custom IMFByteStream, or codec playback; those
paths remain candidates. The ABI/ownership follows
[MFCreateSourceReaderFromURL](https://learn.microsoft.com/en-us/windows/win32/api/mfreadwrite/nf-mfreadwrite-mfcreatesourcereaderfromurl).

The optional `-Providers` diagnostic implies `-HandleTypes`. It uses read-only
EnumerateTraceGuidsEx metadata, filters registrations to the current PID, and
records changes since the preceding census (the first delta is the baseline).
It does not enable an ETW session. The provider census can differ slightly from
the handle census because these are sequential observations with different scope.
The Godot 24-cycle pre-fix run identifies all +23 registrations as provider
`51311de3-d55e-454a-9c58-43dc7b4c01d2`; local `logman query providers` identifies
this as `Microsoft-Windows-MSMPEG2ADEC`. Registration changes at cycles 12 and 24
are +11/+12, with no further change during 30 seconds idle. Evidence stem:
`media-churn-mobile-cycles24-process-idle30-types-providers-before-fix` and
`media-aac-provider-identification.log`.

Inspection of `dshowwrapper_get_pin`'s media-type overload found two unbalanced
COM paths: a matching media type returned the pin without releasing its
IEnumMediaTypes enumerator, and EnumMediaTypes failure returned without releasing
the pin. Both releases have been added; decoder lifetime validation follows below.

After rebuilding the source Media SDK, Godot Vulkan/safe 24 cycles plus 30 seconds
idle pass picture checks and final zero GPU resources. EtwRegistration stays 313
at cycles 1/12/24 and all idle checkpoints; provider counts have no delta after
the initial census. The latter-half private-memory range is 793.887–811.020 MB;
30-second-idle private memory is 816.005 MB. This fixes the measured AAC
registration retention, while longer memory-trend validation is still required.
Evidence uses the same stem without `-before-fix`. The analyzer option
`--require-stable-aac` rejects the saved pre-fix log and accepts the post-fix log;
its result is limited to the identified provider, not all native memory.

The post-fix 120-cycle Vulkan/safe follow-up also passes, followed by 30 seconds
idle. ETW stays 313 and AAC provider changes stay empty after the first census.
Handle medians over 24-cycle blocks are 928/924/920/921/919, replacing the
pre-fix rising trend. Private-memory medians are 800.821/827.601/837.978/832.385/
834.902 MB; latter-half range is 805.421–838.697 MB, OLS -0.916 MB/minute.
Idle ends at 834.933 MB and 905 handles. All pictures pass; final host resources
are zero. This supports bounded post-warmup stability for the tested MP4/churn
workload, with no forced GC; it does not prove stability for every codec or
unlimited duration. This earlier RGBA evidence stem is preserved as
`media-churn-mobile-cycles120-process-idle30-types-providers-rgba`.
Packaged Vulkan/safe Runtime also passes 24 players after this fix, with zero
retained AAC registrations at cycles 1/12/24 and the idle checkpoint, and final
host resources zero (`media-churn-mobile-runtime-cycles24-process-types-providers`).
When `-Providers` is selected, the runner now invokes the AAC stability check and
fails if that provider accumulates; `aac_registration_stable` is recorded separately
from functional playback and broader memory-trend acceptance.
The rebuilt SDK also passes OpenGL 24-cycle churn with the enforced AAC check,
and fresh packaged Vulkan/safe PCM/video control tests. A fresh rate-2 Godot
benchmark submits 599 drawn frames in 10.000016 seconds (59.900/s), with 600
callbacks and zero focus loss/backpressure (`media-frame-benchmark-safe-rate2-sample12.log`).
This is a 30-FPS source played at 2x; it does not certify native 60-FPS encoded
content or hardware audio/display synchronization. VFX regressions and current
near-60 animation results are recorded in frame-benchmark.md.

This covers a real local MP4 and PCM audio, not every codec or network streaming.
Arbitrary-duration/all-codec Media stability and physical audio output remain
unverified. Encoded 1080p60 measurements are recorded above.
After the user reported antivirus deletion of the initial churn runner, the runner
was simplified to direct engine invocation without process polling or forced
termination. It remained present and `test-media-churn.ps1` passed Vulkan/safe:
24 fresh players decode and render, detach and dispose over about 67 seconds,
with a 256-MiB heap and no forced GC. Each cycle checks a decoded picture; three
display sizes recur. All 24 checkpoints were collected, 11 natural GCs occurred,
and final host resources were zero. After warmup, tracked resources range 32–52,
texture memory 6,811,648–8,773,632 bytes, and Godot static memory
65,557,586–67,264,738 bytes. Recovered checkpoints repeatedly return to 32 resources
and approximately 65,557,598 static bytes. No sustained cycle-by-cycle growth was
observed in these metrics. That early runner did not sample whole-process private
memory; the current runner does. These historical counters alone did not rule
out native decoder leaks. Evidence is in
`artifacts/logs/media-churn-mobile.log` and `artifacts/reference/media-churn-mobile.json`.
No antivirus exclusions or protection changes were made; the detection reason is
still unknown, and successful execution does not establish its cause.

The same 24-cycle fixture also passes `test-media-churn.ps1 -Runtime` and
`test-media-churn.ps1 -Renderer gl_compatibility`. Runtime takes about 66.7 seconds;
GL takes about 67.3 seconds. Both record 11 natural GCs, 32–52 tracked resources
after warmup, repeated recovery to 32, and final teardown to zero. Runtime texture
memory ranges 6,811,648–8,773,632 bytes; GL ranges 10,318,563–12,434,403 bytes.
GL recovered static memory is 56,274,228 bytes. The isolated run's static-memory
counter is unavailable: `Memory::get_mem_usage()` returns zero without
`DEBUG_ENABLED`, so its zero readings are not memory-usage evidence. Reports
include `static_memory_available` to distinguish this case. All three workloads
remain bounded churn tests, not whole-process or hours-long leak certification.
The runtime still uploads decoded planes; it does not claim decoder-to-GPU
zero-copy integration. Synthetic alpha-video planes do not prove an alpha codec.

## macOS arm64 notes (2026-11-16)

The macOS port runs the same Godot-hosted probes through
`scripts/test-media-planes.sh`, `scripts/test-media-audio.sh`,
`scripts/test-media-video.sh` and `scripts/test-media-churn.sh`. Differences
from the Windows runners, all observable in the scripts:

- Audio fixtures: the WAV silence fixture keeps the Python generator. The MP3
  tone is encoded with ffmpeg/libmp3lame and the AIFF tone with `afconvert -f
  AIFF -d BEI16` (AIFF stores big-endian PCM), replacing the Media Foundation
  based `tests/native/make_audio_fixture.cpp`; both are verified with ffprobe
  (44100 Hz) before playback. Durations and tolerances are unchanged.
- The AVFoundation backend (OSXPlatform) handles MP3/AIFF/MP4 on macOS. Its
  `setCurrentTime:` used `CMTimeMakeWithSeconds(time, 1)`, quantizing seeks to
  whole seconds; the probe's 1200 ms +/-100 ms seek check failed. The timescale
  is now 600, the usual AVFoundation choice.
- AVF decodes H.264 to packed YCbCr 4:2:2 (`BYTE_APPLE_422`), which the Godot
  texture path does not accept. `GodotResourceFactory.createTexture(MediaFrame)`
  and `GodotTexture.update(MediaFrame)` now convert such frames to
  `INT_ARGB_PRE` through the existing `CVVideoFrame::ConvertToFormat` path,
  the same fallback J2D/SW use. The YUV multi-plane R8 path still serves
  `MULTI_YCbCr_420` without conversion.
- `CurrentProcessMemory` (media churn process samples) cannot use FFM
  downcalls to `proc_pid_rusage`/`proc_pidinfo` on the pinned JDK: Temurin
  25.0.5+8 on aarch64 crashes with C2/metaspace corruption (`compiledIC
  "stub not found"`, `ChunkPool` SIGSEGV) shortly after such downcalls, also
  reproducible standalone outside Godot. The macOS branch therefore samples
  `ps` RSS (reported as both working set and private bytes) and counts
  `/dev/fd` entries for handles. Pass criteria are unchanged; the samples are
  trend-analysis data, not acceptance gates.
- `--runtime`, `--handle-types`/`--providers` (PSS/ETW census) and the D3D
  comparison mode remain Windows-only; the macOS scripts reject them
  explicitly. `make-media-fixture.ps1` (1080p60 benchmark fixture) is
  Windows-only and unused by the macOS batch.
