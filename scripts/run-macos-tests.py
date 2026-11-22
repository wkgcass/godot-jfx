#!/usr/bin/env python3
"""Run the macOS arm64 scene and distribution tests serially on an idle desktop."""
import argparse
import csv
import datetime
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from jdk_home import add_jdk_argument, configure_jdk
from godot_driver import MACOS_DRIVERS, check_case_logs

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
DESKTOP = {"robot", "drag-drop-external", "native-ime", "hover-demo", "virtual-keyboard"}
OPTIONAL_ROBOT = {"drag-drop", "physical-drag", "hover-flicker", "vfx-table-scroll"}
VARIANTS = {
    "bridge": ["--encoded", "--stop-from-host", "--textures", "--prism-textures", "--shader-states", "--prism-context"],
    "drag-drop-ole-inject": ["--timeout"], "failure-shutdown": ["--probe FailureApplicationProbe"],
    "file-dialog": ["--stop-host"], "godot-view": ["--transform"], "ime": ["--spaced-click"],
    "mesh-transform": ["--cache-pressure"], "native-churn": ["--kind Idle", "--kind SubViewport", "--kind JavaFXNativeWindow"],
    "pacing-cap": ["--mode restore", "--mode override"],
    "queued-texture-update": ["--batch-boundary", "--viewport-state"],
    "readback": ["--snapshot", "--snapshot-stress", "--stop-during-read"],
    "scene-textures": ["--resize", "--missing-scene"], "media-churn": ["--audio-only"],
    "vfx-stage": ["--abrupt"], "vfx-loading": ["--cancel"], "vfx-dialog": ["--inject-failure"],
    "vfx-animation": ["--timing-only"], "media-video": ["--sample lk"],
    "vfx-intro": ["--all-pages --freeze-fusion --page-limit 3"],
}
DEFAULTS = {"media-audio": "--codec all", "vfx-intro": "--all-pages"}


def cases(group, drivers, selection="all"):
    if group == "NonRobot" and selection != "variants":
        for driver in drivers:
            yield [str(SCRIPTS / "test-driver-config.py"), "--driver", driver], {}
            for script in ("test-godot-library", "test-shadow-jar", "test-vfx-demo-jar"):
                args = [] if script.endswith("demo-jar") else ["--runtime", str(ROOT / "artifacts/godot-library")]
                yield [str(SCRIPTS / (script + ".py")), *args, "--driver", driver], {}
            args = ["--disable-vsync", "--max-fps", "60"] if driver == "opengl" else []
            yield [str(SCRIPTS / "run-vfx-demo.sh"), "--smoke", "--driver", driver, *args], {}

    for script in sorted(SCRIPTS.glob("test-*.sh")):
        name = script.stem[5:]
        robot = group == "Robot"
        if robot and name not in DESKTOP | OPTIONAL_ROBOT or not robot and name in DESKTOP:
            continue
        variants = [DEFAULTS.get(name, "")]
        if robot:
            if name in (OPTIONAL_ROBOT - {"vfx-table-scroll"}) | {"virtual-keyboard"}:
                variants = ["--robot"]
        else:
            variants.extend(VARIANTS.get(name, []))
        flags = script.read_text()
        if "--runtime)" in flags:
            variants.append("--runtime")
        takes_driver = "--driver)" in flags
        if name == "render-mode-rejection":
            if "opengl" in drivers and selection != "variants":
                yield [str(script), "--driver", "opengl"], {}
            continue
        if selection == "default":
            variants = variants[:1]
        elif selection == "variants":
            variants = variants[1:]
        backends = drivers if takes_driver else [None]
        for driver in backends:
            for variant in variants:
                args = ["--driver", driver] if takes_driver else []
                args.extend(variant.split())
                extra = {"GODOT_JFX_DRAG_MODE": "robot"} if robot and name == "vfx-table-scroll" else {}
                yield [str(script), *args], extra


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_jdk_argument(parser)
    parser.add_argument("--group", choices=["NonRobot", "Robot"], default="NonRobot")
    parser.add_argument("--driver", choices=[*MACOS_DRIVERS, "all"], default="metal")
    parser.add_argument("--cases", choices=["all", "default", "variants"], default="all",
                        help="select the default invocation, additional variants, or both")
    parser.add_argument("--test", nargs="+", metavar="NAME", help="select named test scripts within the group")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--results", type=Path)
    args = parser.parse_args()
    tests = list(cases(args.group, MACOS_DRIVERS if args.driver == "all" else [args.driver], args.cases))
    if args.test:
        names = set(args.test)
        unknown = names.difference(Path(command[0]).stem for command, _ in tests)
        if unknown:
            parser.error(f"Unavailable for this group and driver: {', '.join(sorted(unknown))}")
        tests = [(command, extra) for command, extra in tests if Path(command[0]).stem in names]
    if args.list:
        for command, env in tests:
            print(*[f"{k}={v}" for k, v in env.items()], *command)
        return
    if sys.platform != "darwin":
        parser.error("macOS is required")
    configure_jdk(args.jdk)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    output = (args.results or ROOT / "agentdir/logs" / f"macos-{args.group}-{stamp}").resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.pop("GODOT_JFX_DRAG_MODE", None)
    failed = False
    with (output / "results.csv").open("x", newline="") as results:
        writer = csv.writer(results)
        writer.writerow(["Test", "Arguments", "Result", "Exit", "Seconds", "Log"])
        for index, (command, extra) in enumerate(tests, 1):
            name = Path(command[0]).stem
            work = None
            if name in ("test-godot-library", "test-shadow-jar"):
                archive = ROOT / "agentdir/artifacts"
                archive.mkdir(parents=True, exist_ok=True)
                work = Path(tempfile.mkdtemp(prefix=f"{output.name}-{index:03}-{name}-", dir=archive))
                command += ["--work", str(work)]
            log = output / f"{index:03}-{name}.log"
            options = " ".join([*(f"{k}={v}" for k, v in extra.items()), *command[1:]])
            child_env = env | extra
            print(f"[{index}/{len(tests)}] {name} {options}", flush=True)
            start = time.monotonic()
            started_ns = time.time_ns()
            python_test = command[0].endswith(".py")
            if python_test:
                command = [sys.executable, *command]
            with log.open("w") as stream, subprocess.Popen(command, cwd=ROOT, env=child_env, start_new_session=True,
                    stdout=stream, stderr=subprocess.STDOUT) as child:
                try:
                    code = child.wait(timeout=1500 if name in ("test-vfx-soak", "test-godot-library", "test-shadow-jar") else 600)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    code = 124
                except KeyboardInterrupt:
                    os.killpg(child.pid, signal.SIGKILL)
                    raise
            status = "FAIL" if code else "SKIP" if log.read_text(errors="replace").startswith("SKIP:") else "PASS"
            if work:
                for source in work.rglob("*.log"):
                    target = output / f"{index:03}-{name}" / source.relative_to(work)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
            raw_logs = []
            if not python_test:
                for source in (ROOT / "agentdir/logs").iterdir():
                    if source.is_file() and source.suffix in (".log", ".import", ".diff") and source != log and source.stat().st_mtime_ns >= started_ns:
                        directory = output / f"{index:03}-{name}"
                        directory.mkdir(exist_ok=True)
                        archived = Path(shutil.copy2(source, directory))
                        if archived.suffix == ".log":
                            raw_logs.append(archived)
                reference = ROOT / "artifacts/reference"
                for source in reference.rglob("*"):
                    if source.suffix.lower() in (".png", ".csv", ".json") and source.is_file() and source.stat().st_mtime_ns >= started_ns:
                        target = output / f"{index:03}-{name}" / "reference" / source.relative_to(reference)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source, target)
            if status == "PASS" and not python_test and "--driver" in command:
                driver = command[command.index("--driver") + 1]
                try:
                    evidence = check_case_logs(raw_logs, driver)
                except (AssertionError, OSError) as error:
                    evidence = [str(error)]
                    status, code = "FAIL", 1
                with log.open("a") as stream:
                    print(*evidence, sep="\n", file=stream)
            writer.writerow([name, options, status, code, round(time.monotonic()-start, 1), log.name])
            results.flush()
            failed |= code != 0
            print(status, log, flush=True)
    raise SystemExit(int(failed))


if __name__ == "__main__":
    main()
