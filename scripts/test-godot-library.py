#!/usr/bin/env python3
"""Run JDK 25 child-process checks for the Java-launched distribution."""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from zipfile import ZipFile

from jdk_home import add_jdk_argument, configure_jdk
from maven_coordinates import CLASSIFIER_HASH_KEYS, artifact_id
import native_prism
from godot_driver import DEFAULT_DRIVER, ENGINE_DRIVERS, add_driver_argument, check_driver
from library_test_platform import CLASSIFIER, EDITOR, MEDIA_LIBRARIES, WINDOWS, LINUX, library, module_paths, system_path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/library"
REFERENCE = ROOT / "tests/reference"
MODULES = "javafx.controls,javafx.fxml,javafx.media,javafx.swing"
EXPORTS = [f"--add-exports={module}/{package}=ALL-UNNAMED" for module, package in [
    ("javafx.graphics", "com.sun.javafx.tk.godot"), ("javafx.graphics", "com.sun.glass.ui"),
    ("javafx.graphics", "com.sun.prism"), ("javafx.graphics", "com.sun.javafx.iio"),
    ("javafx.graphics", "com.sun.javafx.iio.jpeg"), ("javafx.media", "com.sun.media.jfxmedia"),
]]


def command(args, log, **kwargs):
    with log.open("wb") as stream:
        result = subprocess.run([str(arg) for arg in args], stdout=stream, stderr=subprocess.STDOUT,
                                timeout=kwargs.pop("timeout", 180), **kwargs)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}), see {log}")


def sha256(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


class RepositoryHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def resolve(runtime, work, maven):
    version = (runtime / "version.txt").read_text().strip()
    consumer = work / "consumer"
    consumer.mkdir(exist_ok=True)
    shutil.copyfile(FIXTURES / "pom.xml", consumer / "pom.xml")
    # Serve the staged repository on loopback. The consumer's empty local cache
    # and the runtime can be on different drives or inside Unicode directories.
    handler = functools.partial(RepositoryHandler, directory=str(runtime / "repository"))
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            command([maven, "-B", "-U", "-f", consumer / "pom.xml",
                     f"-Dmaven.repo.local={work / 'maven-cache'}",
                     f"-Dgodot.platform={CLASSIFIER}",
                     f"-Dgodot.repository=http://127.0.0.1:{server.server_port}/",
                     f"-Dgodot.version={version}",
                     "org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy-dependencies",
                     f"-DoutputDirectory={consumer / 'modules'}"], work / "maven.log", timeout=300)
        finally:
            server.shutdown()
    inventory = json.loads((runtime / "module-inventory.json").read_text())
    # Maven also resolves the ordinary graphics and media JARs transitively.
    # Select the platform variant of each module for the runtime module path.
    for module in ("graphics", "media"):
        classifier, = (consumer / "modules").glob(f"godot-jfx-{module}-*-{CLASSIFIER}.jar")
        plain = classifier.with_name(classifier.name.replace(f"-{CLASSIFIER}.jar", ".jar"))
        if sha256(plain) != inventory[f"javafx.{module}"]["sha256"]:
            raise AssertionError(f"Unexpected transitive module: {plain}")
        plain.unlink()
    hashes = {jar.name: sha256(jar) for jar in (consumer / "modules").glob("*.jar")}
    expected = {}
    for module in ("base", "controls", "fxml", "graphics", "media", "swing"):
        platform = module in ("graphics", "media")
        suffix = f"-{CLASSIFIER}" if platform else ""
        filename = f"{artifact_id(module)}-{version}{suffix}.jar"
        key = CLASSIFIER_HASH_KEYS[CLASSIFIER] if platform else "sha256"
        expected[filename] = inventory[f"javafx.{module}"][key]
    if hashes != expected:
        mismatches = sorted(name for name in hashes.keys() | expected.keys() if hashes.get(name) != expected.get(name))
        raise AssertionError(f"Resolved jars differ from the staged modules: {mismatches}")
    graphics = next((consumer / "modules").glob("godot-jfx-graphics-*.jar"))
    with ZipFile(graphics) as jar:
        if not any(p.endswith(".gdshader") for p in jar.namelist()):
            raise AssertionError("Missing Godot shaders in Maven graphics jar")
    controls = next((consumer / "modules").glob("godot-jfx-controls-*.jar"))
    with ZipFile(controls) as jar:
        for ext in (".bss", ".css", ".png", ".properties"):
            if not any(p.endswith(ext) for p in jar.namelist()):
                raise AssertionError(f"Missing {ext} in Maven controls jar")
    return hashes


class Suite:
    def __init__(self, work, jdk, hashes):
        self.work, self.jdk, self.hashes = work, jdk, hashes
        self.modules = work / "consumer/modules"
        self.classes = work / "classes"
        self.cwd = work / "separate working directory"
        self.cwd.mkdir(exist_ok=True)
        self.results = []
        self.render_driver = None
        self.failed = []
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith("GODOT_JFX_") and k not in ("JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS")}
        self.env["PATH"] = system_path(jdk)

    def compile(self):
        self.classes.mkdir(exist_ok=True)
        args = [self.jdk / "bin/javac", "--module-path", self.modules, "--add-modules", MODULES,
                "-encoding", "UTF-8", "-d", self.classes]
        # This first compile uses only exported public APIs.
        command([*args, FIXTURES / "DirectApplication.java", FIXTURES / "ApplicationWithMain.java",
                 FIXTURES / "SceneMessageApplication.java"], self.work / "public-compile.log")
        command([self.jdk / "bin/javac", "--module-path", self.modules, "-d", self.work / "example.fx",
                 *sorted((FIXTURES / "modular").rglob("*.java"))], self.work / "modular-compile.log")
        command([*args, *EXPORTS, "-cp", self.classes, FIXTURES / "LibraryLifecycle.java", FIXTURES / "BackendProbe.java",
                 REFERENCE / "EffectsProbe.java", REFERENCE / "NodeShaderProbe.java", REFERENCE / "MediaVideoProbe.java"],
                self.work / "fixtures-compile.log")
        command([self.jdk / "bin/javap", "--module-path", self.modules, "--module", "javafx.graphics", "-public",
                 "javafx.application.GodotRuntime", "javafx.application.GodotRuntime$Options"], self.work / "public-api.log")
        command([self.jdk / "bin/java", "-version"], self.work / "jdk.log")

    def child(self, name, *args, **kwargs):
        try:
            self.check_child(name, *args, **kwargs)
        except (AssertionError, RuntimeError, subprocess.TimeoutExpired) as error:
            self.failed.append(name)
            self.results.append({"case": name, "error": str(error)})
            print(f"FAIL {name}: {error}", flush=True)
        (self.work / "results.json").write_text(json.dumps(self.results, indent=2), encoding="utf-8")

    def check_child(self, name, target, *args, properties=None, expected=(), code=0, loaded=(), env=None,
                    engines=1, expected_loops=None, module_path=None):
        props = {"javafx.cachedir": self.work / "native-cache", "javafx.godot.verbose": "true",
                 **(properties or {})}
        if engines and self.render_driver:
            props.setdefault("javafx.godot.driver", self.render_driver)
        argv = [self.jdk / "bin/java", "--module-path", module_path or self.modules, "--add-modules", MODULES, *EXPORTS,
                "--enable-native-access=javafx.graphics,javafx.media", "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8",
                *(f"-D{k}={v}" for k, v in props.items() if v is not None), "-cp", self.classes, target, *args]
        output = self.work / (name + ".log")
        paths = set()
        snapshots = {}
        capture = (env or {}).get("GODOT_JFX_MEDIA_CAPTURE")
        previous_capture = Path(capture).stat().st_mtime_ns if capture and Path(capture).exists() else None
        start = time.monotonic()
        image_sampled = False
        with output.open("wb") as log, subprocess.Popen([str(x) for x in argv], cwd=self.cwd, stdin=subprocess.PIPE,
                stdout=log, stderr=subprocess.STDOUT, env=self.env | (env or {})) as proc:
            while proc.poll() is None:
                if loaded:
                    current = module_paths(proc)
                    paths.update(current)
                    if name == "early-image" and not image_sampled and b"EARLY_IMAGE_PASS" in output.read_bytes():
                        paths.update(module_paths(proc))
                        proc.stdin.write(b"1")
                        proc.stdin.flush()
                        image_sampled = True
                    if "startup" not in snapshots and any(p.name.lower() == loaded[0] for p in current):
                        snapshots["startup"] = sorted(map(str, current))
                    if capture and "decodedFrame" not in snapshots and Path(capture).exists() and Path(capture).stat().st_mtime_ns != previous_capture:
                        snapshots["decodedFrame"] = sorted(map(str, current))
                if time.monotonic() - start > 80:
                    try:
                        command([self.jdk / "bin/jcmd", str(proc.pid), "Thread.print"], self.work / (name + "-threads.log"), timeout=8)
                    finally:
                        proc.kill()
                        proc.wait()
                    raise RuntimeError(f"{name} timed out, see {output}")
                time.sleep(.05)
        log = output.read_text(encoding="utf-8", errors="replace")
        actual_drivers = []
        if engines:
            actual, _ = check_driver(log, self.render_driver, output)
            actual_drivers.append(ENGINE_DRIVERS[actual])
        count = log.count("GODOT_LIBRARY_INSTANCE_CREATED")
        loops = log.count("GODOT_LIBRARY_LOOP renderer=")
        errors = re.findall(r"(?m)^(?:Exception in thread|.* uncaught:|SCRIPT ERROR:|SHADER ERROR:|ERROR:|FATAL ERROR).*", log)
        if (proc.returncode != code or count != engines or loops != (engines if expected_loops is None else expected_loops)
                or any(s not in log for s in expected) or (code in (0, 37) and errors)):
            raise AssertionError(f"{name}: exit {proc.returncode}, engines {count}, loops {loops}, see {output}")
        if loaded and engines == 0 and any(path.name.lower() == library("godot") for path in paths):
            raise AssertionError(f"{name}: loaded the engine before Godot startup")
        for filename in loaded:
            actual = {p.resolve() for p in paths if p.name.lower() == filename}
            if len(actual) != 1:
                raise AssertionError(f"{name}: expected one loaded {filename}, saw {actual}")
            wanted, = actual
            if not wanted.is_relative_to(self.work / "native-cache"):
                raise AssertionError(f"{name}: loaded native outside the classifier cache: {wanted}")
            module = "media" if filename in MEDIA_LIBRARIES else "graphics"
            classifier, = self.modules.glob(f"godot-jfx-{module}-*-{CLASSIFIER}.jar")
            with ZipFile(classifier) as jar:
                if sha256(wanted) != hashlib.sha256(jar.read(filename)).hexdigest():
                    raise AssertionError(f"{filename} differs from {classifier}")
            if capture and str(wanted).casefold() not in {p.casefold() for p in snapshots.get("decodedFrame", [])}:
                raise AssertionError(f"{name}: {filename} absent after decoded frame")
        self.results.append({"case": name, "exit": proc.returncode, "seconds": round(time.monotonic()-start, 2),
                             "engines": count, "loops": loops, "command": list(map(str, argv)), "jarHashes": self.hashes,
                             "jdk": (self.work / "jdk.log").read_text().strip(), "moduleSnapshots": snapshots,
                             "renderers": re.findall(r"GODOT_LIBRARY_LOOP renderer=(\w+)", log),
                             "testDrivers": actual_drivers,
                             "loadedModules": sorted(map(str, paths)), "log": str(output)})
        print(f"PASS {name}", flush=True)

    def project(self, name, script=None, parent_script=None, duplicate=False):
        # Two levels below work so the existing pixel observers share reference images.
        project = self.work / "projects" / name
        shutil.copytree(FIXTURES / "project", project, dirs_exist_ok=True)
        scene = '[gd_scene format=3]\n[node name="Main" type="Node"]\n'
        if script:
            shutil.copyfile(FIXTURES / script, project / script)
            if parent_script:
                shutil.copyfile(ROOT / "tests/godot" / parent_script, project / parent_script)
            scene = f'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://{script}" id="1"]\n[node name="Main" type="Node2D"]\nscript = ExtResource("1")\n'
        elif duplicate:
            scene += '[node name="OtherHost" type="JavaFXHost" parent="."]\n'
        (project / "main.tscn").write_text(scene)
        command([EDITOR, "--headless", "--path", project, "--editor", "--import"], project / "import.log")
        return project

    def damaged_classifier(self, directory, module, entry, replacement=None):
        # Keep one module per name and alter only the resource under test.
        directory.mkdir(exist_ok=True, parents=True)
        source, = self.modules.glob(f"godot-jfx-{module}-*-{CLASSIFIER}.jar")
        target = directory / source.name
        with ZipFile(source) as original, ZipFile(target, "w") as damaged:
            if entry not in original.namelist():
                raise AssertionError(f"Missing test input {entry} in {source}")
            for info in original.infolist():
                if info.filename != entry:
                    damaged.writestr(info, original.read(info))
                elif replacement is not None:
                    damaged.writestr(info, replacement)
        return os.pathsep.join(str(target if jar == source else jar) for jar in self.modules.glob("*.jar"))

    def checks(self, group, *, driver=None):
        # Pin even the concurrent initialization probe to the selected driver.
        self.render_driver = driver or DEFAULT_DRIVER
        if group in ("scene-message", "render"):
            project = self.project("scene-message", "scene_message.gd")
            self.child("scene-message", "SceneMessageApplication", properties={"javafx.godot.project": project},
                       expected=["SCENE_MESSAGE_VALIDATION_PASS", "SCENE_MESSAGE_FIFO_PASS count=5", "SCENE_MESSAGE_STOP"])
        if group in ("render", "media"):
            if driver and group == "render":
                self.child("direct-driver", "DirectApplication", expected=["APPLICATION_START", "APPLICATION_STOP"])
            method = "gl_compatibility" if driver == "opengl" else "mobile"
            refs = self.work / "artifacts/reference"
            refs.mkdir(exist_ok=True, parents=True)
        if group == "launch":
            for case in ("init", "concurrent", "race", "explicit", "auto", "startup", "exit"):
                marker = {"init": "HOST_READY", "concurrent": "HOST_READY", "race": "HOST_READY", "explicit": "APPLICATION_STOP",
                          "auto": "APPLICATION_STOP", "startup": "PLATFORM_RESHOW_PASS", "exit": "EXPLICIT_EXIT"}[case]
                self.child(case, "LibraryLifecycle", case, expected=[marker], code=37 if case == "exit" else 0)
            expected = ["APPLICATION_INIT", "APPLICATION_START", "APPLICATION_STOP"]
            direct_props = {"javafx.godot.driver": driver}
            self.child("direct", "DirectApplication", properties=direct_props, expected=expected,
                       loaded=[library("godot"), library("javafx_font")])
            if not WINDOWS and self.render_driver == "metal":
                self.child("direct-metal", "DirectApplication", properties={"javafx.godot.driver": "metal"},
                           expected=["GODOT_LIBRARY_LOOP renderer=mobile",
                                     "APPLICATION_START", "APPLICATION_STOP"])
            self.child("application-main", "ApplicationWithMain", expected=["APPLICATION_MAIN", "APPLICATION_STOP"])
            if driver == "opengl":
                self.child("opengl", "LibraryLifecycle", "opengl", properties={"javafx.godot.driver": None},
                           expected=["GODOT_LIBRARY_LOOP renderer=gl_compatibility",
                           "HOST_READY", "APPLICATION_STOP"])
            self.child("exit-fx", "LibraryLifecycle", "exit-fx", expected=["EXPLICIT_FX_EXIT"], code=37)
            self.child("exit-toolkit", "LibraryLifecycle", "exit-toolkit", expected=["SHUTDOWN_TOOLKIT_PASS"], code=37)
            self.child("modular", "--module-path", os.pathsep.join(map(str, [self.modules, self.work / "example.fx"])),
                       "--module", "example.fx/example.fx.ModularApplication", expected=["APPLICATION_MODULE_PASS example.fx"])
        elif group == "failures":
            self.child("invalid-startup-window", "LibraryLifecycle", "startup",
                       properties={"javafx.godot.startupWindow": "invalid"}, code=1, engines=0,
                       expected=["Invalid javafx.godot.startupWindow: invalid"])
            self.child("invalid-driver", "LibraryLifecycle", "failure", properties={"javafx.godot.driver": "invalid"},
                       expected=["EXPECTED_FAILURE", "Invalid javafx.godot.driver"], code=31, engines=0)
            for case in ("missing", "architecture", "project", "invalid-pack", "attach"):
                runtime = self.work / ("failure-" + case)
                runtime.mkdir(exist_ok=True, parents=True)
                module_path = None
                if case in ("missing", "architecture"):
                    wrong_arch = None
                    if case == "architecture":
                        if WINDOWS:
                            wrong_arch = (Path(os.environ["SystemRoot"]) / "SysWOW64/version.dll").read_bytes()
                        elif LINUX:
                            output = runtime / "wrong-class.so"
                            command(["gcc", "-m32", "-nostdlib", "-shared", "-x", "c", "/dev/null", "-o", output],
                                    runtime / "gcc.log")
                            wrong_arch = output.read_bytes()
                        else:
                            output = runtime / "intel.dylib"
                            command(["clang", "-arch", "x86_64", "-dynamiclib", "-x", "c", "/dev/null", "-o", output],
                                    runtime / "clang.log")
                            wrong_arch = output.read_bytes()
                    module_path = self.damaged_classifier(runtime, "graphics", library("godot"), wrong_arch)
                elif case == "attach":
                    self.pack(self.project("duplicate", duplicate=True), runtime / "project.pck")
                elif case == "invalid-pack":
                    (runtime / "project.pck").write_bytes(b"invalid resource pack")
                marker = {"missing": library("godot"), "architecture": library("godot"), "project": "project:",
                          "invalid-pack": "create:", "attach": "attach:"}[case]
                self.child("failure-" + case, "LibraryLifecycle", "failure", module_path=module_path, properties={
                           "javafx.cachedir": runtime / "cache",
                           "javafx.godot.project": runtime / "project.pck" if case in ("project", "invalid-pack", "attach") else None},
                           expected=["EXPECTED_FAILURE", marker], code=31, engines=int(case == "attach"), expected_loops=0)
            self.child("early-image", "BackendProbe", "image", expected=["EARLY_IMAGE_PASS"], engines=0, loaded=[library("javafx_iio")])
            required_media = library("jfxmedia" if LINUX else "glib-lite")
            damaged = self.damaged_classifier(self.work / "missing-media", "media", required_media)
            self.child("missing-media-dependency", "BackendProbe", "media", module_path=damaged,
                       expected=[required_media, "UnsatisfiedLinkError"], code=1, engines=0)
            backend = native_prism.PRISM
            self.child("native-" + backend, "BackendProbe", backend, properties=native_prism.properties(),
                       env=native_prism.environment(), engines=0, expected=["NATIVE_CONTROL_PASS"],
                       loaded=[library("glassgtk3" if LINUX else "glass"), library("prism_" + backend)])
        elif group == "render":
            project = self.project("独立 工程𠮷", "interaction.gd")
            pack = self.work / "窗口 𠮷.pck"
            self.pack(project, pack)
            self.child("direct-input", "DirectApplication", properties={"test.input": "true", "javafx.godot.project": pack},
                       expected=["APPLICATION_INIT", "APPLICATION_START", "APPLICATION_INPUT_PASS",
                       f"LIBRARY_VIEW_STAGE_PASS renderer={method}", "APPLICATION_STOP"], loaded=[library("godot")],
                       env={"GODOT_LIBRARY_CAPTURE": str(refs / "direct-input.png")})
            for case, source in (("directory", project), ("pck", pack)):
                expected = ["NATIVE_CWD", "APPLICATION_INPUT_PASS", f"LIBRARY_VIEW_STAGE_PASS renderer={method}", "APPLICATION_STOP"]
                self.child("unicode-" + case, "DirectApplication", properties={"javafx.godot.project": source,
                           "test.expectedNativeCwd": self.cwd, "test.input": "true"}, expected=expected,
                           env={"GODOT_LIBRARY_CAPTURE": str(refs / (case + ".png"))})
                # Keep the public Options.project contract separate from the automatic application.
                self.child("options-" + case, "LibraryLifecycle", "explicit", properties={"test.project": source,
                           "test.input": "true"}, expected=expected,
                           env={"GODOT_LIBRARY_CAPTURE": str(refs / ("options-" + case + ".png"))})
            self.child("effects-reference", "EffectsProbe", properties={**native_prism.properties(),
                       "effects.reference": refs / "d3d-effects.png"}, env=native_prism.environment(),
                       expected=["EFFECTS_REFERENCE_PASS"], engines=0)
            for name, probe, parent, marker in [
                ("shader", "NodeShaderProbe", "node_shader_test.gd", "LIBRARY_SHADER_PIXELS_PASS"),
                ("effects", "EffectsProbe", "effects_test.gd", "LIBRARY_EFFECT_PIXELS_PASS"),
            ]:
                project = self.project(name, name + "_observer.gd", parent)
                self.child(name, probe, properties={"javafx.godot.project": project}, expected=[marker])
        if group in ("render", "media"):
            for case, sample in [("media", "oracle"), ("media-lk", "lk")]:
                video = ROOT / subprocess.check_output(
                    [sys.executable, ROOT / "scripts/setup-env.py", "--sample-path", sample], text=True).strip()
                expected = ["MEDIA_VIDEO_RESIZE_PASS", "MEDIA_VIDEO_CONTROLS_PASS", "MEDIA_VIDEO_PROBE_PASS"]
                if sample == "lk":
                    expected.append("MEDIA_VIDEO_READY width=1920 height=1080")
                self.child(case, "MediaVideoProbe", expected=expected,
                           env={"GODOT_JFX_MEDIA_FILE": str(video), "GODOT_JFX_MEDIA_CAPTURE": str(refs / (case + ".png"))},
                           loaded=[library("godot"), *MEDIA_LIBRARIES])

    @staticmethod
    def pack(project, output):
        command([EDITOR, "--headless", "--path", project,
                 "--export-pack", "JavaFX resources", output], project / "pack.log")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_jdk_argument(parser)
    add_driver_argument(parser)
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--maven", default=shutil.which("mvn") or str(ROOT / ".tools/apache-maven-3.9.9/bin" / ("mvn.cmd" if WINDOWS else "mvn")))
    parser.add_argument("--group", choices=["prepare", "launch", "failures", "lifecycle", "render", "media", "scene-message", "all"], default="all")
    args = parser.parse_args()
    configure_jdk(args.jdk)
    runtime = args.runtime.resolve()
    work = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="Godot 验收 ")).resolve()
    work.mkdir(parents=True, exist_ok=True)
    print(f"Evidence: {work}", flush=True)
    hashes = resolve(runtime, work, args.maven)
    suite = Suite(work, Path(os.environ["JAVA_HOME"]), hashes)
    suite.compile()
    groups = {"all": ["launch", "failures", "render"], "lifecycle": ["launch", "failures"]}
    for group in groups.get(args.group, [args.group]):
        suite.checks(group, driver=args.driver)
    if suite.failed:
        raise SystemExit("Failed cases: " + ", ".join(suite.failed))


if __name__ == "__main__":
    main()
