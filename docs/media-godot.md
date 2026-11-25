# Media support

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


Media is required by the latest user clarification. WebKit is excluded. The
earlier instruction excluding both is superseded.

The measurements below retain their original workload, logs and historical build
context. They are not a fresh rerun of every later host/JFX change. Current limits are tracked in [acceptance status](acceptance-status.md).
The [archived review](../agentdir/docs/review-open-items.md) documents the original verification; a source or binary change requires relevant verification
before reusing an old result as evidence for that new build.

## Encoded 1080p60 validation (2026-11-03)

Run the fixture generator once from the repository root on Windows. It builds
`tests/native/make_media_fixture.cpp`, encodes and verifies 960 frames of
1920x1080 H.264 at 60 FPS, and writes the MP4 and its JSON manifest to
`agentdir/media/`. Each benchmark verifies the video and generator source hashes.

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

PrismMediaFrameHandler releases cached planes on the render thread when MediaPlayer is disposed. A single MediaView detaching leaves shared planes available. The churn fixture reuses a WritableImage destination and checks each decoded picture. [Historical verification](../agentdir/docs/media-godot.md).

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
.\scripts\test-media-audio.ps1 -Driver opengl
.\scripts\test-media-audio.ps1 -Runtime
.\scripts\test-media-audio.ps1 -Codec all
```

On Windows, macOS and Linux, the audio playback tests use `media-silence.wav`, `media-tone.mp3` or
`media-tone.aiff` from `agentdir/media/`. Audio-only churn uses
`media-churn-silence.wav` there. The tests reuse existing files. Linux can generate the WAV and MP3 fixtures. Provide `media-tone.aiff` before running the AIFF case on Linux, since the Unix fixture generator invokes the macOS `afconvert` tool for that format. Both WAVs contain two seconds of
mono 16-bit 44.1-kHz silence. On Windows, generating an MP3 or AIFF builds `tests/native/make_audio_fixture.cpp`
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
`agentdir/logs/media-audio-*.log`. This proves native playback operation; it does
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
.\scripts\test-media-planes.ps1 -Driver opengl
.\scripts\test-media-video.ps1
.\scripts\test-media-video.ps1 -Driver opengl
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
Logs: `agentdir/logs/media-frame-benchmark-{d3d,safe}.log`.

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

## Media process growth

The Windows churn test samples process memory and handles. With `-Providers` it also checks AAC decoder registration stability. The measured COM reference retention was fixed; longer memory trends and other codecs require separate verification. [Historical verification](../agentdir/docs/media-godot.md).

## macOS arm64 notes (2026-11-16)

The macOS port runs the same Godot-hosted probes through
`scripts/test-media-planes.sh`, `scripts/test-media-audio.sh`,
`scripts/test-media-video.sh` and `scripts/test-media-churn.sh`. Differences
from the Windows runners, all observable in the scripts:

- Audio fixtures: the WAV silence fixture keeps the Python generator. The MP3
  tone is encoded with ffmpeg/libmp3lame and the AIFF tone with `afconvert -f
  AIFF -d BEI16` (AIFF stores big-endian PCM), replacing the Media Foundation
  based `tests/native/make_audio_fixture.cpp`; both are verified with ffprobe
  (44100 Hz) when generated. Durations and tolerances are unchanged.
- The AVFoundation backend (OSXPlatform) handles MP3/AIFF/MP4 on macOS. Its
  `setCurrentTime:` used `CMTimeMakeWithSeconds(time, 1)`, quantizing seeks to
  whole seconds; the probe's 1200 ms +/-100 ms seek check failed. The timescale
  is now 600, the usual AVFoundation choice.
- The AVFoundation player passes zero tolerance on both sides of a JavaFX seek.
  A paused seek between keyframes otherwise can settle on the neighboring
  keyframe. The 1080p Lk sample previously stayed at 7.800 s for a request
  at 7.434 s on both Metal and OpenGL. After the fix, `test-media-video.sh
  --sample lk` passed with `--driver metal`, `--driver opengl` and the
  `--native` Mac Glass control, including seek, end-of-media, stop and
  replay. All three recorded maximum resize error 0 and blend error 1/255.
  Logs are in `agentdir/logs/media-video-{metal,opengl,native-mtl}-lk.log`.
- AVFoundation prefers planar YCbCr 4:2:0 and also accepts packed 4:2:2 and
  BGRA. The Godot renderer uploads a planar frame into three R8 textures and
  applies the YCbCr shader. Packed 4:2:2 still uses the BGRA conversion. Both
  YCbCr formats can supply BGRA when a software consumer requests it.
- The 1920×1080, 60 Hz fixture previously negotiated packed 4:2:2 and expanded
  to BGRA, splitting a video frame across two 4 MiB command batches. In the
  recorded Metal trial, 601 frames rendered in ten seconds and the queue
  rejected 1,132 submission attempts. With planar decoding the same video fits
  in one batch. Three consecutive ten-second trials on each driver measured
  60.056–60.146 rendered FPS with zero queue rejections or focus losses.
  Source format, plane count and counters are in
  `agentdir/logs/media-frame-{metal,opengl}-rate1-sample{9,10,11}-native60.log`.
  The native conversion probe checked 100 red/blue frames of each format,
  including row padding. Its log is
  `agentdir/logs/macos-planar-video/convert-formats.log`.
- `CurrentProcessMemory` (media churn process samples) cannot use FFM
  downcalls to `proc_pid_rusage`/`proc_pidinfo` on the pinned JDK: Temurin
  25.0.5+8 on aarch64 crashes with C2/metaspace corruption (`compiledIC
  "stub not found"`, `ChunkPool` SIGSEGV) shortly after such downcalls, also
  reproducible standalone outside Godot. The macOS branch therefore samples
  `ps` RSS (reported as both working set and private bytes) and counts
  `/dev/fd` entries for handles. Pass criteria are unchanged; the samples are
  trend-analysis data, not acceptance gates.
- Use `--runtime` for an isolated macOS Media project. For native Mac Glass and Prism Metal, run `./scripts/test-media-video.sh --native` or `./scripts/test-media-churn.sh --native` with the same sample and cycle settings as the Godot run. PSS/ETW and native D3D diagnostics require Windows. On macOS, `./scripts/make-media-fixture.py` encodes and verifies 960 H.264 frames with ffmpeg and ffprobe. `./scripts/benchmark-media-frames.py --driver metal --native60` checks the fixture hash, focused playback and host throughput. `--native` selects the native Mac Glass / Prism Metal comparison.

## Linux x64 media churn

On Linux the observer reads RSS and private memory from the media JVM's
`/proc/self/smaps_rollup`. Private bytes include private clean, dirty and
hugetlb pages. The JVM's Unix operating system bean supplies the open file
descriptor count in the `handles` field.

On WSL2 with the Arc B390, Vulkan Mobile and OpenGL Compatibility each passed
the default MP4 case, PCM audio-only case and isolated MP4 runtime case.
Each run recorded 24 JVM, process and Godot samples plus one idle process
sample. All six runs reported `GODOT_MEDIA_CHURN_PASS final_owned=0` at
teardown. The full logs are under
`agentdir/artifacts/linux-media-recheck-pIa1Wi3X/agentdir/logs/acceptance/`.
