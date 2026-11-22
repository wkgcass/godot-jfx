#!/usr/bin/env python3
"""Launch a scene fixture with the published OpenJFX modules on the classpath."""
import argparse
import json
import os
import re
from pathlib import Path
import subprocess
import sys

from godot_driver import add_driver_argument, DEFAULT_DRIVER
from maven_local import test_jars

ROOT = Path(__file__).resolve().parents[1]


def command(args, working_directory):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    add_driver_argument(parser)
    if sys.platform == "darwin":
        parser.add_argument("--runtime", action="store_true", help="import just the selected standalone scene")
    options, args = parser.parse_known_args(args)
    if any(arg.split("=", 1)[0] in ("--renderer", "--rendering-method", "--rendering-driver") for arg in args):
        parser.error("select the Godot backend with --driver")
    jvm_options = [f"-Djavafx.godot.driver={options.driver or DEFAULT_DRIVER}"]
    windows = os.name == "nt"
    if not windows and sys.platform != "darwin":
        raise RuntimeError("Scene fixtures require the Windows or macOS platform JARs")
    java_home = os.environ.get("GODOT_JFX_JDK") or os.environ.get("JAVA_HOME")
    if windows and not java_home:
        raise ValueError("Set JAVA_HOME to the source build JDK")
    jdk = Path(java_home or ROOT / ".tools/jdk-25/Contents/Home")
    jars = test_jars()
    classes = ROOT / "artifacts/reference"
    classes.mkdir(exist_ok=True, parents=True)
    source = ROOT / "tests/reference/GodotSceneFixture.java"
    compiled = classes / "com/sun/javafx/tk/godot/GodotSceneFixture.class"
    inputs_modified = max(path.stat().st_mtime_ns for path in [source, *jars])
    if not compiled.exists() or compiled.stat().st_mtime_ns < inputs_modified:
        javac = jdk / ("bin/javac.exe" if windows else "bin/javac")
        subprocess.run([javac, "-cp", os.pathsep.join(map(str, jars)), "-d", classes, source], check=True)
    if "--path" not in args:
        args = ["--path", str(working_directory), *args]
    index = args.index("--path") + 1
    if getattr(options, "runtime", False):
        from macos_probe import isolated_project
        scenes = [arg for arg in args if re.fullmatch(r"res://[a-z0-9_]+\.tscn", arg)]
        if len(scenes) != 1 or (working_directory / args[index]).resolve() != ROOT / "tests/godot":
            parser.error("--runtime requires a standalone scene in tests/godot")
        scene = Path(scenes[0]).stem
        project = isolated_project(scene, ROOT / "artifacts" / ("runtime-" + scene.replace("_", "-")))
        args[index] = str(project)
        args.remove(scenes[0])
    elif (working_directory / args[index]).resolve() == ROOT / "tests/godot":
        project = subprocess.check_output([sys.executable, ROOT / "scripts/prepare-godot-fixture.py"], text=True).strip()
        args[index] = str(ROOT / "artifacts" / project)
    vfx = ROOT / "artifacts/vfx"
    cp = [*jars, classes, *(vfx / entry for entry in (
        "classes/java/main", "classes/java/test", "resources/main", "resources/test", "dependencies/*"))]
    java = jdk / ("bin/java.exe" if windows else "bin/java")
    return [str(java), *jvm_options, "--enable-native-access=ALL-UNNAMED", "-cp", os.pathsep.join(map(str, cp)),
            "com.sun.javafx.tk.godot.GodotSceneFixture", *args]


if __name__ == "__main__":
    if sys.argv[1:2] == ["--print-command"]:
        print(json.dumps(command(sys.argv[3:], Path(sys.argv[2]))))
    else:
        argv = command(sys.argv[1:], Path.cwd())
        os.execv(argv[0], argv)
