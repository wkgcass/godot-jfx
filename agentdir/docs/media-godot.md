# media-godot — historical verification

The Windows workspace copies of the Media churn reports archived on 2026-11-20
are under `agentdir/artifacts/reference/windows-workspace-20261120/`. The commands
below write fresh reports under `artifacts/reference/`.

## Media texture disposal and churn

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
RGBA run is archived under `agentdir/artifacts/reference/` with a `-rgba` suffix. Packaged Runtime passes its own
24-cycle check against this rebuilt SDK.

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
`agentdir/logs/media-foundation-lifecycle.log`. Reproduce with JDK 25:

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
`agentdir/artifacts/reference/media-churn-mobile-cycles120-process-idle30-types-providers-rgba.json`.
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
`agentdir/logs/media-churn-mobile.log` and `agentdir/artifacts/reference/media-churn-mobile.json`.
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
