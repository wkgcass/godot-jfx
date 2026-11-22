#!/usr/bin/env python3
"""Record an interactive macOS VFX hover reproduction, or analyze an existing log."""
import argparse
from datetime import datetime
from pathlib import Path
import re

from macos_probe import LOGS, scene_probe

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--driver", choices=["metal", "opengl"], default="metal")
parser.add_argument("--no-sample", action="store_true")
parser.add_argument("--log-path", type=Path)
args = parser.parse_args()
if args.log_path:
    output = args.log_path.read_text(errors="replace")
else:
    log = LOGS / f"hover-manual-{datetime.now():%Y%m%d-%H%M%S}.log"
    print(f"Reproduce the hover and close the Demo to finish. Log: {log}", flush=True)
    output = scene_probe("vfx_demo", args.driver, log, {"GODOT_JFX_DEMO_SMOKE": "0", "GODOT_JFX_HOVER_TAP": "1",
                        "GODOT_JFX_HOVER_SAMPLE": str(int(not args.no_sample))})

for kind in ("HOST_GAP", "HOST_PHASE", "FX_GAP", "FX_TASK"):
    lines = re.findall(r"HOVER_TAP [^\n]*? " + kind + r" [^\n]*", output)
    print(f"{kind} ({len(lines)} hits)")
    print(*lines[:30], sep="\n")
start = None
previous_frame = previous_luma = None
for frame_text, luma_text in re.findall(r"HOVER_SAMPLE f=(\d+) luma=([0-9.]+)", output):
    frame, luma = int(frame_text), float(luma_text)
    consecutive = previous_frame is not None and frame == previous_frame + 2
    if consecutive and luma == previous_luma:
        if start is None:
            start = previous_frame
    else:
        if consecutive and start is not None and previous_frame - start >= 24 and abs(luma - previous_luma) >= .03:
            print(f"Constant luma f={start}..{previous_frame} luma={previous_luma} then {luma}")
        start = None
    previous_frame, previous_luma = frame, luma
if re.search(r"^(?:ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)", output, re.M):
    raise SystemExit("Hover log contains errors")
