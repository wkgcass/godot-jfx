#!/usr/bin/env python3
"""Measure VFX frames, transition rendering, GPU commands, menu interaction or loading on macOS."""
import argparse
import re

from jdk_home import add_jdk_argument, configure_jdk
from macos_probe import GRAPHICS, LOGS, ROOT, compile_probe, isolated_project, native_probe, require, scene_probe

PROBES = {
    "frames": ("VfxFrameBenchmark", "vfx_frame_benchmark", "VFX_FRAME_BENCHMARK_PASS"),
    "transitions": ("VfxTransitionProbe", "vfx_transition", "VFX_TRANSITION_BENCHMARK_PASS"),
    "gpu": ("VfxFrameBenchmark", "vfx_frame_benchmark", "VFX_FRAME_BENCHMARK_PASS"),
    "menu": ("VfxMenuPerformanceProbe", "vfx_menu_performance", "VFX_MENU_PERFORMANCE_PASS"),
    "loading": ("VfxLoadingPerfProbe", "vfx_loading_perf", "VFX_LOADING_PERF_PASS"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    for mode in PROBES:
        p = commands.add_parser(mode)
        add_jdk_argument(p)
        backend = p.add_mutually_exclusive_group()
        backend.add_argument("--driver", choices=["metal", "opengl"])
        if mode == "frames":
            backend.add_argument("--native", action="store_true", help="use the SDK's Mac Glass and Prism Metal")
            p.add_argument("--trace", action="store_true")
        if mode in ("frames", "gpu"):
            p.add_argument("--host120", action="store_true")
        if mode == "menu":
            p.add_argument("--full-uploads", action="store_true")
    args = parser.parse_args()
    configure_jdk(args.jdk)
    driver = args.driver or "metal"
    native = getattr(args, "native", False)
    host120 = getattr(args, "host120", False)
    trace = getattr(args, "trace", False)
    if native and host120:
        parser.error("--host120 requires Godot")
    name, scene, marker = PROBES[args.mode]
    extras = ["ThreadStackSampler"] if args.mode == "transitions" else []
    compile_probe(name, *extras, exports=GRAPHICS)
    label = "native-mtl" if native else driver
    flags = "".join("-" + opt for opt in ("trace", "host120", "full_uploads") if getattr(args, opt, False))
    log = LOGS / f"vfx-{args.mode}-{label}{flags}.log"
    env = {"GODOT_JFX_BENCHMARK_TRACE": str(int(trace)), "GODOT_JFX_BENCHMARK_MAILBOX": "0"}
    if trace or args.mode in ("gpu", "menu", "loading"):
        env["GODOT_JFX_PROFILE_COMMANDS"] = "1"
    if args.mode == "menu":
        env["GODOT_JFX_REGION_UPLOAD"] = "0" if args.full_uploads else "1"

    if native:
        output = native_probe(name, log, "javafx.controls,javafx.swing",
                              [f"--add-exports={p}=ALL-UNNAMED" for p in GRAPHICS], env)
        require(output, "glass=com.sun.glass.ui.mac.MacApplication prism=com.sun.prism.mtl.MTLPipeline")
    else:
        project = None
        host_args = ["--disable-vsync", "--max-fps", "120"] if host120 else []
        if args.mode == "gpu":
            # M1 counter samples occupy eight bytes each in a 32 KiB Metal buffer.
            samples = 4096 if driver == "metal" else 8192
            project = isolated_project(scene, ROOT / "artifacts/vfx-gpu-profile",
                                       f"\n[debug]\nsettings/profiler/max_timestamp_query_elements={samples}\n")
            host_args.append("--gpu-profile")
        output = scene_probe(scene, driver, log, env, host_args, project)
        require(output, "GODOT_" + scene.upper() + "_PASS")
        if args.mode in ("frames", "transitions", "gpu"):
            require(output, "glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline")
        if args.mode == "gpu":
            totals = re.findall(r"^GPU PROFILE \(total ([\d.]+)ms\)", output, re.M)
            if not any(float(total) > 0 for total in totals):
                raise SystemExit(f"No GPU timestamp measurements in {log}")
    require(output, marker)
    if args.mode == "transitions":
        require(output, "VFX_TRANSITION_RESOURCE_CLEANUP_PASS")
        if not any(int(line.split()[-1]) > 0 for line in output.splitlines() if line.startswith("VFX_TRANSITION_TARGET_SWITCHES ")):
            raise SystemExit("Missing positive Prism target-switch count")
    if trace:
        require(output, "VFX_FRAME_TRACE_JAVA ")
        if not native:
            require(output, "VFX_FRAME_TRACE_HOST ", "VFX_FRAME_TRACE_PHASES ", "profile_geometry_us", "profile_render_offscreen_us")
    for line in output.splitlines():
        if line.startswith(("MENU_PERF ", "LOADING_PERF ", "VFX_TRANSITION_", "VFX_FRAME_")) and "TRACE_" not in line:
            print(line)


if __name__ == "__main__":
    main()
