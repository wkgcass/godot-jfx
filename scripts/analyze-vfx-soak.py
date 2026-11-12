"""Summarize observations, without treating bounded samples as leak-free proof."""
import argparse
import json
import statistics
from pathlib import Path


def distribution(values):
    return {"min": min(values), "median": statistics.median(values), "max": max(values)} if values else None


def analyze(report):
    samples = report["native_samples"]
    java = report["java_samples"]
    process = report["process_samples"]
    executable = report.get("sampled_executable", "")
    process_valid = bool(executable) and not executable.lower().endswith(".console.exe")
    rounds = sorted({s["round"] for s in samples if s["round"] > 0})
    result = {
        "navigation_and_cleanup_passed": report["navigation_and_cleanup_passed"],
        "forced_gc": report["forced_gc"],
        "rounds": rounds,
        "sample_counts": {"native": len(samples), "java": len(java), "process": len(process)},
        "memory_acceptance": "observations only; assess warm-up, GC and repeated-page trends",
        "process_memory_valid": process_valid,
        "sampled_executable": executable or None,
    }
    result["round_endpoints"] = [s for s in samples if s["page"] == 0]
    result["adjacent_round_deltas"] = []
    for earlier, later in zip(rounds, rounds[1:]):
        before = {(s["page"], s["direction"]): s for s in samples if s["round"] == earlier}
        after = {(s["page"], s["direction"]): s for s in samples if s["round"] == later}
        keys = before.keys() & after.keys()
        result["adjacent_round_deltas"].append({
            "earlier": earlier, "later": later, "paired_pages": len(keys),
            **{metric: distribution([after[key][metric] - before[key][metric] for key in keys])
               for metric in ("owned", "texture_bytes", "static_bytes")},
        })
    if len(rounds) >= 2:
        first = {(s["page"], s["direction"]): s for s in samples if s["round"] == rounds[0]}
        last = {(s["page"], s["direction"]): s for s in samples if s["round"] == rounds[-1]}
        paired = []
        for key in sorted(first.keys() & last.keys()):
            paired.append({"page": key[0], "direction": key[1], **{
                metric: last[key][metric] - first[key][metric]
                for metric in ("owned", "texture_bytes", "static_bytes")}})
        result["last_minus_first_round_same_page"] = paired
        result["paired_delta_summary"] = {
            metric: distribution([s[metric] for s in paired])
            for metric in ("owned", "texture_bytes", "static_bytes")}
    result["java_heap_bytes"] = distribution([s["heap_used"] for s in java])
    if java:
        result["natural_gc_count_delta"] = java[-1]["gc_count"] - java[0]["gc_count"]
    if process and process_valid:
        tail = process[len(process) // 2:]
        xs = [s["elapsed_ms"] / 1000 for s in tail]
        ys = [s["private_bytes"] for s in tail]
        mean_x, mean_y = statistics.mean(xs), statistics.mean(ys)
        variance = sum((x - mean_x) ** 2 for x in xs)
        result["process_tail_half"] = {
            "duration_seconds": xs[-1] - xs[0],
            "private_bytes": distribution(ys),
            "working_set_bytes": distribution([s["working_set"] for s in tail]),
            "handle_count": distribution([s["handles"] for s in tail]),
            "private_bytes_ols_per_minute": (
                60 * sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / variance
                if variance else None),
        }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8-sig"))
    summary = analyze(report)
    destination = args.report.with_suffix(".analysis.json")
    destination.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in summary.items() if k != "last_minus_first_round_same_page"}, indent=2))
    print(f"Saved {destination}")
