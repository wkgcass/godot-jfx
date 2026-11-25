#!/usr/bin/env python3
"""Clean native builds, local distribution outputs and generated test projects."""
import argparse
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys

from jdk_home import add_jdk_argument, configure_jdk


ROOT = Path(__file__).resolve().parents[1]
TARGETS = ("godot-editor", "godot-library", "jfx", "packages", "test-projects")
PACKAGES = ("artifacts/vfx", "artifacts/godot-library", "tests/library/shadow/build")
PACKAGE_GRADLE_DIRS = ("scripts/vfx-build/.gradle", "tests/library/shadow/.gradle")
GODOT_STATE_FILES = (".scons_env.json", ".scons_node_count", ".sconsign5.dblite", "platform/windows/msvc_capture.log")


def native_command(target):
    if sys.platform == "win32":
        # Use the same SDK locations, custom modules and target options as the build.
        return ["pwsh.exe", "-NoProfile", "-File", str(ROOT / "scripts/build-windows.ps1"),
                "-Target", target, "-Clean"]
    if sys.platform == "linux" and platform.machine() == "x86_64":
        return [str(ROOT / "scripts/build-linux.sh"), "--target", target, "--clean"]
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise ValueError("Native clean targets require Windows x64, macOS arm64 or Linux x64.")
    if target == "jfx":
        return [str(ROOT / "jfx/gradlew"), "-p", str(ROOT / "jfx"), "cleanAll", "--no-problems-report", "--no-daemon"]
    command = [str(ROOT / ".tools/pyenv/bin/scons"), "-C", str(ROOT / "godot"), "--clean",
               "platform=macos", "arch=arm64", "vulkan=no", "accesskit=no", "angle=no"]
    if target == "godot-editor":
        return [*command, "target=editor"]
    return [*command, "target=template_release", "library_type=shared_library", "extra_suffix=library",
            "disable_path_overrides=no", f"custom_modules={ROOT / 'native/godot_modules'}"]


def check_output_path(path):
    if path.resolve() != path:
        raise ValueError(f"Refusing to clean a redirected output path: {path}")


def remove_directory(path, dry_run):
    check_output_path(path)
    print(f"Remove directory: {path}", flush=True)
    if not dry_run and path.exists():
        shutil.rmtree(path)


def remove_file(path, dry_run):
    check_output_path(path)
    print(f"Remove file: {path}", flush=True)
    if not dry_run:
        path.unlink(missing_ok=True)


def run_command(label, command, cwd, env, dry_run):
    display = subprocess.list2cmdline(command) if os.name == "nt" else shlex.join(command)
    print(f"{label}: {display}", flush=True)
    if not dry_run:
        subprocess.run(command, cwd=cwd, env=env, check=True)


def clean(target, dry_run, jdk=None):
    targets = TARGETS if target == "all" else (target,)
    env = os.environ.copy()
    uses_gradle = "jfx" in targets or (target == "packages" and any((ROOT / p).exists() for p in PACKAGE_GRADLE_DIRS))
    if uses_gradle or "godot-library" in targets:
        env["JAVA_HOME"] = str(configure_jdk(jdk))
        if sys.platform in ("darwin", "linux") and "jfx" in targets:
            env["ANT_HOME"] = env.get("ANT_HOME") or str(ROOT / ".tools/apache-ant-1.10.15")
            ant = Path(env["ANT_HOME"]) / "bin/ant"
            if not dry_run and not os.access(ant, os.X_OK):
                raise ValueError(f"Missing executable {ant}. Run scripts/setup-env.py or set ANT_HOME before cleaning.")

    if uses_gradle:
        env["GRADLE_USER_HOME"] = str(ROOT / ".gradle-cache")
        wrapper = ROOT / "jfx" / ("gradlew.bat" if os.name == "nt" else "gradlew")
        run_command("gradle stop", [str(wrapper), "--stop"], ROOT / "jfx", env, dry_run)

    for item in targets:
        if item in ("packages", "test-projects"):
            if item == "packages":
                paths = [ROOT / relative for relative in (*PACKAGES, *PACKAGE_GRADLE_DIRS)]
            else:
                artifacts = ROOT / "artifacts"
                paths = sorted(path for pattern in ("runtime-*", "scene-fixtures-*")
                               for path in artifacts.glob(pattern) if path.is_dir())
                paths.extend((artifacts / "reference", artifacts / "native-tests", artifacts / "vfx-gpu-profile", artifacts / "pulse-stop-patch",
                              artifacts / "texture-cancellation-patch", ROOT / "tests/godot/.godot"))
                if sys.platform == "linux":
                    paths.append(artifacts / "linux-clipboard")
                wayland_cache = ROOT / "tests/wayland/__pycache__"
                if wayland_cache.is_dir():
                    paths.append(wayland_cache)
            for path in paths:
                remove_directory(path, dry_run)
        else:
            command = native_command(item)
            cwd = ROOT
            if item == "jfx" and sys.platform == "darwin":
                cwd = ROOT / "jfx"
            run_command(item, command, cwd, env, dry_run)
            if item == "jfx":
                for relative in ("jfx/.gradle", "jfx/buildSrc/.gradle"):
                    remove_directory(ROOT / relative, dry_run)
            if target == "all" and item == "godot-library":
                # SCons can write its signature database as it exits.
                remove_directory(ROOT / "godot/bin", dry_run)
                for relative in GODOT_STATE_FILES:
                    remove_file(ROOT / "godot" / relative, dry_run)

    if target == "all":
        for relative in ("godot", "scripts", "native"):
            source = ROOT / relative
            for cache in sorted(source.rglob("__pycache__")):
                if cache.is_dir() and ".git" not in cache.relative_to(source).parts:
                    remove_directory(cache, dry_run)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    add_jdk_argument(parser)
    parser.add_argument("--target", choices=("all", *TARGETS), default="all")
    parser.add_argument("--dry-run", action="store_true", help="Print commands and paths without running them")
    args = parser.parse_args()
    try:
        clean(args.target, args.dry_run, args.jdk)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Clean failed: {error}\n")
