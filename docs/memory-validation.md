# Memory and resource validation

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


The objective requires no sustained growth in memory or GPU resources. A zero
tracked-resource count at shutdown only proves cleanup of the resources tracked
by the module. It does not measure driver allocations or all process memory.

## Latest review run (2026-11-11)

The latest three-round run passes navigation and final cleanup but shows homepage
owned resources 4869/6166/6840 and static memory 423751910/606438661/702758968 bytes.
There were 22 natural GCs; process tail-half private-memory slope is about
160 MiB/minute. This supersedes the old stable-count result as current evidence.
The growth is under investigation; final zero does not settle its cause.
Preserved evidence: `artifacts/reference/review-final-soak-growth.json`, its
`.analysis.json`, and `artifacts/logs/review-final-soak-growth.log`.

The follow-up diagnostic adds `resources` to each native sample: live textures,
active/retired targets, RD target count, target-owned count, target mesh/shader/
material caches and draw slots, plus surface mesh cache and retired textures.
These are per-owner counts (shared resources may be counted more than once), not
GPU bytes. The existing on-demand `get_texture_resource_stats` interface gathers
them on the main thread; it does not add per-frame collection. Rebuild and publish the engine library
before using the updated soak fixture. This diagnostic is not a performance run.

The implemented follow-up shares the target geometry cache across main-thread
Viewport targets: one 4096-entry/48 MiB input-payload budget, rather than one per
target. Draw slots retain their own mesh references. A weak registry owns no GPU
resources; the final target releases the cache. Surface-local caches are unchanged.
`shared_target_meshes` reports the shared target cache size once; `target_meshes`
remains a sum of per-target observations and must not be interpreted as unique
meshes after this change. The unchanged-binary diagnostic completed with 57435 cached target meshes.
Cross-target pressure/pixel regression passed; full-soak comparison
and performance revalidation remain pending.

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

The analyzer compares the same page and direction in the first and final rounds,
reports round endpoints and natural GC activity, and summarizes process memory
over the latter half of the run. Its regression slope is descriptive: startup,
JIT, shader caches, garbage collection and allocator retention can affect it.
Inspect per-page deltas and the full time series before attributing growth.
Repeating a bounded workload does not establish unlimited-duration stability.

Artifacts are `artifacts/logs/vfx-soak-*.log`, separate stderr logs, and
`artifacts/reference/vfx-soak-*.json` plus `.analysis.json`. An interrupted run is
not a pass. The runner terminates only its own test process on timeout/error and
restores all environment overrides.

## Existing isolated workloads

`test-stage-churn.ps1` checks native Stage creation/destruction, retained Java
objects under natural GC, window count, and warm tracked-resource/texture baselines.
`test-native-churn.ps1` separates Godot-only window/SubViewport churn from JVM work.
These tests previously exposed WinRT callback retention and Vulkan descriptor
retention. Their bounded results remain separate from real-Demo memory evidence.

## Completed Vulkan/safe run (2026-11-03)

The corrected engine-process run completes three full 35-page round trips in
approximately 537 seconds, with 205 Java/native observations and 517 process
samples. Navigation and final cleanup pass; tracked resources are zero after host
removal. Java heap is capped at 256 MiB, with 656 natural collections and sampled
heap usage between 28.5 and 84.3 MB (decimal units); no forced GC or OOM occurs.

| Return to homepage | Owned resources | Texture bytes | Godot static bytes |
| --- | ---: | ---: | ---: |
| Round 1 | 99 | 135692288 | 80583048 |
| Round 2 | 99 | 135692288 | 80586000 |
| Round 3 | 99 | 135692288 | 80585976 |

The actual engine's latter-half private memory spans 1.90–2.61 GB, median 2.29 GB;
working set median is 2.25 GB. Handles range from 808 to 821. The fitted private
memory slope is +113542 bytes/minute, much smaller than page/allocator variation.
Round-2/3 private-memory maxima are approximately 2484/2487 MiB; their medians
differ (approximately 2155/2193 MiB), so this is not an exact flat-line assertion.
Same-page native resource/texture delta medians are zero between adjacent rounds,
with positive and negative transient differences under natural GC.

The observations are consistent with a bounded warmed workload and do not show
clear sustained accumulation at this duration. They do not rule out small leaks,
unmeasured driver allocations, or other workloads/longer sessions. The first run's
console-launcher process metrics are invalid and retained separately as
`vfx-soak-mobile-3-heap256-launcher-invalid.json`. The dated numbers above are historical; the reusable
`vfx-soak-mobile-3-heap256.json` filenames are overwritten by later runs. Use the
preserved `review-final-soak-growth` files for the 2026-11-11 run.

## Shared-cache follow-up results (2026-11-11)

GL and Vulkan pressure fixtures verify a shared
4096-entry budget, peer destruction preserving other users, final-user release
starting a fresh cache, and queued-draw pixels. The old binary fails the new shared
budget assertion. Three-round navigation/cleanup passes with 205 samples and final
zero; no forced GC. Homepage static MiB is 211/226/234 versus 401/566/650 before.
Process private peak drops from about 5.19 to 3.70 GiB; tail-half slope drops from
about 116 to 38 MiB/minute. These are bounded observations, not zero-growth proof.
Targets still grow 196/219/231 and materials 1957/2555/2836; texture memory grows
775/817/836 MiB. Remaining retention needs explanation before memory closeout.
Evidence: review-shared-mesh-after.json and .analysis.json in artifacts/reference.

Current mobile/safe 68-transition rates are Viewport 58.604 pulse / 55.741 host
composition FPS and RD 59.662 / 56.786, both unfocused=0 and cleanup PASS.
The independent rate calculation and current binary hashes are recorded in
artifacts/review-shared-mesh-performance.json. Occasional long frames remain
explicitly deferred. These counters do not measure physical scanout.

### Residual pool growth investigation

Normal BaseResourcePool frame maintenance ages resources and handles disposal;
it does not evict every idle resource on each page change. Allocation pressure
triggers staged pruning, and the reclamation target may grow from 512 MiB toward
the 1 GiB maximum. ImagePool retains compatible reusable images via soft references.
These are allocation/ownership policies, not a proof of stable process or driver
memory. A six-round Viewport/mobile run with the same 256 MiB Java heap is now
in progress, without forced GC or changed pool limits. The three-round resource
delta decomposition is in artifacts/review-residual-growth-analysis.json.

## Six-round follow-up completed (2026-11-11)

The same Viewport/mobile workload completes six rounds (409 Java/native samples,
988 process samples, 40 natural GCs, final_owned=0). No forced GC or budget change.
Targets remain 232 in rounds 3–6. Homepage static MiB: 235.78/238.11/240.61/241.24;
texture MiB: 869.86/872.09/873.64/873.64. Shared target mesh entries stay <=4096.
Material/shader/slot caches still fill, so owned count is not a constant-baseline
metric. Those caches have independent lifetimes/bounds; retirement lists are zero
at the recorded endpoints. Full report: review-shared-mesh-six-rounds.json and
.analysis.json under artifacts/reference.

Process tail-half private-memory slope is +9.70 MiB/min. To avoid mistaking exit
teardown for improvement, the separate 750-second-to-ten-seconds-before-final-page
window spans 3876.29–3895.27 MiB with +4.87 MiB/min slope. Thus the result shows
reduced, slowing growth at this duration, not zero growth or proof against all
small leaks. The excessive per-target geometry-cache budget multiplication is
fixed and regression tested; no further defect is established by these bounded
observations. The six-round result supersedes earlier pending-run notes above.
