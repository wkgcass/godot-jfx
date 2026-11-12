"""Summarize current-process samples; no claim of leak freedom from a trend alone."""
import json
import statistics
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8-sig"))
count = data["cycles"]
process = data["process_samples"]
native = data["native_samples"]
java = data["java_samples"]
for samples in (process, java, *([] if data.get("native_d3d") else [native])):
    if [row["cycle"] for row in samples] != list(range(1, count + 1)):
        raise ValueError("Incomplete or unordered checkpoints")
if not data["playback_and_cleanup_passed"] or len({s["pid"] for s in process}) != 1:
    raise ValueError("Failed playback or mixed sampled processes")

def ranges(rows, fields):
    return {field: {"min": min(s[field] for s in rows),
                    "median": statistics.median(s[field] for s in rows),
                    "max": max(s[field] for s in rows)} for field in fields}

half = count // 2
timing = process if "elapsed_ms" in process[0] else native
times = [s["elapsed_ms"] / 60000 for s in timing[half:]]
values = [s["private_bytes"] for s in process[half:]]
tx, vx = statistics.mean(times), statistics.mean(values)
denom = sum((t-tx)**2 for t in times)
slope = sum((t-tx)*(v-vx) for t, v in zip(times, values)) / denom if denom else None
blocks = []
for start in range(0, count, 24):
    rows = process[start:start+24]
    blocks.append({"first_cycle": rows[0]["cycle"], "last_cycle": rows[-1]["cycle"],
                   **ranges(rows, ("private_bytes", "working_set", "handles"))})
result = {
    "source": str(path), "cycles": count, "pid": process[0]["pid"],
    "elapsed_ms_last_checkpoint": timing[-1]["elapsed_ms"],
    "forced_gc": data["forced_gc"], "gc_count_last": java[-1]["gc_count"],
    "process_latter_half": ranges(process[half:], ("private_bytes", "working_set", "handles")),
    "private_bytes_per_minute_latter_half_ols": slope,
    "process_blocks": blocks,
    "native_latter_half": ranges(native[half:], ("owned", "texture_bytes", "static_bytes")) if native else None,
    "idle_samples": data.get("idle_samples", []),
    "java_threads": ranges(process, ("java_threads",)) if "java_threads" in process[0] else None,
    "heap": ranges(java, ("heap_used",)),
    "limitations": "Post-dispose checkpoints, not continuous peak sampling. Bounded workload; positive or negative OLS alone is not leak acceptance."
}
output = path.with_suffix(".analysis.json")
output.write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result, indent=2))
