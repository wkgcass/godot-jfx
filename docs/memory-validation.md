# Memory and resource validation

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Current commands are in [TESTS.md](../TESTS.md). Dated measurements are in the
> [memory validation archive](../agentdir/docs/memory-validation.md).


The objective requires no sustained growth in memory or GPU resources. A zero
tracked-resource count at shutdown only proves cleanup of the resources tracked
by the module. It does not measure driver allocations or all process memory.

The shared Viewport target cache has a 4096-entry/48 MiB input-payload budget. The `shared_target_meshes` count measures the shared cache once. The per-target counts can include the same mesh more than once.

## Real VFX workload

```powershell
.\scripts\test-vfx-soak.ps1 -Rounds 3 -HeapMiB 256
python .\scripts\analyze-vfx-soak.py artifacts/reference/vfx-soak-mobile-3-heap256.json
```

This uses the published engine and JavaFX JARs, and the original
VFX Intro classes. An observer reports page changes and JVM memory without changing
business code. Godot injects mouse input into the Demo's Next/Previous controls,
visits all pages in both directions each round, and waits two seconds after each
page acknowledgement. Fusion animations remain enabled. No forced GC is used.

The runner limits the JVM heap and records process private bytes, working set and
handle count every second. It samples the Java process that loaded the packaged engine. The report
records the sampled PID/executable; the analyzer excludes old reports without an
engine identity. Per-page samples record tracked resources, Godot texture
memory and Godot static memory after the transition. Java heap/GC samples occur
at page-change time, so they are not synchronized with the settled native samples.
The runner checks every expected page acknowledgement and final window/resource
cleanup. Its pass marker is navigation/cleanup acceptance, not a leak-free claim.

On Linux the Unix runner starts sampling after the launcher execs the selected
JDK's Java executable. It reads resident and private pages from
`/proc/<pid>/smaps_rollup` and counts open file descriptors in `/proc/<pid>/fd`.
The report uses the common `working_set`, `private_bytes` and `handles` fields
for RSS, private memory and descriptor count respectively.

The Linux `texture_bytes` sample comes from Godot's `RENDER_TEXTURE_MEM_USED` monitor. Vulkan sums texture allocation sizes reported to RenderingDevice by the Vulkan driver. The OpenGL compatibility renderer adds its own texture and renderbuffer byte counters, using sizes recorded by Godot at allocation and resize. Compare trends within each driver. These counters do not measure physical GPU residency and cannot be added to the Linux process-private total. [RenderingDevice accounting](../godot/servers/rendering/rendering_device.cpp) and [OpenGL accounting](../godot/drivers/gles3/storage/utilities.cpp).

The analyzer compares the same page and direction in the first and final rounds,
reports round endpoints and natural GC activity, and summarizes process memory
over the latter half of the run. Its regression slope is descriptive: startup,
JIT, shader caches, garbage collection and allocator retention can affect it.
Inspect per-page deltas and the full time series before attributing growth.
Repeating a bounded workload does not establish unlimited-duration stability.

Artifacts are `agentdir/logs/vfx-soak-*.log`, separate stderr logs, and
`artifacts/reference/vfx-soak-*.json` plus `.analysis.json`. An interrupted run is
not a pass. The runner terminates only its own test process on timeout/error and
restores all environment overrides.

## Existing isolated workloads

`test-stage-churn.ps1` checks native Stage creation/destruction, retained Java
objects under natural GC, window count, and warm tracked-resource/texture baselines.
`test-native-churn.ps1` separates Godot-only window/SubViewport churn from JVM work.
These tests previously exposed WinRT callback retention and Vulkan descriptor
retention. Their bounded results remain separate from real-Demo memory evidence.

On WSL2 with the B390, the OpenGL Stage churn test stopped at cycle 30 on release `ace7814e1e52…` / Toolkit `ab7b90061449…`. The live 640×360 root render target had eight cached canvas draw slots at that observation and seven at cycle 6. This accounted for the change from 34 to 35 tracked resources. Texture memory held at 19,315,459 bytes. The original 36-cycle fixture passed on a fresh private Weston desktop. A 180-cycle run with additional root-focus and slot logging on the original desktop held at 34 resources after warm-up and reached zero after shutdown. The draw that required the eighth slot in the initial run remains unidentified. Per-cycle logs and counts are under `wayland-toolkit-publication-QI3DyI7e/stage-slot-observation/` in the LCD publication archive.

Set `GODOT_JFX_SOAK_TARGETS=1` to include a `VFX_SOAK_TARGETS` record at startup and at each return to the home page. Each record contains the live render targets' generation-bearing handles, dimensions and material, shader and draw-slot counts. Matching handles between two returns distinguishes cache growth on surviving targets from allocation and disposal of entire targets. Counts describe Godot objects rather than their CPU or GPU allocation sizes.

## Recorded results

The six-round follow-up released all tracked resources at shutdown and showed smaller late-round increases. Longer process and GPU memory trends still require measurement. [Historical verification](../agentdir/docs/memory-validation.md).

On 2026-11-22 the M1 ran `./scripts/test-vfx-soak.sh --driver metal` and
`--driver opengl` on the rebuilt local Maven publication. Each run visited
35 pages forward and back over three rounds with a 256 MiB heap. Both
recorded 205 Java and 205 native samples and released all tracked resources
at shutdown. At page zero, the host-owned count started at 369 on both drivers. After the three rounds, the counts were 7,676, 8,580
and 9,003 on Metal, and 8,043, 10,003 and 10,812 on OpenGL.
Long-run growth remains open. The reports for the final publication are in
`agentdir/logs/macos-planar-final/soak-analysis-{metal,opengl}.log`.

On 2026-11-23 the WSL2/B390 Linux publication completed the same three-round
workload on Vulkan/dzn and OpenGL/D3D12. Each backend reported 205 matching
Java and native samples and zero host-owned resources after shutdown.

| Driver | Initial and end-of-round owned counts at page 0 | JVM process samples | Natural collections | Latter-half private memory slope |
| --- | --- | ---: | ---: | ---: |
| Vulkan | 305 → 3618 → 4293 → 4684 | 507 | 23 | +21.7 MiB/min |
| OpenGL | 305 → 3518 → 4337 → 4901 | 513 | 20 | +62.5 MiB/min |

On matched pages, the median increase in owned resources from round two
to round three was 495 for Vulkan and 562.5 for OpenGL. Sustained memory
stability remains open. Raw logs, reports and analyses for both drivers
are in `agentdir/artifacts/linux-vfx-acceptance/soak/`.

On 2026-11-24 the native Wayland VFX run on the Intel Arc B390 visited the
same 35 pages forward and back six times per driver, with a 256 MiB heap and
normal garbage collection. Each run recorded 409 Java and 409 host samples,
completed navigation, and reported zero host-owned resources after shutdown.
The following values compare the same home page at the end of each round.
Process memory is the nearest sampled value, within 0.47 seconds.

| Driver | Private memory by round (MiB) | Render targets by round | Target materials by round | Private memory slope over second half |
| --- | --- | --- | --- | ---: |
| Vulkan/dzn | 1713, 1844, 1998, 2086, 2161, 2206 | 184, 203, 218, 228, 236, 236 | 1566, 1940, 2274, 2570, 2773, 2918 | +26.2 MiB/min |
| OpenGL/D3D12 | 2547, 2921, 3123, 3206, 3272, 3359 | 164, 196, 209, 211, 212, 217 | 1468, 2008, 2294, 2478, 2655, 2831 | +28.0 MiB/min |

Both target material counts and both process memory measurements were still
rising on the sixth return. Long-run memory stability remains open. The raw
reports, shutdown markers, process samples and extraction script are under
`agentdir/artifacts/wayland-vfx-six-rounds-kJDJ7U5C/`.

### Eight Vulkan rounds on native Wayland

On 24 November the B390 repeated the 35-page workload eight times on Vulkan/dzn with a 256 MiB heap, normal GC and target snapshots enabled. The archive contains 545 Java samples, 545 host samples and nine home-page snapshots. The host released all owned resources on exit.

| End of round | Live targets | Cached materials | Godot texture memory (MiB) | Private process memory (MiB) |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 180 | 1623 | 759.5 | 1714.0 |
| 4 | 225 | 2784 | 825.8 | 2103.9 |
| 7 | 231 | 3351 | 855.6 | 2247.1 |
| 8 | 232 | 3481 | 855.7 | 2280.7 |

Between rounds seven and eight, the 231 surviving targets gained 129 net materials and one new target held one material. All 180 targets from the first return were present at the final return with 1498 additional materials between them. The second-half private-memory slope was +14.1 MiB/min. Independent Linux smaps snapshots at the first and last returns showed a 566.4 MiB rise in unnamed private mappings. These measurements identify the objects accumulating materials and the mappings in which private memory grew. The bytes attributable to the material cache remain undetermined.

The raw reports, endpoint table and mapping samples are in `agentdir/artifacts/wayland-cross-stage-tn1HHwAW/soak/`.

### Sampler material cache comparison

A second B390 Vulkan run used the same engine (`78d43359aab3…`), isolated Weston display, 256 MiB heap and navigation workload. Only this diagnostic JVM used `GODOT_JFX_RID_MATERIAL_CACHE=0`. The switch makes materials with sampler RID parameters pass-owned. Other cacheable materials still use the cache. The run completed four round trips, with 273 Java and 273 host samples and zero host-owned resources at shutdown.

| Fourth return to the home page | Regular release | Diagnostic |
| --- | ---: | ---: |
| Cached materials | 2784 | 563 |
| Live render targets | 225 | 218 |
| Cached shader references | 1149 | 1117 |
| Private process memory (MiB) | 2103.9 | 2054.3 |
| Godot texture monitor (MiB) | 825.8 | 844.4 |

Between returns one and four, private memory grew by 389.9 MiB in the regular release and by 325.2 MiB in the diagnostic. The cache switch removed about 80% of fourth-return material entries while substantial process growth persisted. The comparison comprises one run per condition and cannot assign a byte cost to individual entries. JVM heap capacity was 110 MiB committed at the four diagnostic observations. The glibc arena snapshots and per-round data are in `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/`. Production caching remains enabled.

### Three rounds on the B390 MSAA release

The full Wayland regression on release `64f8f54d265b…` ran three round trips through all 35 pages on each driver with a 256 MiB JVM heap and normal GC. Each run produced 205 paired Java and host observations and released all host-owned resources at shutdown. At each return to the home page, the nearest process sample was within 0.49 seconds.

| Driver | Private process memory at returns 1, 2, 3 (MiB) | Live render targets | Cached target materials |
| --- | --- | --- | --- |
| Vulkan/dzn | 1812.2, 2009.5, 2095.2 | 191, 216, 228 | 1583, 2141, 2402 |
| OpenGL/D3D12 | 2640.9, 3012.9, 3198.2 | 169, 190, 209 | 1585, 2068, 2343 |

Private memory continued rising on both drivers. The raw PID-matched reports, page samples and endpoint table are in `agentdir/artifacts/wayland-material-comparison-8Qv64YvC/soak-current/`. Cases 280 and 281 in `nonrobot-full/` contain the runtime logs.

### Native allocation stacks during Vulkan navigation

A separate JVM on the same release repeated the Vulkan navigation four times with jemalloc sampling one allocation per 256 KiB on average. The diagnostic recorded live allocation stacks at each return to the same home page. It completed all 273 Java and 273 host observations and released all host-owned resources at shutdown. The normal-allocator process observations above provide a separate reference.

| Endpoint difference | Estimated live native heap growth | Of which stacks contain Godot shader variant loading and shader creation from bytecode |
| --- | ---: | ---: |
| Return 1 to return 4 | 354.9 MiB | 262.5 MiB |
| Return 3 to return 4 | 75.9 MiB | 52.3 MiB |

The matching stacks include both `ShaderRD::_load_variant_from_cache` and `RenderingDevice::shader_create_from_bytecode_with_samplers`. Grouping by the mapped library of the first frame outside jemalloc attributes +239.1 MiB to the Godot library and +85.7 MiB to Mesa dzn between returns one and four. This breakdown and the stack totals describe overlapping allocations. Process private memory rose from 1864.9 to 2238.9 MiB during that interval. Sampling estimates omit allocations outside jemalloc. These observations identify the allocation path measured in the comparison below.

The five heap profiles, jeprof differences, module aggregation and process samples are in `agentdir/artifacts/wayland-niri-WMYYUVqs/vfx-prof/`. The aggregate calculation applies the heap_v2 sampling adjustment and compares its totals to jeprof.

### Sharing identical target shader programs in a diagnostic build

A source-built diagnostic engine (`836edd65c451…`) interned identical immutable shader source across the bounded caches of live offscreen targets. The last target using a shared shader freed its RID. Target-specific materials, sampler references, draw slots and the existing overflow policy remained in use. The release and diagnostic each ran four Vulkan rounds with the same jemalloc sampling and page-zero synchronization. Each run produced 273 paired observations. Per-target counters count cached references in the diagnostic.

| Vulkan measurement | Release | Diagnostic |
| --- | ---: | ---: |
| Private process memory at return 1 | 1864.9 MiB | 1031.6 MiB |
| Private process memory at return 4 | 2238.9 MiB | 1056.5 MiB |
| Estimated live native heap growth, returns 1 to 4 | 354.9 MiB | 50.5 MiB |
| Growth on shader variant loading stacks in that interval | 262.5 MiB | 17.7 MiB |
| Estimated live native heap growth, returns 3 to 4 | 75.9 MiB | 15.0 MiB |

On its fourth return the diagnostic had 1,019 target shader references backed by 13 distinct pooled programs. It released all 13 on shutdown. Ten targeted Vulkan/OpenGL runs passed, covering queued texture revisions, viewport and batch boundaries, target rendering and shader-cache pressure. The result identifies duplicated shader programs as a substantial contributor on this workload. The fourth-return live heap still increased, and this comparison contains one profiled run per condition. The profiled builds were compared separately from the full regression on `64f8f54d265b…`.

The isolated source, classifier, raw checks, five heap snapshots, comparison and shutdown counts are under `agentdir/artifacts/wayland-niri-WMYYUVqs/shader-sharing-8N7V2U87/`.

The same diagnostic then ran six round trips on each driver using the normal allocator, a 256 MiB JVM heap and normal GC. Each driver completed all 409 Java and 409 host samples and reached zero host-owned resources and zero shared shader programs at shutdown. Private memory on returning to the same home page was:

| Driver | Returns 1 through 6 (MiB) | Second-half private-memory slope |
| --- | --- | ---: |
| Vulkan/dzn | 960.1, 984.1, 998.0, 1010.8, 1040.8, 1039.6 | +5.9 MiB/min |
| OpenGL/D3D12 | 721.9, 737.9, 736.2, 787.3, 788.3, 791.0 | +5.5 MiB/min |

Both runs used substantially less private memory at return three than the regular release measured above. The live target and material counts continued to rise. The measurements support the effect of shader sharing over six rounds, while long-run stability remains open. The per-page data, process samples, engine hash verification and endpoint table are in the diagnostic archive's `regular/` directory.

### Shared target shader lifetime in the Linux release

The B390 release `a312dd9c27c1…` includes the shader-sharing change measured above. The soak records the number of distinct shared programs as `resources.shared_target_shaders` and the sum of live targets' cached references as `resources.target_shaders`. A single program can have several references. The Linux process sampler and the Godot page sample each record an epoch timestamp in milliseconds so the nearest process reading can be located even when JVM and engine startup times differ. The shutdown check requires zero host-owned resources and zero remaining shared target programs. Independent Vulkan and OpenGL pixel tests verified that removing one owner preserves the other owner's drawing and that removing the last owner returns the pool to its initial size. Results are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/focused/`.

Both drivers completed one full 35-page round trip on the published library with a 256 MiB JVM heap, normal GC and the default native allocator. Each recorded 69 Java and 69 Godot observations. At the return to the home page, Vulkan/dzn reported 811 cached shader references backed by 13 distinct programs, with 1004.1 MiB of private process memory. OpenGL/D3D12 reported 847 references backed by 13 programs, with 769.0 MiB private. The selected process samples were 305 ms before and 127 ms after the corresponding Godot observations. Both fixtures exited successfully with zero host-owned resources and zero shared target shaders. A single round measures a return baseline. Logs and process samples are in the release archive under `one-round-b390-vulkan-final/` and `one-round-b390-opengl/`, with the verified library hash and counts checked by `audit-preflight.py`.

The standard three-round NonRobot fixtures on this same release completed 205 paired Java and host samples per driver. All six returns had 13 shared programs and both shutdown checks reached zero.

| Driver | Private memory at returns 1, 2, 3 (MiB) | Live render targets | Second-half private-memory slope |
| --- | --- | --- | ---: |
| Vulkan/dzn | 1044.8, 1062.0, 1075.9 | 180, 206, 210 | +2.9 MiB/min |
| OpenGL/D3D12 | 780.0, 781.4, 785.4 | 188, 212, 220 | +0.1 MiB/min |

These measurements used the published 512 MiB reclamation target. Process private memory rose by 31.1 MiB on Vulkan and 5.4 MiB on OpenGL from return one to return three. Cases 280 and 281 under `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/nonrobot-full/` contain the raw data. The PID- and library-verified home observations and trends are in `soak-regular/` in the same archive.

### VFX effect-image pool on the B390

Two Vulkan diagnostics matched individual JavaFX texture handles to the offscreen targets reported by Godot on return to the home page. Both used the published `a312dd9c27c1…` engine, the 35-page navigation, the normal allocator and a 256 MiB Java heap.

In the first run a temporary copy of `GodotTexturePool` recorded the Java allocation stack for each new render target. The numbers of targets created through JavaFX's `ImagePool.checkOut` were 179, 191 and 199 at returns one, two and three. The remaining target at each return was the window back buffer. The effect-pool targets retained 1,553, 1,990 and 2,304 target-specific materials. All 205 page observations matched, and host-owned resources and shared target shaders reached zero at shutdown.

In the second run the Java observer took a read-only snapshot of the effects renderer's image pool on the Prism thread at each home-page return. Godot waited for that snapshot before recording the native handles. This run used the published JavaFX classes. Every handle found in the pool matched a live Godot target. The figures below describe a pool entry's state at the observation and its nominal RGBA8 image size. Each return also had one target outside the observed pools.

| Return | Unlocked pool images | Locked pool images | Nominal RGBA8 storage of unlocked images | Materials on unlocked targets |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 167 | 0 | 289.5 MiB | 1,361 |
| 2 | 195 | 0 | 308.2 MiB | 1,819 |

The unlocked images are available for a later effect draw. Both runs closed with zero tracked host resources. Source overlays, stack traces, pool membership and handle-by-handle reconciliation are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/{target-allocations-2nbMSqn5,pool-ownership-E79Cr2V3}/`.

### Effect-pool budget comparison

A third isolated Vulkan run changed the initial Prism texture-pool reclamation target from 512 MiB to 256 MiB in a temporary copy of `GodotTexturePool`. Both conditions kept the 1 GiB hard limit, default native allocator and 256 MiB JVM heap. The diagnostic used the same synchronized pool observation and added a reading of the effective budget. The published JavaFX modules still use 512 MiB.

| Second home-page return | Published setting, 512 MiB | Diagnostic setting, 256 MiB |
| --- | ---: | ---: |
| Unlocked effect-pool targets | 195 | 42 |
| Materials cached on those targets | 1,819 | 202 |
| Nominal RGBA8 storage of those targets | 308.2 MiB | 155.1 MiB |
| Godot texture-memory monitor | 759.8 MiB | 351.9 MiB |
| Process private memory | 1,026.3 MiB | 1,008.2 MiB |

Both runs completed two 35-page round trips and closed with zero shared target programs and zero tracked host resources. The respective process samples were 294 ms after and 76 ms before the second return. Private process memory increased 6.3 and 5.1 MiB from the first to the second return. The monitor and the size estimate measure different resources from process private memory. Earlier reclamation substantially reduced retained render targets and the Godot monitor reading in this comparison. Two rounds and one run per setting leave the long-run process trend and frame-pacing cost unresolved. The private class overlay, effective pool accounting, raw observations and comparison are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/pool-budget-tP4zjwYV/`.

### Vulkan home-page observations before an interrupted 12-round run

On the published B390 library `a312dd9c27c1…`, six consecutive Vulkan/dzn round trips completed before the run stopped during round seven. On the six returns to the same home page, private process memory measured 1032.1, 1067.2, 1087.7, 1109.1, 1124.2 and 1130.6 MiB. The process readings were within 0.51 seconds of the native page samples. Independent Linux memory-map readings placed 90.6 MiB of the 98.5 MiB increase in anonymous private mappings. These mappings include native and JVM allocations.

Godot reported 13 shared shader programs throughout. Between returns five and six the texture monitor rose from 826.5 to 826.8 MiB. All 233 previous render targets survived and gained 98 net cached materials. The one additional target held two materials. This identifies where the material count increased. The process data do not assign an allocation size to those materials.

Pairing all 68 page-and-direction observations from round five with round six showed higher private memory on every matched page (median +20.8 MiB). The median material count increased by 133 and the median file descriptor count stayed unchanged. The largest offset between a native sample and its process reading in this comparison was 507 ms. The same-page comparison supports the growth seen on return to the home page.

The run supplied no shutdown measurement or OpenGL result. The six matched samples are retained separately from complete soak results in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/extended-interrupted-wSACkrea/{home.csv,completed-home-targets.csv,paired-process.csv,run/}`.

### Twelve Vulkan rounds on the published shared-shader engine

The B390 Vulkan/dzn application on isolated Weston completed twelve consecutive round trips through all 35 pages with the normal allocator and a 256 MiB Java heap. All 817 page observations matched in Java and Godot. The application exited successfully with zero host-owned resources and zero shared target shaders. The outer shell returned 2 after the report had been written. A comment in the shell script had been edited in place while it was running. The raw shell status is preserved in `extended/results.txt`.

| Vulkan home-page return | Process private (MiB) | JVM heap capacity (MiB) | JVM heap used (MiB) | Texture monitor (MiB) | Live targets | Cached materials |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 1128.8 | 117 | 84.1 | 798.1 | 219 | 2684 |
| 8 | 1185.3 | 117 | 49.5 | 805.2 | 227 | 3244 |
| 12 | 1253.1 | 117 | 81.4 | 832.1 | 232 | 3577 |

The HotSpot counters came from copies of the running JVM's performance-data file taken after each home-page observation from round four onwards. Reported heap capacity stayed at 117 MiB. Process private memory rose by 124.3 MiB between returns four and twelve. Shared shader programs stayed at 13. Between the last two returns, 228 surviving targets gained 84 materials and four additional targets held 31 materials. The latter-half process slope was +4.9 MiB/min. Memory and GPU resource stability remain open for Vulkan. Measurements and their timestamps are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/extended/{jvm-process-home.csv,vulkan-complete-targets.csv,vulkan-complete-pairs.csv,vulkan-analysis.log}`.

To locate the growth during navigation, adjacent native page samples were subtracted and the forward and reverse changes across each page boundary were added for each round. Adding both directions cancels a fixed difference in material count between neighboring pages. The sum across all boundaries reproduces the home-to-home change. In Vulkan rounds 7–12, the largest net increases were pages 30↔31 (Components intro/demo, +169 materials), 23↔24 (Animation System demo/description, +155), and 18↔19 (the two table demos, +134). All three boundary pairs gained materials in each of the six rounds. Other boundaries also released materials. These measurements locate growth during navigation and do not identify a control that owns a material. Per-round changes are in `extended/vulkan-transition-growth-edges.csv` in the release archive.

An independent four-round run with sampled native allocations on the earlier shared-shader diagnostic build helps interpret the material counts. From return three to four, stacks passing through mesh construction accounted for an estimated +7.78 MiB, shader variant loading +2.27 MiB, and material acquisition +0.75 MiB. Across returns one to four the corresponding estimates were +2.49, +17.75 and +1.25 MiB. These figures sum signed changes in live sampled allocations, including frees. Indirect or deferred driver allocations can appear on other stacks. The classifications for this diagnostic are in `extended/profiled-call-paths.csv`; the normal-allocator twelve-round run has no allocation stacks.

A fresh Vulkan run on the same published library used a read-only copy of the launcher. The test script exited with code zero. All 817 expected Java and Godot page observations matched, and both tracked resource counts returned to zero. Private process memory was 1048.2, 1089.1, 1136.9 and 1152.6 MiB at home returns 1, 4, 8 and 12. Cached materials rose from 1420 to 2897 over those returns. The latter-half private-memory slope was +3.01 MiB/min. Both runs showed growth, with different magnitudes. The launcher hash, exit status, paired measurements, and comparison are recorded in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/vulkan-12-wrapper-repeat-rut3KNOS/`.

### Twelve OpenGL rounds on the published shared-shader engine

The same B390 release completed the isolated native Wayland workload using OpenGL Compatibility through Mesa D3D12. The application and outer test script exited with code zero. All 817 Java and 817 Godot observations matched the expected navigation sequence. There were 2,029 process samples. The host released all tracked resources and shared shader programs at shutdown.

| OpenGL home-page return | Process private (MiB) | JVM heap capacity (MiB) | Texture monitor (MiB) | Live targets | Cached materials |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 790.1 | 110 | 999.1 | 164 | 1495 |
| 4 | 784.9 | 110 | 1086.5 | 208 | 2352 |
| 8 | 793.4 | 110 | 1145.3 | 235 | 3029 |
| 12 | 794.9 | 110 | 1145.8 | 235 | 3416 |

At returns eight through twelve the same 235 render targets accounted for 95.4 million pixels. Their combined material count rose by 387, including 65 between the last two returns. Shared shader programs stayed at 13. On the last round, the median change in private process memory across the 68 matched pages was +0.1 MiB. The latter-half slope over all process samples was +0.17 MiB/min, compared with +4.86 MiB/min for Vulkan. OpenGL process memory changed little late in this run, while the continued material growth leaves the GPU resource stability requirement open.

Matching target handles from return six to return twelve gives a further breakdown. On Vulkan, targets already present at the first return gained 445 of the 589 net additional materials. On OpenGL, the corresponding targets gained 458 of 626. Targets first observed after return six accounted for 97 and 72 materials respectively. The `extended/material-cohorts.csv` and `extended/material-cohort-targets.csv` files give the totals and individual target handles. Each target enters its cohort at the first home-page observation where its handle appears.

The `extended/` directory in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/` contains both drivers’ original logs, renderer and library identities, return-to-home counters, per-target comparisons and per-page memory differences. `summary.json` preserves the outer shell exit codes separately from the application navigation and cleanup results.

### Texture-pool budget and render timing on B390 Vulkan

Two isolated three-round Vulkan runs used the same engine, JVM, 35-page workload and frame observer. A diagnostic Java class changed the initial texture-pool reclamation target to 256 MiB. Its hard limit stayed at 1 GiB. Both runs confirmed the loaded class origin, completed 205 paired navigation observations, sampled all 204 transition intervals and released all tracked resources. The render thread read each pool's effective target on arrival at the home page. It remained at the respective 512 or 256 MiB setting at all four observations.

| Third round | Published 512 MiB | Diagnostic 256 MiB |
| --- | ---: | ---: |
| Process private memory on return | 1083.3 MiB | 1008.9 MiB |
| Godot texture monitor on return | 754.3 MiB | 463.6 MiB |
| Godot buffer monitor on return | 39.3 MiB | 39.2 MiB |
| Cached target materials on return | 2053 | 460 |
| 95th percentile of post-draw callback intervals | 33.02 ms | 33.04 ms |
| 99th percentile of post-draw callback intervals | 40.71 ms | 41.25 ms |

All three rounds showed a lower home-page texture reading with the smaller pool. The third-round median difference between the 68 matched page-level 95th percentiles was −0.257 ms. First-draw latency is measured from input injection to the next post-draw callback. These timings describe engine callbacks, with one run per setting. Physical presentation timing is outside this measurement. The comparison, per-page intervals and JVM class origins are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/wayland-pool-pacing-SqjQY7q9/`. The reference publication measured here used a 512 MiB pool target.

### Twelve-round Vulkan check of the 256 MiB reclamation target

The diagnostic class completed 12 Vulkan rounds on B390 under native Wayland. The script exited successfully, all 817 Java and native observations matched and the host released its tracked resources and shared shaders on exit. The comparison used the successful 12-round published run with the read-only launcher. Both used the same native library, allocator, 256 MiB JVM heap and normal garbage collection.

| Vulkan measure | Published 512 MiB | Diagnostic 256 MiB |
| --- | ---: | ---: |
| Final home-page private memory | 1152.55 MiB | 1121.95 MiB |
| Final home-page texture monitor | 825.31 MiB | 581.31 MiB |
| Final home-page live targets | 223 | 111 |
| Final home-page cached materials | 2897 | 953 |
| Latter-half private-memory slope | +3.01 MiB/min | +3.19 MiB/min |

Across all 408 matched page and direction observations in rounds seven through twelve, the diagnostic had fewer targets and materials and lower texture and process-private readings on every observation. Median differences were −133 targets, −1958 materials, −292.0 MiB of texture memory and −52.35 MiB of process private memory. On the last home return 79 targets from the prior return had disappeared and 77 additional targets were present. Both budgets still showed rising process private memory through the latter half. The comparison establishes a smaller working set on this workload and leaves the sustained process growth unresolved. Reports and per-page comparisons are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/wayland-pool-pacing-SqjQY7q9/long-256/`.

### Twelve-round OpenGL check of the 256 MiB reclamation target

The diagnostic OpenGL run also exited with code zero after 817 paired Java and native observations and zero tracked resources at shutdown. The last home return had 56 targets and 515 cached materials, with 643.35 MiB on Godot's texture monitor and 777.14 MiB of process-private memory. The published reference had 235 targets, 3416 materials, 1145.81 MiB on the texture monitor and 794.88 MiB of process-private memory.

All 408 matched observations in rounds 7–12 had lower texture readings, target counts and material counts with the smaller pool. Median reductions were 454.78 MiB, 146 targets and 2286 materials. Process-private memory was lower in 406 observations, with a median reduction of 13.34 MiB. The latter-half process slopes were +0.36 MiB/min with the diagnostic class and +0.17 MiB/min with the published class. Both drivers benefit in texture working set; the Vulkan private-memory rise remains under investigation.

A separate JVM-side pressure probe checked both pool settings. Sixteen locked 4096×4096 RGBA texture handles took the pool's accounting to its 1 GiB limit. Both configurations retained the locked handles, refused the next allocation, reused a released slot with a new generation and returned to zero used bytes on disposal. Both passed the repository's texture cancellation probe. This exercise checked encoded allocations and Java resource accounting without submitting a GPU frame. Reports are in `long-256/opengl-summary.json` and `locked-textures-2QEFbiQ3/` under the pacing experiment archive.

### Native allocator observations during Vulkan navigation

An eight-round repeat on B390 used the 256 MiB diagnostic class, the published Godot library and the default glibc allocator. At each settled return to the home page the observer recorded the process's private memory, JVM heap and non-heap usage, and glibc's allocator report. All 545 paired navigation observations completed. The application released its tracked resources and shared target shaders at shutdown.

| Home-page reading (MiB) | Round 1 | Round 4 | Round 8 |
| --- | ---: | ---: | ---: |
| Process private memory | 1006.95 | 1038.71 | 1070.13 |
| Memory obtained by glibc arenas | 541.23 | 587.30 | 617.86 |
| Free blocks reported by the arenas | 80.11 | 116.59 | 87.27 |
| Direct mmap allocations reported by glibc | 140.16 | 137.92 | 137.92 |
| Java heap committed / used | 94.00 / 49.24 | 94.00 / 46.45 | 94.00 / 84.33 |

Between returns four and eight, process private memory grew by 31.42 MiB and glibc's 16 arenas obtained another 30.56 MiB. Direct mmap allocations and Java heap capacity were stable at those checkpoints. Arena sizes describe allocations of address space, while the process reading counts resident private pages. Free space fluctuated between returns. The observations locate growth in the native allocator and leave the allocating component and lifetime of its allocations unresolved. The nine snapshots, time-aligned measurements and navigation report are in `native-heap-probe-TGnhJGma/` under the pacing experiment archive.


The rebuilt Linux package (`GodotTexturePool.class` prefix `b0774c465b25`) completed the ordinary three-round regression on both drivers. Each run produced 205 matching Java and host navigation observations and passed cleanup with normal GC. On the three settled home returns, sampled process private memory was 1043.7, 1070.5 and 1088.2 MiB on Vulkan and 775.2, 769.5 and 764.6 MiB on OpenGL. Reports and sample times are in `agentdir/artifacts/wayland-linux-pool-release-j87Wdjek/soak-regular/`.

### Three-round check of the B390 Wayland release

The Linux release with engine SHA-256 prefix `20e839a2fcf2` completed three round trips through all 35 pages on each renderer with a 256 MiB Java heap and normal GC. All 205 Java page observations and all 205 native page, round and direction observations matched the expected sequence on each run. Both processes exited with zero host-owned resources and zero shared target shaders.

| Renderer | Process-private MiB after rounds 1 / 2 / 3 | Texture MiB after rounds 1 / 2 / 3 | Live targets after rounds 1 / 2 / 3 |
| --- | --- | --- | --- |
| Vulkan Mobile | 1070.4 / 1086.6 / 1095.7 | 499.7 / 490.6 / 449.8 | 63 / 73 / 56 |
| OpenGL Compatibility | 750.4 / 762.2 / 766.3 | 713.5 / 711.2 / 796.0 | 67 / 61 / 116 |

Process-private samples were taken within 355 ms of the settled home-page observations. The three rounds verify navigation and shutdown. Long-run memory stability remains open. Source reports and both timestamp-aligned summaries are in `agentdir/artifacts/wayland-interaction-hQ6x4vwN/verified-release-lZUp7QMq/restart-suite-n8jhXQQK/` under `nonrobot-full/{280,281}-test-vfx-soak/` and `soak-{vulkan,opengl}-check.json`.

### Three-round check after the mesh upload change

Engine `da0a4ee0ac9a` completed three more return trips through the same 35 pages on each B390 driver. Each run matched all 205 Java and native navigation samples and exited with zero host-owned resources and zero shared target shaders.

| Driver | Private memory on home returns 1 / 2 / 3 (MiB) | Texture memory on the same returns (MiB) |
| --- | --- | --- |
| vulkan | 1122.2 / 1147.0 / 1153.8 | 547.3 / 457.2 / 558.3 |
| opengl | 630.1 / 640.6 / 644.1 | 644.7 / 712.7 / 750.6 |

The nearest private-memory sample for the third OpenGL return preceded the native observation by 1.03 s. Texture memory was measured by the host at the observation itself. The per-return timestamps, process samples and shutdown markers are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-mesh-publication-smkUz5fY/` in `soak-{vulkan,opengl}-check.json` and `nonrobot-full/{280,281}-test-vfx-soak/`.

The release with engine `ace7814e1e52…` and Toolkit `ab7b90061449…` completed three round trips through all 35 VFX pages on each driver with a 256 MiB Java heap. Each run paired all 205 Java and host navigation samples and ended with zero host-owned resources and zero shared target shaders. The values below were sampled on returning to the home page.

| Driver | Process-private MiB after rounds 1 / 2 / 3 | Texture MiB after rounds 1 / 2 / 3 |
| --- | --- | --- |
| Vulkan/mobile | 1240.0 / 1234.3 / 1256.3 | 543.4 / 477.1 / 459.4 |
| OpenGL/gl_compatibility | 652.6 / 663.6 / 646.3 | 669.3 / 689.4 / 710.5 |

The OpenGL texture monitor rose 41.2 MiB between the first and third returns. Longer workloads are needed to establish the steady-state texture footprint. Timestamp-aligned readings are archived in `wayland-toolkit-publication-QI3DyI7e/soak-{vulkan,opengl}-check.json`.
