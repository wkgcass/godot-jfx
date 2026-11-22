#!/usr/bin/env python3
"""Install and resolve development-test JARs in this checkout's .m2/repository."""
import argparse
import filecmp
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from maven_coordinates import GROUP_PATH, artifact_id, release_version


ROOT = Path(__file__).resolve().parents[1]
MAVEN_REPOSITORY = ROOT / ".m2" / "repository"
MODULES = ("base", "graphics", "controls", "fxml", "media", "swing")
PLATFORM_MODULES = ("graphics", "media")


def classifier():
    arch = platform.machine().lower()
    if sys.platform == "win32" and arch in ("amd64", "x86_64"):
        return "win"
    if sys.platform == "darwin" and arch == "arm64":
        return "mac-aarch64"
    raise ValueError(f"Unsupported JavaFX platform: {sys.platform} {arch}")


def module_jars(version, target):
    for module in MODULES:
        artifact = artifact_id(module)
        directory = GROUP_PATH / artifact / version
        prefix = f"{artifact}-{version}"
        jar = directory / f"{prefix}.jar"
        runtime_jar = directory / f"{prefix}-{target}.jar" if module in PLATFORM_MODULES else jar
        yield jar, runtime_jar


def test_jars():
    jars = []
    for _, relative in module_jars(release_version(), classifier()):
        jar = (MAVEN_REPOSITORY / relative).resolve()
        if not jar.is_relative_to(MAVEN_REPOSITORY) or not jar.is_file():
            raise FileNotFoundError(f"Expected test dependency at {MAVEN_REPOSITORY / relative}. Run scripts/maven_local.py install.")
        jars.append(jar)
    return jars


def install(runtime, maven):
    executable = Path(shutil.which(maven) or maven).resolve(strict=True)
    version = release_version()
    target = classifier()
    env = os.environ.copy()
    if target == "mac-aarch64" and not env.get("JAVA_HOME"):
        env["JAVA_HOME"] = str(ROOT / ".tools/jdk-25/Contents/Home")
    if runtime is None:
        runtime = ROOT / "artifacts/godot-library"
        if target == "win":
            subprocess.run(["pwsh.exe", "-NoProfile", "-File", ROOT / "scripts/stage-godot-library.ps1",
                            "-Destination", runtime], cwd=ROOT, env=env, check=True)
        else:
            subprocess.run(["sh", ROOT / "scripts/stage-godot-library.sh"], cwd=ROOT, env=env, check=True)
    else:
        runtime = runtime.resolve()
    if (runtime / "version.txt").read_text().strip() != version:
        raise ValueError(f"Stage {version} before installing from {runtime}")

    artifacts = []
    repository = runtime / "repository"
    for jar, runtime_jar in module_jars(version, target):
        pom = (repository / jar.with_suffix(".pom")).resolve(strict=True)
        artifacts.append(((repository / jar).resolve(strict=True), pom, ""))
        if runtime_jar != jar:
            artifacts.append(((repository / runtime_jar).resolve(strict=True), pom, target))

    # Maven installs the original POM and maintains its own local repository metadata.
    # Resolve once per installation so subsequent test processes can run offline.
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        mvn = [executable, "-B", "--no-transfer-progress", f"-Dmaven.repo.local={MAVEN_REPOSITORY}"]
        for jar, pom, suffix in artifacts:
            args = [*mvn, "org.apache.maven.plugins:maven-install-plugin:3.1.4:install-file",
                    f"-Dfile={jar}", f"-DpomFile={pom}"]
            if suffix:
                args.append(f"-Dclassifier={suffix}")
            subprocess.run(args, cwd=work, env=env, check=True)

        output = work / "classpath.txt"
        subprocess.run([*mvn, "-f", ROOT / "tests/library/pom.xml",
                        "org.apache.maven.plugins:maven-dependency-plugin:3.8.1:build-classpath",
                        f"-Dgodot.version={version}", f"-Dgodot.platform={target}",
                        f"-Dmdep.outputFile={output}"], cwd=work, env=env, check=True)
        paths = [Path(p).resolve(strict=True) for p in output.read_text(encoding="utf-8").strip().split(os.pathsep)]
        if not all(p.is_relative_to(MAVEN_REPOSITORY) for p in paths):
            raise ValueError(f"Maven resolved dependencies outside {MAVEN_REPOSITORY}")
        resolved = {p.name: p for p in paths}
        for jar, _, _ in artifacts:
            if jar.name not in resolved or not filecmp.cmp(jar, resolved[jar.name], shallow=False):
                raise ValueError(f"Maven did not resolve the staged build of {jar.name}")
    print(f"Installed {version} ({target}) in {MAVEN_REPOSITORY}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    installer = commands.add_parser("install", help="Package the current platform build and install it with Maven")
    installer.add_argument("--runtime", type=Path, help="Install an existing staging directory without repackaging")
    installer.add_argument("--maven", default=shutil.which("mvn") or str(
        ROOT / ".tools/apache-maven-3.9.9/bin" / ("mvn.cmd" if os.name == "nt" else "mvn")))
    paths = commands.add_parser("module-path", help="Print the resolved platform module path")
    paths.add_argument("--json", action="store_true", help="Return an ASCII JSON string for PowerShell")
    args = parser.parse_args()
    try:
        if args.command == "install":
            install(args.runtime, args.maven)
        else:
            value = os.pathsep.join(map(str, test_jars()))
            print(json.dumps(value) if args.json else value)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")
