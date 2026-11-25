#!/usr/bin/env python3
"""Measure decoded video frames using Godot or the native JavaFX SDK."""
import argparse
import hashlib
import json
import re
import subprocess

from jdk_home import add_jdk_argument, configure_jdk
from godot_driver import DEFAULT_DRIVER, add_driver_argument
from macos_probe import NATIVE_MARKER, NATIVE_PRISM
from macos_probe import GRAPHICS, MEDIA, LOGS, ROOT, compile_probe, isolated_project, native_probe, require, scene_probe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_jdk_argument(parser)
    group = parser.add_mutually_exclusive_group()
    add_driver_argument(group)
    group.add_argument("--native", action="store_true")
    parser.add_argument("--rate", type=int, choices=[1, 2], default=1)
    parser.add_argument("--sample", type=int, choices=range(21), default=0, help="trial number for the log")
    for option in ("clock-skew", "native60", "no-vsync", "frame-phases", "runtime"):
        parser.add_argument("--" + option, action="store_true")
    args = parser.parse_args()
    configure_jdk(args.jdk)
    if args.native and args.runtime:
        parser.error("--runtime requires Godot")
    driver = args.driver or DEFAULT_DRIVER
    if args.native60:
        video = ROOT / "agentdir/media/media-1080p60.mp4"
        manifest = json.loads(video.with_suffix(".json").read_text())
        for field, value in dict(width=1920, height=1080, fps=60, frames=960, seconds=16, codec="H264",
                sha256=hashlib.sha256(video.read_bytes()).hexdigest(), source_sha256=hashlib.sha256(
                (ROOT / "scripts/make-media-fixture.py").read_bytes()).hexdigest()).items():
            if manifest.get(field) != value:
                raise SystemExit("Regenerate the fixture with scripts/make-media-fixture.py")
    else:
        video = ROOT / subprocess.check_output([ROOT / "scripts/setup-env.py", "--sample-path", "oracle"], text=True).strip()
    modules = "javafx.controls,javafx.media"
    compile_probe("MediaFrameBenchmark", modules=modules, exports=GRAPHICS + MEDIA)
    backend = f"native-{NATIVE_PRISM}" if args.native else driver
    flags = "".join("-" + key for key in ("clock_skew", "native60", "no_vsync", "frame_phases", "runtime") if getattr(args, key))
    log = LOGS / f"media-frame-{backend}-rate{args.rate}-sample{args.sample}{flags}.log"
    env = dict(GODOT_JFX_MEDIA_FRAME_PHASES=str(int(args.frame_phases)), GODOT_JFX_MEDIA_RATE=str(args.rate),
               GODOT_JFX_MEDIA_CLOCK=str(int(args.clock_skew)), GODOT_JFX_MEDIA_FIXTURE="1080p60" if args.native60 else "oracle30",
               GODOT_JFX_MEDIA_FILE=str(video))
    host = None
    if args.native:
        options = [f"--add-exports={p}=ALL-UNNAMED" for p in GRAPHICS + MEDIA]
        options += ["--add-opens=javafx.media/javafx.scene.media=ALL-UNNAMED"]
        if args.no_vsync:
            options.append("-Dprism.vsync=false")
        output = native_probe("MediaFrameBenchmark", log, modules, options, env)
        require(output, NATIVE_MARKER)
    else:
        scene = "media_frame_benchmark"
        project = isolated_project(scene, ROOT / "artifacts/runtime-media-frames") if args.runtime else None
        output = scene_probe(scene, driver, log, env, ["--disable-vsync"] if args.no_vsync else [], project)
        require(output, "GODOT_MEDIA_FRAME_PASS", "glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline")
        host = json.loads(next(line.split(" ", 1)[1] for line in output.splitlines() if line.startswith("MEDIA_FRAME_HOST ")))
        if host["unfocused_ticks"] != 0:
            raise SystemExit("Host measurement lost window focus")
    require(output, "MEDIA_FRAME_BENCHMARK_PASS")
    sample = re.search(r"^MEDIA_FRAME_JAVA .* rendered_fps=([0-9.]+) .*unfocused=0$", output, re.M)
    if not sample:
        raise SystemExit("Missing focused Java frame measurement")
    if args.native60 and args.rate == 1:
        if float(sample[1]) < 55 or (host and (host["elapsed_ms"] <= 0 or
                host["presentations"] * 1000 / host["elapsed_ms"] < 55 or host["backpressure"] != 0)):
            raise SystemExit("1080p60 throughput/backpressure check failed")
        print("MEDIA_FRAME_60FPS_ACCEPTANCE_PASS minimum_fps=55")
    print(sample[0])


if __name__ == "__main__":
    main()
