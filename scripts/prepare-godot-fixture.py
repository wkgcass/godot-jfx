#!/usr/bin/env python3
"""Import the scene fixtures in a disposable project at the same directory depth."""
import hashlib
import os
import sys
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def prepare():
    source = ROOT / "tests/godot"
    editor = ROOT / "godot/bin" / ("godot.windows.editor.x86_64.console.exe" if os.name == "nt" else "godot.macos.editor.arm64")
    files = sorted(p for p in source.rglob("*") if p.is_file()
                   and not {".godot", "artifacts"}.intersection(p.relative_to(source).parts)
                   and not p.name.endswith(".gd.uid"))
    digest = hashlib.sha256(str(editor.stat().st_mtime_ns).encode())
    for path in files:
        digest.update(path.relative_to(source).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    artifacts = ROOT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    project = artifacts / ("scene-fixtures-" + digest.hexdigest()[:20])
    if not project.is_dir():
        with tempfile.TemporaryDirectory(dir=artifacts) as temp:
            staged = Path(temp) / "project"
            for path in files:
                target = staged / path.relative_to(source)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
            logs = ROOT / "agentdir/logs"
            logs.mkdir(parents=True, exist_ok=True)
            import_log = logs / f"{project.name}-{Path(temp).name}-import.log"
            with import_log.open("wb") as log:
                result = subprocess.run([editor, "--headless", "--editor", "--path", staged, "--import"],
                                        stdout=log, stderr=subprocess.STDOUT, timeout=120)
            if result.returncode or not (staged / ".godot/global_script_class_cache.cfg").is_file():
                raise RuntimeError(f"Fixture import failed ({import_log}): {import_log.read_text('utf-8', errors='replace')}")
            try:
                staged.rename(project)
            except FileExistsError:
                pass  # A concurrent launcher published the identical import.
    return project


if __name__ == "__main__":
    print(prepare().name)
