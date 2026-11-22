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
