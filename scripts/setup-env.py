#!/usr/bin/env python3
"""Prepare source submodules, local build tools and media test samples for Windows x64 and macOS arm64."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
from urllib.request import urlopen
from zipfile import BadZipFile, ZipFile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools"
SAMPLES = {
    "oracle": ("media-oracle-sample.mp4", "https://download.oracle.com/otndocs/products/javafx/oow2010-2.mp4",
               "a6b3928991253a7828052612c8b6cec25f5de3648a361f92e5c2ece9a37d7d34"),
    "lk": ("Lk.mp4", "https://raw.githubusercontent.com/wkgcass/hotta-pc-assistant/refs/heads/dev/"
           "src/main/resources/video/Lk.mp4", "53b1a2aa9bcdfc6fa2e8ab93d2794829a93b0c8676e6e500c0995e44c6908059"),
}


def prepare_submodules():
    missing = [name for name in ("godot", "jfx", "vfx") if not (ROOT / name / ".git").exists()]
    if missing:
        subprocess.run(["git", "submodule", "update", "--init", "--recursive", "--", *missing],
                       cwd=ROOT, check=True)


def media_sample(name, *, download):
    filename, url, digest = SAMPLES[name]
    sample = ROOT / "agentdir/media" / filename
    if sample.is_file() and hashlib.sha256(sample.read_bytes()).hexdigest() == digest:
        if download:
            print(f"Reusing {sample}")
        return sample
    if not download:
        raise ValueError(f"Run scripts/setup-env.py to prepare {filename}")

    sample.parent.mkdir(parents=True, exist_ok=True)
    legacy = ROOT / "artifacts/reference" / filename
    try:
        if hashlib.sha256(legacy.read_bytes()).hexdigest() == digest:
            legacy.replace(sample)
            print(f"Moved {filename} to {sample.parent}")
            return sample
    except FileNotFoundError:
        # Another setup may have moved the legacy sample while we were checking it.
        if sample.is_file() and hashlib.sha256(sample.read_bytes()).hexdigest() == digest:
            return sample
    print(f"Downloading {sample.name}", flush=True)
    with TemporaryDirectory(dir=sample.parent) as temp:
        staged = Path(temp) / sample.name
        with urlopen(url, timeout=90) as source, staged.open("wb") as dest:
            shutil.copyfileobj(source, dest)
        if hashlib.sha256(staged.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Checksum mismatch for {url}")
        staged.replace(sample)
    return sample


def install_archive(destination, url, digest, files, *, archive_root="", version_marker=None):
    """Verify the archive before exposing its contents at the path used by the build."""
    def ready(folder):
        if not all((folder / name).is_file() for name in files):
            return False
        if os.name != "nt" and not os.access(folder / files[0], os.X_OK):
            return False
        if version_marker:
            name, text = version_marker
            marker = folder / name
            return marker.is_file() and text in marker.read_text(encoding="utf-8")
        return True

    if ready(destination):
        print(f"Reusing {destination}")
        return
    if destination.exists():
        raise ValueError(f"Incomplete or incompatible installation at {destination}; move it aside and rerun setup")

    print(f"Installing {destination.name}", flush=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=destination.parent) as temp:
        staging = Path(temp)
        name = url.rsplit("/", 1)[1]
        archive = TOOLS / name
        if not archive.is_file():
            archive = staging / name
            with urlopen(url, timeout=90) as source, archive.open("wb") as dest:
                shutil.copyfileobj(source, dest)
        checksum = hashlib.sha512() if len(digest) == 128 else hashlib.sha256()
        with archive.open("rb") as src:
            for chunk in iter(lambda: src.read(1024 * 1024), b""):
                checksum.update(chunk)
        if checksum.hexdigest() != digest:
            raise ValueError(f"Checksum mismatch for {archive}")
        unpacked = staging / "unpacked"
        if name.endswith(".tar.gz"):
            unpacked.mkdir()
            subprocess.run(["tar", "-xzf", archive, "-C", unpacked], check=True)
        else:
            with ZipFile(archive) as distribution:
                distribution.extractall(unpacked)
                if os.name != "nt":
                    for entry in distribution.infolist():
                        if not entry.is_dir() and (entry.external_attr >> 16) & 0o111:
                            (unpacked / entry.filename).chmod(0o755)
        source = unpacked / archive_root
        if not ready(source):
            raise ValueError(f"{name} does not contain the expected files")
        try:
            source.rename(destination)
        except OSError:
            if not ready(destination):  # A concurrent setup may have finished first.
                raise


def install_java_tools(windows):
    ant = "apache-ant-1.10.15"
    install_archive(TOOLS / ant, f"https://archive.apache.org/dist/ant/binaries/{ant}-bin.zip",
                    "1de7facbc9874fa4e5a2f045d5c659f64e0b89318c1dbc8acc6aae4595c4ffaf"
                    "90a7b1ffb57f958dd08d6e086d3fff07aa90e50c77342a0aa5c9b4c36bff03a9",
                    ["bin/ant.bat" if windows else "bin/ant", "lib/ant.jar", "lib/ant-launcher.jar"],
                    archive_root=ant)
    maven = "apache-maven-3.9.9"
    install_archive(TOOLS / maven,
                    f"https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/{maven}-bin.zip",
                    "8beac8d11ef208f1e2a8df0682b9448a9a363d2ad13ca74af43705549e72e74c"
                    "9378823bf689287801cbbfc2f6ea9596201d19ccacfdfb682ee8a2ff4c4418ba",
                    ["bin/mvn.cmd" if windows else "bin/mvn", "lib/maven-core-3.9.9.jar",
                     "boot/plexus-classworlds-2.8.0.jar"], archive_root=maven)


def prepare_venv(windows):
    home = TOOLS / ("python" if windows else "pyenv")
    python = home / ("Scripts/python.exe" if windows else "bin/python3")
    if not python.is_file():
        bootstrap = sys.executable
        if not windows and sys.version_info[:2] != (3, 13):
            bootstrap = shutil.which("python3.13")
            if not bootstrap:
                raise ValueError("Install Python 3.13 to create .tools/pyenv")
        subprocess.run([bootstrap, "-m", "venv", home], check=True)
    # Check the interpreter and installed versions locally before contacting pip's index.
    probe = ("import json,sys; from importlib.metadata import distributions; "
             "print(json.dumps([sys.prefix, sys.version_info[:2], "
             "{d.metadata['Name'].lower(): d.version for d in distributions()}]))")
    prefix, version, installed = json.loads(subprocess.check_output([python, "-I", "-c", probe], text=True))
    if Path(prefix).resolve() != home.resolve() or (not windows and version != [3, 13]):
        raise ValueError(f"Unexpected virtual environment or Python version at {home}")
    requirements = []
    if windows and installed.get("scons") != "4.10.1":
        requirements.append("scons==4.10.1")
    if not windows:
        if not installed.get("scons", "").startswith("4.11."):
            requirements.append("scons==4.11.*")
        requirements.extend(name for name in ("zstandard", "pillow") if name not in installed)
    if requirements:
        subprocess.run([python, "-Im", "pip", "--isolated", "--disable-pip-version-check", "install",
                        "--no-cache-dir", *requirements], check=True)
    else:
        print(f"Reusing Python dependencies in {home}")


def prepare_windows():
    # Install the x64 MSVC packages from Godot's install_d3d12_sdk_windows.py separately.
    deps = TOOLS / "localappdata/Godot/build_deps"
    releases = "https://github.com/godotengine"
    nuget = "https://api.nuget.org/v3-flatcontainer"
    install_archive(deps / "mesa-x86_64-msvc",
                    f"{releases}/godot-nir-static/releases/download/25.3.1-3/godot-nir-static-x86_64-msvc-release.zip",
                    "f7796c97657fab348774906dc938bb46fbfd1e45434244141fc8886e5e4b5530",
                    ["bin/libNIR.windows.x86_64.lib", "godot-mesa/src/compiler/nir/nir.h"],
                    version_marker=("godot-mesa/VERSION.info", "25.3.1"))
    install_archive(deps / "pix",
                    f"{nuget}/winpixeventruntime/1.0.240308001/winpixeventruntime.1.0.240308001.nupkg",
                    "726acc93d6968e2146261a1e415521747d50ad69894c2b42b5d0d4c29fd66ec4",
                    ["Include/WinPixEventRuntime/pix3.h", "bin/x64/WinPixEventRuntime.dll",
                     "bin/x64/WinPixEventRuntime.lib"],
                    version_marker=("WinPixEventRuntime.nuspec", "<version>1.0.240308001</version>"))
    install_archive(deps / "agility_sdk",
                    f"{nuget}/microsoft.direct3d.d3d12/1.618.5/microsoft.direct3d.d3d12.1.618.5.nupkg",
                    "0027fc24f947c48dbded13ada7d280be221eb651644e23a8a476f0f1f0a079dd",
                    ["build/native/bin/x64/D3D12Core.dll", "build/native/bin/x64/d3d12SDKLayers.dll"],
                    version_marker=("Microsoft.Direct3D.D3D12.nuspec", "<version>1.618.5</version>"))
    subprocess.run(["pwsh.exe", "-NoProfile", "-File", ROOT / "scripts/build-makedepend.ps1", "-Reuse"],
                   check=True)


def prepare_macos():
    install_archive(TOOLS / "jdk-25",
                    "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/"
                    "OpenJDK25U-jdk_aarch64_mac_hotspot_25.0.5_8.tar.gz",
                    "36dc14d797aaff6d89aab302cd053fdba6207dfdcf772052fa7b023a94b0e857",
                    ["Contents/Home/bin/java", "Contents/Home/bin/javac", "Contents/Home/include/jni.h"],
                    archive_root="jdk-25.0.5+8", version_marker=("Contents/Home/release", 'JAVA_VERSION="25.'))


def main():
    windows = sys.platform == "win32" and platform.machine().lower() in ("amd64", "x86_64")
    if not windows and (sys.platform != "darwin" or platform.machine() != "arm64"):
        raise ValueError("Run setup on Windows x64 or macOS arm64")
    if windows:
        pwsh = shutil.which("pwsh.exe")
        if not pwsh or subprocess.run([pwsh, "-NoProfile", "-Command",
                                       "if ($PSVersionTable.PSVersion -lt '7.4.1') { exit 1 }"]).returncode:
            raise ValueError("PowerShell 7.4.1 or later is required. Install PowerShell from the Microsoft Store and ensure pwsh is on PATH.")
    prepare_submodules()
    install_java_tools(windows)
    prepare_venv(windows)
    if windows:
        prepare_windows()
    else:
        prepare_macos()
    for name in SAMPLES:
        media_sample(name, download=True)
    print(f"Build tools ready in {TOOLS}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-path", choices=SAMPLES, help="Verify an installed sample and print its repository-relative path")
    args = parser.parse_args()
    try:
        if args.sample_path:
            print(media_sample(args.sample_path, download=False).relative_to(ROOT).as_posix())
        else:
            main()
    except (OSError, ValueError, BadZipFile, subprocess.CalledProcessError) as error:
        sys.exit(f"Environment setup failed: {error}")
