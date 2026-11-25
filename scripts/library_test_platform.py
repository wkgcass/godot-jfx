#!/usr/bin/env python3
"""Platform inputs and loaded-library observations for distribution tests."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = os.name == "nt"

LINUX = sys.platform == "linux"
if not WINDOWS and not LINUX and sys.platform != "darwin":
    raise RuntimeError("No packaged engine tests for this platform")

CLASSIFIER = "win" if WINDOWS else "linux" if LINUX else "mac-aarch64"
EDITOR = ROOT / "godot/bin" / ("godot.windows.editor.x86_64.console.exe" if WINDOWS else
                              "godot.linuxbsd.editor.x86_64" if LINUX else "godot.macos.editor.arm64")
ENGINE = ROOT / "godot/bin" / ("godot.windows.template_release.x86_64.library.dll" if WINDOWS
                                else "libgodot.linuxbsd.template_release.x86_64.library.so" if LINUX
                                else "libgodot.macos.template_release.arm64.library.dylib")
SDK_NATIVES = ROOT / "jfx/build/sdk" / ("bin" if WINDOWS else "lib")


def library(name):
    return name + ".dll" if WINDOWS else "lib" + name + (".so" if LINUX else ".dylib")


MEDIA_LIBRARIES = [library(name) for name in ("jfxmedia", "gstreamer-lite")]
if not LINUX:
    MEDIA_LIBRARIES.append(library("glib-lite"))
MEDIA_LIBRARIES.append(library("fxplugins" if LINUX or WINDOWS else "jfxmedia_avf"))


def system_path(jdk):
    system_dirs = os.path.join(os.environ["SystemRoot"], "System32") if WINDOWS else os.defpath
    return os.pathsep.join((str(jdk / "bin"), system_dirs))


if WINDOWS:
    from windows_loaded_modules import module_paths
elif LINUX:
    def module_paths(process):
        mappings = Path(f"/proc/{process.pid}/maps").read_text().splitlines()
        paths = (entry.split(maxsplit=5)[-1] for entry in mappings)
        return {Path(path).resolve() for path in paths if path.startswith("/") and ".so" in Path(path).name}
else:
    def module_paths(process):
        # lsof's txt entries include the dylibs mapped in the target JVM.
        result = subprocess.run(["/usr/sbin/lsof", "-a", "-p", str(process.pid), "-d", "txt", "-Fn"],
                                capture_output=True, text=True)
        return {Path(line[1:]).resolve() for line in result.stdout.splitlines()
                if line.startswith("n/") and line.endswith(".dylib")}
