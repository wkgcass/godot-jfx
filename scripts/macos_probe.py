"""Launch Unix desktop measurement probes with the SDK and fixtures used by the regressions."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from jdk_home import configure_jdk
from godot_driver import check_driver
import native_prism
from native_prism import PRISM as NATIVE_PRISM

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / "jfx/build/sdk/lib"
OUT = ROOT / "artifacts/reference"
LOGS = ROOT / "agentdir/logs"
CP = os.pathsep.join(map(str, [OUT, *(ROOT / "artifacts/vfx" / path for path in (
    "classes/java/main", "classes/java/test", "resources/main", "resources/test", "dependencies/*"))]))
GRAPHICS = ["javafx.graphics/com.sun.prism", "javafx.graphics/com.sun.glass.ui"]
MEDIA = ["javafx.media/com.sun.media.jfxmedia" + suffix for suffix in ("", ".control", ".events")]
if sys.platform == "linux":
    NATIVE_MARKER = "glass=com.sun.glass.ui.gtk.GtkApplication prism=com.sun.prism.es2.ES2Pipeline"
else:
    NATIVE_MARKER = "glass=com.sun.glass.ui.mac.MacApplication prism=com.sun.prism.mtl.MTLPipeline"


def compile_probe(*classes, modules="javafx.controls", exports=()):
    OUT.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    subprocess.run([configure_jdk() / "bin/javac", "--module-path", SDK, "--add-modules", modules,
                    *(f"--add-exports={p}=ALL-UNNAMED" for p in exports), "-encoding", "UTF-8",
                    "-cp", CP, "-d", OUT, *(ROOT / "tests/reference" / (c + ".java") for c in classes)], check=True)


def run(command, log, env=None):
    print(f"Log: {log}", file=sys.stderr, flush=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    with log.open("wb") as stream:
        result = subprocess.run(command, cwd=ROOT, env=os.environ | (env or {}), stdout=stream, stderr=subprocess.STDOUT)
    output = log.read_text(errors="replace")
    if result.returncode or re.search(r"^(?:ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError", output, re.M):
        raise SystemExit(f"Probe failed (exit {result.returncode}): {log}")
    return output


def require(output, *markers):
    for marker in markers:
        if marker not in output:
            raise SystemExit(f"Missing probe result: {marker}")


def isolated_project(scene, directory, settings=""):
    source = ROOT / "tests/godot"
    directory.mkdir(parents=True, exist_ok=True)
    tscn = source / (scene + ".tscn")
    shutil.copyfile(tscn, directory / tscn.name)
    for dependency in re.findall(r'path="res://([^"]+)"', tscn.read_text()):
        target = directory / dependency
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / dependency, target)
    project = (source / "project.godot").read_text().replace("res://main.tscn", f"res://{scene}.tscn")
    (directory / "project.godot").write_text(project + settings)
    from library_test_platform import EDITOR
    run([EDITOR, "--headless", "--path", directory, "--editor", "--import"],
        LOGS / (directory.name + "-import.log"))
    return directory


def scene_probe(scene, driver, log, env=None, args=(), project=None):
    path = ["--path", project] if project else ["--path", "tests/godot", f"res://{scene}.tscn"]
    output = run([sys.executable, ROOT / "scripts/godot-fixture.py", "--driver", driver, *path,
                  "--render-thread", "safe", *args], log, env)
    check_driver(output, driver, log)
    return output


def native_probe(name, log, modules, options=(), env=None):
    return run([configure_jdk() / "bin/java", *(f"-D{k}={v}" for k, v in native_prism.properties().items()), "--module-path", SDK,
                "--add-modules", modules, "--enable-native-access=javafx.graphics,ALL-UNNAMED" +
                (",javafx.media" if "javafx.media" in modules else ""), *options, "-cp", CP, name], log, native_prism.environment() | (env or {}))
