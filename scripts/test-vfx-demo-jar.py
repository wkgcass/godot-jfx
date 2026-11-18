"""Run the full Intro JAR in isolation and check that its directory stays portable."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]


def check_windows_intro(process, deadline, jar):
    import ctypes
    from windows_loaded_modules import module_paths
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = (callback, wintypes.LPARAM)
    user32.GetWindowThreadProcessId.argtypes = (wintypes.HWND, ctypes.POINTER(wintypes.DWORD))
    user32.GetWindowTextW.argtypes = (wintypes.HWND, wintypes.LPWSTR, ctypes.c_int)
    user32.IsWindowVisible.argtypes = (wintypes.HWND,)
    user32.GhostWindowFromHungWindow.argtypes = (wintypes.HWND,)
    user32.GhostWindowFromHungWindow.restype = wintypes.HWND
    user32.IsZoomed.argtypes = (wintypes.HWND,)
    user32.PostMessageW.argtypes = (wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)
    intro = None

    @callback
    def find_intro(hwnd, _):
        nonlocal intro
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == process.pid and user32.IsWindowVisible(hwnd):
            title = ctypes.create_unicode_buffer(128)
            user32.GetWindowTextW(hwnd, title, len(title))
            if title.value == "VFX Intro":
                intro = hwnd
        return True

    first_seen = None
    while process.poll() is None and time.monotonic() < deadline:
        intro = None
        user32.EnumWindows(find_intro, 0)
        if intro is not None:
            if user32.GhostWindowFromHungWindow(intro):
                raise AssertionError("Windows replaced the VFX Intro with a ghost window")
            if first_seen is None:
                first_seen = time.monotonic()
            if time.monotonic() - first_seen >= 20:
                engines = [path for path in module_paths(process) if path.name.lower() == "godot.dll"]
                with ZipFile(jar) as archive:
                    build = archive.read("META-INF/godot-jfx/natives.id").decode("ascii").strip()
                    if len(engines) != 1 or build not in engines[0].parts:
                        raise AssertionError(f"VFX Intro loaded an unexpected engine: {engines}")
                    if hashlib.sha256(engines[0].read_bytes()).digest() != hashlib.sha256(archive.read("godot.dll")).digest():
                        raise AssertionError(f"VFX Intro loaded a different DLL from {jar}")
                print(f"VFX Intro engine pid={process.pid} path={engines[0]}", flush=True)
                # Exercise queued native messages after idle. Disabling ghosting
                # alone cannot make a blocked window process these commands.
                was_zoomed = bool(user32.IsZoomed(intro))
                for zoomed in (not was_zoomed, was_zoomed):
                    command = 0xF030 if zoomed else 0xF120  # SC_MAXIMIZE / SC_RESTORE
                    if not user32.PostMessageW(intro, 0x0112, command, 0):  # WM_SYSCOMMAND
                        raise ctypes.WinError(ctypes.get_last_error())
                    until = min(deadline, time.monotonic() + 5)
                    while bool(user32.IsZoomed(intro)) != zoomed:
                        if process.poll() is not None or time.monotonic() >= until:
                            raise AssertionError("VFX Intro did not process the queued window command")
                        time.sleep(0.05)
                if not user32.PostMessageW(intro, 0x0010, 0, 0):  # WM_CLOSE
                    raise ctypes.WinError(ctypes.get_last_error())
                return
        else:
            first_seen = None
        time.sleep(0.2)
    raise AssertionError("VFX Intro did not remain visible for the Windows responsiveness check")


def main():
    source = ROOT / "artifacts/vfx/libs/vfx-demo.jar"
    with ZipFile(source) as archive:
        entries = set(archive.namelist())
        intro = Path("io/vproxy/vfx/intro")
        for page in (ROOT / "vfx/src/test/java" / intro).glob("*.java"):
            if (intro / (page.stem + ".class")).as_posix() not in entries:
                raise AssertionError(f"Missing Intro class: {page.stem}")
        for directory in ("vfx/src/main/resources", "vfx/src/test/resources"):
            resources = ROOT / directory
            for path in resources.rglob("*"):
                if path.is_file() and path.relative_to(resources).as_posix() not in entries:
                    raise AssertionError(f"Missing VFX resource: {path}")
        if any(name.endswith((".pck", "project.godot", ".jar")) for name in entries):
            raise AssertionError("Unexpected project or nested JAR in the Demo")

    env = {k: v for k, v in os.environ.items() if not k.startswith("GODOT_") and
           k not in ("CLASSPATH", "JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS")}
    java = Path(os.environ["JAVA_HOME"]) / "bin/java"
    with tempfile.TemporaryDirectory(prefix="VFX Intro ") as directory:
        jar = Path(directory) / source.name
        shutil.copyfile(source, jar)
        log = ROOT / "artifacts/logs/vfx-demo-jar-isolated.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        args = [java, "-jar", jar.name]
        if os.name != "nt":
            args.append("--smoke")
        with log.open("wb") as output, subprocess.Popen(
                args, cwd=directory, env=env,
                stdout=output, stderr=subprocess.STDOUT) as run:
            deadline = time.monotonic() + 75
            try:
                if os.name == "nt":
                    check_windows_intro(run, deadline, jar)
                run.wait(timeout=max(0, deadline - time.monotonic()))
            finally:
                if run.poll() is None:
                    run.kill()
        stdout = log.read_bytes()
        if run.returncode or b"VFX_DEMO_CLOSED" not in stdout or re.search(
                rb"(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:", stdout):
            raise AssertionError(f"VFX Demo failed ({run.returncode}), see {log}")
        extra = set(jar.parent.iterdir()) - {jar}
        if extra:
            raise AssertionError(f"Demo wrote files beside the JAR: {extra}")
        print(f"PASS isolated VFX Intro JAR: {log}")


if __name__ == "__main__":
    main()
