"""Build an independent Shadow consumer and run the single distributable with JDK 25."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from zipfile import ZipFile

from windows_loaded_modules import module_paths


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
    editor = ROOT / "godot/bin/godot.windows.editor.x86_64.console.exe"
    pack = work / "resources.pck"
    execute([editor, "--headless", "--path", project, "--editor", "--import"], work / "import.log")
    execute([editor, "--headless", "--path", project, "--export-pack", "JavaFX resources", pack], work / "pack.log")
    return pack


def build(work, runtime, name, pack=None):
    project = work / "tests/library/shadow"
    version = (runtime / "version.txt").read_text().strip()
    args = [ROOT / "jfx/gradlew.bat", "-p", project, "shadowJar", "--no-daemon", "--refresh-dependencies",
            f"-Prepository={runtime / 'repository'}", f"-PjavafxVersion={version}"]
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
        required = {"godot.dll", "javafx_font.dll", "META-INF/godot-jfx/natives.id"}
        if name == "media":
            required.update(("jfxmedia.dll", "fxplugins.dll"))
        elif "jfxmedia.dll" in names:
            raise AssertionError(f"Controls-only build unexpectedly includes Media: {jar}")
        if not required <= names or any(n.endswith((".jar", "project.godot", "project.pck")) for n in names):
            raise AssertionError(f"Invalid flat jar: {jar}")
        for dll in (entry for entry in required if entry.endswith(".dll")):
            if hashlib.sha256(archive.read(dll)).digest() != hashlib.sha256((runtime / "bin" / dll).read_bytes()).digest():
                raise AssertionError(f"{jar} contains a different build of {dll}")
        packs = {n for n in names if n.endswith(".pck")}
        if packs != ({"META-INF/godot-jfx/scenes.pck"} if pack else set()):
            raise AssertionError(f"Unexpected resource packs: {packs}")
    return jar


def launch(work, jar, name, args, markers, extra_env=None, expected_error=None):
    # The application receives no JFX flags, extra class path or runtime directory.
    jdk = Path(os.environ["JAVA_HOME"])
    env = {k: v for k, v in os.environ.items() if not k.startswith("GODOT_")
           and k not in ("JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "CLASSPATH")}
    env["PATH"] = os.pathsep.join(map(str, [jdk / "bin", Path(os.environ["SystemRoot"]) / "System32"]))
    log = work / (name + ".log")
    loaded = set()
    with log.open("wb") as stream, subprocess.Popen([jdk / "bin/java", "-jar", jar.name, *args],
            cwd=jar.parent, env=env | (extra_env or {}), stdout=stream, stderr=subprocess.STDOUT) as proc:
        deadline = time.monotonic() + 55
        while proc.poll() is None:
            loaded.update(module_paths(proc))
            if time.monotonic() >= deadline:
                proc.kill()
                raise TimeoutError(f"{name} timed out, see {log}")
            time.sleep(.05)
    output = log.read_text(encoding="utf-8", errors="replace")
    if expected_error:
        if proc.returncode == 0 or expected_error not in output or "SHADOW_STAGE_PASS" in output:
            raise AssertionError(f"{name}: expected startup failure, see {log}")
        print(f"PASS {name}", flush=True)
        return
    if proc.returncode or any(x not in output for x in [f"APPLICATION_PID={proc.pid}", *markers]) or re.search(
            r"(?m)^(ERROR:|SHADER ERROR:|SCRIPT ERROR:|Exception in thread)", output):
        raise AssertionError(f"{name} failed, see {log}")
    required = {"godot.dll"}
    if name == "media":
        required.update(("jfxmedia.dll", "glib-lite.dll", "gstreamer-lite.dll", "fxplugins.dll"))
    else:
        required.add("javafx_font.dll")
    with ZipFile(jar) as archive:
        build_id = archive.read("META-INF/godot-jfx/natives.id").decode("ascii")
        for dll in required:
            paths = [path for path in loaded if path.name.lower() == dll]
            if len(paths) != 1 or build_id not in paths[0].parts:
                raise AssertionError(f"{name}: expected {dll} in the build's native cache, got {paths}")
            if hashlib.sha256(paths[0].read_bytes()).digest() != hashlib.sha256(archive.read(dll)).digest():
                raise AssertionError(f"{name}: loaded {dll} differs from JAR resource")
    (work / (name + "-modules.json")).write_text(json.dumps(sorted(map(str, loaded)), indent=2))
    print(f"PASS {name}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    work = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="JavaFX Shadow "))
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
    launch(work, jar, "plain-stage", [], ["SHADOW_STAGE_PASS"])
    if set(jar.parent.iterdir()) != {jar}:
        raise AssertionError("Projectless startup wrote files beside the application JAR")
    (jar.parent / "project.godot").write_text('config_version=5\n[application]\nrun/main_scene="res://absent.tscn"\n')
    launch(work, jar, "foreign-project", [], ["SHADOW_STAGE_PASS"])
    jar = build(work, runtime, "media")
    launch(work, jar, "media", [], ["MEDIA_VIDEO_CONTROLS_PASS", "MEDIA_VIDEO_PROBE_PASS"], {
        "GODOT_JFX_MEDIA_FILE": str(ROOT / "artifacts/reference/media-oracle-sample.mp4"),
        "GODOT_JFX_MEDIA_CAPTURE": str(work / "media.png")})
    jar = build(work, runtime, "scenes", export_scene(work))
    launch(work, jar, "bundled-view", ["view"], ["LIBRARY_VIEW_STAGE_PASS", "APPLICATION_INPUT_PASS", "APPLICATION_STOP"],
           {"GODOT_LIBRARY_CAPTURE": str(work / "view.png")})
    invalid = work / "invalid.pck"
    invalid.write_bytes(b"Invalid resource pack")
    jar = build(work, runtime, "invalid", invalid)
    launch(work, jar, "invalid-bundled-pack", [], [], expected_error="resources: could not mount bundled")


if __name__ == "__main__":
    main()
