#!/usr/bin/env python3
"""Verify the active graphics API of an automatically started JavaFX application."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from jdk_home import add_jdk_argument, configure_jdk
from godot_driver import DEFAULT_DRIVER, DEVICE_LINE, DRIVER_MARKER, MACOS_DRIVERS, WINDOWS_DRIVERS, check_driver
from library_test_platform import ROOT, WINDOWS
from maven_local import test_jars


DRIVERS = WINDOWS_DRIVERS if WINDOWS else MACOS_DRIVERS
GRAPHICS_LIBRARIES = re.compile(r"(?i)[/\\](d3d12(?:core)?\.dll|dxgi\.dll|vulkan-1\.dll|opengl32\.dll|"
                                r"godot\.dll|libgodot\.dylib|Metal\.framework/[^\s]*Metal|"
                                r"OpenGL\.framework/[^\s]*OpenGL)(?=\s|$)")


def snapshot_modules(jdk, app, log, env):
    deadline = time.monotonic() + 60
    while b"APPLICATION_START" not in log.read_bytes().splitlines():
        if app.poll() is not None:
            raise AssertionError(f"Application exited before showing its window: {log}")
        if time.monotonic() >= deadline:
            raise TimeoutError(f"Application did not show its window: {log}")
        time.sleep(.05)
    snapshot = log.with_name(log.stem + "-modules.txt")
    with snapshot.open("wb") as out:
        subprocess.run([jdk / "bin/jcmd", str(app.pid), "VM.dynlibs"], stdout=out, stderr=subprocess.STDOUT,
                       env=env, timeout=20, check=True)
    listing = snapshot.read_text(encoding="utf-8", errors="replace")
    return sorted(set(GRAPHICS_LIBRARIES.findall(listing)), key=str.lower)


def check_launch(jdk, module_path, work, logs, requested):
    label = requested or "default"
    log = logs / f"{label}.log"
    args = [jdk / "bin/java", "--module-path", module_path, "--add-modules", "javafx.controls",
            "--enable-native-access=javafx.graphics"]
    if requested != "invalid":
        args.append("-Dtest.awaitModuleSnapshot=true")
    if requested is not None:
        args.append(f"-Djavafx.godot.driver={requested}")
    args += ["-cp", str(work), "DirectApplication"]
    env = os.environ.copy()
    for key in ("JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS"):
        env.pop(key, None)
    libraries = []
    with log.open("wb") as stream, subprocess.Popen(args, cwd=work, env=env, stdin=subprocess.PIPE,
            stdout=stream, stderr=subprocess.STDOUT) as app:
        try:
            if requested != "invalid":
                libraries = snapshot_modules(jdk, app, log, env)
                app.stdin.write(b"\n")
                app.stdin.flush()
            code = app.wait(timeout=60)
        finally:
            if app.poll() is None:
                app.kill()
                app.wait()
    output = log.read_text(encoding="utf-8", errors="replace")
    lines = output.splitlines()
    if requested == "invalid":
        if (not code or DEVICE_LINE.search(output) or DRIVER_MARKER.search(output)
                or "APPLICATION_START" in lines or "Invalid javafx.godot.driver" not in output):
            raise AssertionError(f"Invalid driver was not rejected before startup: {log}")
        print("PASS invalid driver rejected", flush=True)
        return
    driver = requested or DEFAULT_DRIVER
    actual, header = check_driver(output, driver, log)
    required = {"libgodot.dylib"}
    if WINDOWS:
        api_dll = {"d3d12": "d3d12.dll", "vulkan": "vulkan-1.dll", "opengl": "opengl32.dll"}[driver]
        required = {"godot.dll", api_dll}
    missing = required.difference(name.lower() for name in libraries)
    if missing:
        raise AssertionError(f"Missing loaded libraries {sorted(missing)}: {logs / (label + '-modules.txt')}")
    if code or not {"APPLICATION_START", "APPLICATION_STOP"}.issubset(lines):
        raise AssertionError(f"Application lifecycle failed (exit {code}): {log}")
    print(f"PASS requested={label} actual={actual} | {header}", flush=True)
    print(f"  Loaded: {', '.join(libraries)}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_jdk_argument(parser)
    parser.add_argument("--driver", choices=[*DRIVERS, "all"], default=DEFAULT_DRIVER)
    args = parser.parse_args()
    jdk = configure_jdk(args.jdk)
    module_path = os.pathsep.join(map(str, test_jars()))
    log_root = ROOT / "agentdir/logs"
    log_root.mkdir(parents=True, exist_ok=True)
    logs = Path(tempfile.mkdtemp(prefix="driver-config-", dir=log_root))
    print(f"Evidence: {logs}", flush=True)
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        subprocess.run([jdk / "bin/javac", "--module-path", module_path, "--add-modules", "javafx.controls",
                        "-encoding", "UTF-8", "-d", work, ROOT / "tests/library/DirectApplication.java"], check=True)
        drivers = list(DRIVERS) if args.driver == "all" else [args.driver]
        if DEFAULT_DRIVER in drivers:
            check_launch(jdk, module_path, work, logs, None)
        for driver in drivers:
            check_launch(jdk, module_path, work, logs, driver)
        if DEFAULT_DRIVER in drivers:
            check_launch(jdk, module_path, work, logs, "invalid")


if __name__ == "__main__":
    main()
