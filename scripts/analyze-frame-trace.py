"""Summarize optional frame traces. Counter intervals overlap; never sum them."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("log", type=Path)
args = parser.parse_args()
lines = args.log.read_text(encoding="utf-8-sig").splitlines()
if "VFX_FRAME_BENCHMARK_PASS" not in lines:
    raise SystemExit("Incomplete benchmark")

def record(name, required=True):
    prefix = name + " "
    matches = [json.loads(line[len(prefix):]) for line in lines if line.startswith(prefix)]
    if len(matches) != 1 and (required or matches):
        raise SystemExit(f"Expected exactly one {name} record, got {len(matches)}")
    return matches[0] if matches else None

java = record("VFX_FRAME_TRACE_JAVA")
host = record("VFX_FRAME_TRACE_HOST", required=False)
phases = record("VFX_FRAME_TRACE_PHASES", required=False)
if not java or (host is not None and (len(host) < 2 or "GODOT_VFX_FRAME_BENCHMARK_PASS" not in lines)):
    raise SystemExit("Incomplete trace or host run")
rows = []
if host:
    for previous, current in zip(host, host[1:]):
        row = {"end_ms": current["time_us"] / 1000}
        for key in ("time_us", "process_us", "encode_us", "draw_sync_us", "metadata_us", "host_commands_us"):
            row[key.replace("_us", "_ms")] = (current[key] - previous[key]) / 1000
        for key in ("presentations", "offscreen_passes", "jni_submit_calls", "jni_submit_us", "texture_patch_commands", "texture_patch_uploads"):
            if key not in current:
                continue
            row[key] = current[key] - previous[key]
        for key in current:
            if key.startswith("profile_"):
                difference = current[key] - previous[key]
                row[key.replace("_us", "_ms")] = difference / 1000 if key.endswith("_us") else difference
        rows.append(row)
rounds = []
for number in sorted({sample[2] for sample in java}):
    gaps = sorted(sample[1] / 1000 for sample in java if sample[2] == number)
    rounds.append({"round": number, "intervals": len(gaps), "over_33ms": sum(gap > 33 for gap in gaps), "max_ms": max(gaps)})
report = {
    "source": str(args.log),
    "unfocused_intervals": next((int(re.search(r"unfocused_intervals=(\d+)", line)[1]) for line in lines if line.startswith("VFX_FRAME_FOCUS ")), None),
    "note": "Instrumented diagnostic; host/Java origins differ by title transport. CPU/sync counters overlap and are wall times, not GPU timings.",
    "java_rounds": rounds,
    "longest_java": [{"end_ms": t / 1000, "gap_ms": gap / 1000, "round": r} for t, gap, r in sorted(java, key=lambda sample: sample[1], reverse=True)[:20]],
    "longest_host": sorted(rows, key=lambda row: row["time_ms"], reverse=True)[:20],
}
if phases is not None:
    if len(phases) < 2 or any(b[0] < a[0] for a, b in zip(phases, phases[1:])):
        raise SystemExit("Incomplete or non-monotonic phase trace")
    gaps = [{"end_ms": b[0] / 1000, "gap_ms": (b[0] - a[0]) / 1000,
             "from": a[1], "to": b[1]} for a, b in zip(phases, phases[1:])]
    report["longest_phase_gaps"] = sorted(gaps, key=lambda row: row["gap_ms"], reverse=True)[:20]
    report["phase_note"] = "Main-thread event gaps include intervening work and scheduling; post_draw_callback is deferred in separate mode, not GPU completion timing."
output = args.log.with_suffix(".analysis.json")
output.write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps({"output": str(output), "unfocused_intervals": report["unfocused_intervals"], "java_rounds": rounds, "longest_host": report["longest_host"][:5], "longest_phase_gaps": report.get("longest_phase_gaps", [])[:5]}, indent=2))
