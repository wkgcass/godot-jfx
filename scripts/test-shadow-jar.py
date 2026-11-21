#!/usr/bin/env python3
"""Build an independent Shadow consumer and run the single distributable with JDK 25."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from zipfile import ZipFile

from godot_driver import DEFAULT_DRIVER, add_driver_argument, check_driver
from library_test_platform import (CLASSIFIER, EDITOR, ENGINE, MEDIA_LIBRARIES, SDK_NATIVES,
                                   WINDOWS, library, module_paths, system_path)


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/library"


def execute(args, log, **kwargs):
    with log.open("wb") as stream:
        subprocess.run(list(map(str, args)), stdout=stream, stderr=subprocess.STDOUT,
                       check=True, timeout=300, **kwargs)


def export_scene(work):
    project = work / "scene source"
    shutil.copytree(FIXTURES / "project", project)
    shutil.copyfile(FIXTURES / "interaction.gd", project / "interaction.gd")
    sample = project / "sample.tscn"
    text = sample.read_text().replace('[node name="Sample" type="Node2D"]',
            '[ext_resource type="Script" path="res://interaction.gd" id="1"]\n\n'
            '[node name="Sample" type="Node2D"]\nscript = ExtResource("1")')
    sample.write_text(text)
    # This main scene must never run when a GodotView resource pack is mounted.
    (project / "main.gd").write_text('extends Node\nfunc _ready():\n\tget_tree().quit(19)\n')
    (project / "main.tscn").write_text('[gd_scene format=3]\n'
            '[ext_resource type="Script" path="res://main.gd" id="1"]\n'
            '[node name="Main" type="Node"]\nscript = ExtResource("1")\n')
    pack = work / "resources.pck"
    execute([EDITOR, "--headless", "--path", project, "--editor", "--import"], work / "import.log")
    execute([EDITOR, "--headless", "--path", project, "--export-pack", "JavaFX resources", pack], work / "pack.log")
    return pack


def build(work, runtime, name, pack=None):
    project = work / "tests/library/shadow"
    version = (runtime / "version.txt").read_text().strip()
    args = [ROOT / "jfx" / ("gradlew.bat" if WINDOWS else "gradlew"), "-p", project, "shadowJar", "--no-daemon", "--refresh-dependencies",
            f"-Prepository={runtime / 'repository'}", f"-PjavafxVersion={version}", f"-Pplatform={CLASSIFIER}"]
    if pack:
        args.append(f"-PscenePack={pack}")
    if name == "media":
        args.append("-PwithMedia=true")
    execute(args, work / (name + "-gradle.log"), env=os.environ | {"GRADLE_USER_HOME": str(ROOT / ".gradle-cache")})
    run_dir = work / name
    run_dir.mkdir()
    jar = run_dir / "app.jar"
    shutil.copyfile(next((project / "build/libs").glob("*-all.jar")), jar)
    with ZipFile(jar) as archive:
        names = set(archive.namelist())
        required = {library("godot"), library("javafx_font"), "META-INF/godot-jfx/natives.id"}
        if name == "media":
            required.update(MEDIA_LIBRARIES)
        elif library("jfxmedia") in names:
            raise AssertionError(f"Controls-only build unexpectedly includes Media: {jar}")
        if not required <= names or any(n.endswith((".jar", "project.godot", "project.pck")) for n in names):
            raise AssertionError(f"Invalid flat jar: {jar}")
        for filename in required - {"META-INF/godot-jfx/natives.id"}:
            source = ENGINE if filename == library("godot") else SDK_NATIVES / filename
            if hashlib.sha256(archive.read(filename)).digest() != hashlib.sha256(source.read_bytes()).digest():
                raise AssertionError(f"{jar} contains a different build of {filename}")
        packs = {n for n in names if n.endswith(".pck")}
        if packs != ({"META-INF/godot-jfx/scenes.pck"} if pack else set()):
            raise AssertionError(f"Unexpected resource packs: {packs}")
    return jar


def launch(work, jar, name, args, markers, extra_env=None, expected_error=None, native_cache=None, driver=None):
    # The application receives no JFX flags, extra class path or runtime directory.
    jdk = Path(os.environ["JAVA_HOME"])
    env = {k: v for k, v in os.environ.items() if not k.startswith("GODOT_")
           and k not in ("JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "CLASSPATH")}
    env["PATH"] = system_path(jdk)
    log = work / (name + ".log")
    loaded = set()
    jvm_options = ["-Dglass.platform=Mac", f"-Djavafx.cachedir={native_cache}"] if native_cache else []
    if driver:
        jvm_options.append(f"-Djavafx.godot.driver={driver}")
    with log.open("wb") as stream, subprocess.Popen([jdk / "bin/java", *jvm_options, "-jar", jar.name, *args],
            cwd=jar.parent, env=env | (extra_env or {}), stdout=stream, stderr=subprocess.STDOUT) as proc:
        deadline = time.monotonic() + 55
        while proc.poll() is None:
            loaded.update(module_paths(proc))
            if time.monotonic() >= deadline:
                proc.kill()
                raise TimeoutError(f"{name} timed out, see {log}")
            time.sleep(.05)
    output = log.read_text(encoding="utf-8", errors="replace")
    if not native_cache:
        check_driver(output, driver, log)
    if expected_error:
        if proc.returncode == 0 or expected_error not in output or "SHADOW_STAGE_PASS" in output:
            raise AssertionError(f"{name}: expected startup failure, see {log}")
        print(f"PASS {name}", flush=True)
        return
    if proc.returncode or any(x not in output for x in [f"APPLICATION_PID={proc.pid}", *markers]) or re.search(
            r"(?m)^(ERROR:|SHADER ERROR:|SCRIPT ERROR:|Exception in thread)", output):
        raise AssertionError(f"{name} failed, see {log}")
    required = {library("godot")}
    if native_cache:
        if any(path.name == library("godot") for path in loaded):
            raise AssertionError(f"{name}: native Mac Glass loaded the Godot engine")
        required = {library("glass"), *MEDIA_LIBRARIES}
    elif name == "media":
        required.update(MEDIA_LIBRARIES)
    else:
        required.add(library("javafx_font"))
    with ZipFile(jar) as archive:
        build_id = archive.read("META-INF/godot-jfx/natives.id").decode("ascii")
        for filename in required:
            paths = [path for path in loaded if path.name.lower() == filename]
            if len(paths) != 1:
                raise AssertionError(f"{name}: expected one mapped {filename}, saw {paths}")
            cached = paths[0].parent == native_cache if native_cache else build_id in paths[0].parts
            if not cached:
                raise AssertionError(f"{name}: expected {filename} in the build's native cache, got {paths}")
            if hashlib.sha256(paths[0].read_bytes()).digest() != hashlib.sha256(archive.read(filename)).digest():
                raise AssertionError(f"{name}: loaded {filename} differs from JAR resource")
    (work / (name + "-modules.json")).write_text(json.dumps(sorted(map(str, loaded)), indent=2))
    print(f"PASS {name}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_driver_argument(parser)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    if args.driver is None:
        args.driver = DEFAULT_DRIVER
    work = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="JavaFX Shadow ")).resolve()
    work.mkdir(parents=True, exist_ok=True)
    print(f"Evidence: {work}", flush=True)
    project = work / "tests/library/shadow"
    shutil.copytree(FIXTURES / "shadow", project, ignore=shutil.ignore_patterns(".gradle", "build"))
    shutil.copyfile(FIXTURES / "DirectApplication.java", project.parent / "DirectApplication.java")
    reference = work / "tests/reference"
    reference.mkdir()
    shutil.copyfile(ROOT / "tests/reference/MediaVideoProbe.java", reference / "MediaVideoProbe.java")
    runtime = args.runtime.resolve()
    jar = build(work, runtime, "stage")
    launch(work, jar, "plain-stage", [], ["SHADOW_STAGE_PASS"], driver=args.driver)
    if set(jar.parent.iterdir()) != {jar}:
        raise AssertionError("Projectless startup wrote files beside the application JAR")
    (jar.parent / "project.godot").write_text('config_version=5\n[application]\nrun/main_scene="res://absent.tscn"\n')
    launch(work, jar, "foreign-project", [], ["SHADOW_STAGE_PASS"], driver=args.driver)
    video = ROOT / subprocess.check_output(
        [sys.executable, ROOT / "scripts/setup-env.py", "--sample-path", "oracle"], text=True).strip()
    jar = build(work, runtime, "media")
    launch(work, jar, "media", [], ["MEDIA_VIDEO_CONTROLS_PASS", "MEDIA_VIDEO_PROBE_PASS"], {
        "GODOT_JFX_MEDIA_FILE": str(video),
        "GODOT_JFX_MEDIA_CAPTURE": str(work / "media.png")}, driver=args.driver)
    if not WINDOWS:
        # Native Glass uses OpenJFX's ordinary library cache. Exercise its
        # first extraction, reuse and two JVMs extracting into one empty cache.
        def native_media(case, cache):
            launch(work, jar, case, [], ["MEDIA_VIDEO_CONTROLS_PASS", "MEDIA_VIDEO_PROBE_PASS"], {
                "GODOT_JFX_MEDIA_FILE": str(video),
                "GODOT_JFX_MEDIA_CAPTURE": str(work / (case + ".png"))}, native_cache=work / cache)

        native_media("native-cold", "native-cache")
        native_media("native-warm", "native-cache")
        with ThreadPoolExecutor(max_workers=2) as pool:
            checks = [pool.submit(native_media, f"native-concurrent-{i}", "shared-cache") for i in (1, 2)]
            for check in checks:
                check.result()
    jar = build(work, runtime, "scenes", export_scene(work))
    launch(work, jar, "bundled-view", ["view"], ["LIBRARY_VIEW_STAGE_PASS", "APPLICATION_INPUT_PASS", "APPLICATION_STOP"],
           {"GODOT_LIBRARY_CAPTURE": str(work / "view.png")}, driver=args.driver)
    invalid = work / "invalid.pck"
    invalid.write_bytes(b"Invalid resource pack")
    jar = build(work, runtime, "invalid", invalid)
    launch(work, jar, "invalid-bundled-pack", [], [], expected_error="resources: could not mount bundled", driver=args.driver)


if __name__ == "__main__":
    main()
