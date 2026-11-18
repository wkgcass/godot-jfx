"""Publish the source SDK as six plain Maven modules and record the shipped content."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


MODULES = {
    "base": [], "graphics": ["base"], "controls": ["graphics", "base"],
    "media": ["graphics", "base"], "fxml": ["graphics", "base"], "swing": ["graphics", "base"],
}
# The Windows SDK filters these compiled classes out of its platform jars.
MAC_PACKAGES = {
    "graphics": ["com/sun/glass/ui/mac", "com/sun/glass/events/mac", "com/sun/prism/mtl",
                 "com/sun/prism/es2", "com/sun/scenario/effect/impl/es2", "com/sun/scenario/effect/impl/hw/mtl"],
    "media": ["com/sun/media/jfxmediaimpl/platform/osx"],
}
GROUP = "org.godotjfx"


def write_pom(path, artifact, version, dependencies):
    pom = ET.Element("project", xmlns="http://maven.apache.org/POM/4.0.0")
    for key, value in [("modelVersion", "4.0.0"), ("groupId", GROUP),
                       ("artifactId", artifact), ("version", version)]:
        ET.SubElement(pom, key).text = value
    deps = ET.SubElement(pom, "dependencies")
    for name in dependencies:
        dep = ET.SubElement(deps, "dependency")
        for key, value in [("groupId", GROUP), ("artifactId", "javafx-" + name), ("version", version)]:
            ET.SubElement(dep, key).text = value
    ET.indent(pom)
    ET.ElementTree(pom).write(path, encoding="utf-8", xml_declaration=True)


def publish(jfx, output, version, jar_tool, classifier):
    modules = output / "modules"
    modules.mkdir(exist_ok=True, parents=True)
    inventory = {}
    windows = classifier == "win"
    media_names = ("fxplugins", "glib-lite", "gstreamer-lite", "jfxmedia", "jfxmedia_avf")
    media_libs = {name + ".dll" if windows else "lib" + name + ".dylib" for name in media_names}
    # Select only this SDK's inputs, even when staging into an existing directory.
    native_dir, pattern, engine = ("bin", "*.dll", "godot.dll") if windows else ("lib", "*.dylib", "libgodot.dylib")
    natives = sorted([output / native_dir / engine, *(jfx / "build/sdk" / native_dir).glob(pattern)])
    build_id = hashlib.sha256()
    for file in natives:
        build_id.update(file.name.encode("ascii") + b"\0" + hashlib.sha256(file.read_bytes()).digest())
    for name, dependencies in MODULES.items():
        module = "javafx." + name
        artifact = "javafx-" + name
        target = modules / (module + ".jar")
        source = jfx / "build" / "sdk" / "lib" / target.name
        compiled = jfx / "modules" / module / "build" / "classes/java/main" / module
        with tempfile.TemporaryDirectory(dir=modules) as work:
            scratch = Path(work)
            packaged = scratch / target.name
            shutil.copyfile(source, packaged)
            with ZipFile(source) as sdk:
                additions = []
                sdk_entries = set(sdk.namelist())
                for package in MAC_PACKAGES.get(name, []):
                    for entry in sorted((compiled / package).rglob("*")):
                        if entry.suffix not in {".class", ".frag", ".vert"}:
                            continue
                        if package == "com/sun/prism/es2" and entry.name.startswith(("IOS", "Monocle", "X11", "EGL")):
                            continue
                        relative = entry.relative_to(compiled).as_posix()
                        if relative in sdk_entries:
                            if sdk.read(relative) != entry.read_bytes():
                                raise ValueError(f"Conflicting SDK and compiled content in {module}: {relative}")
                            continue
                        staged = scratch / "classes" / relative
                        staged.parent.mkdir(exist_ok=True, parents=True)
                        shutil.copyfile(entry, staged)
                        additions.append(relative)
                if additions:
                    subprocess.run([jar_tool, "--update", "--file", packaged, "-C", scratch / "classes", "."], check=True)
            with ZipFile(packaged) as z:
                entries = sorted(z.namelist())
                if entries.count("module-info.class") != 1 or any(
                    entry.lower().endswith((".dll", ".so", ".dylib")) for entry in entries
                ):
                    raise ValueError(f"Invalid modular Java jar: {module}")
                required = {"graphics": ["com/sun/glass/ui/mac/MacRobot.class",
                                         "javafx/application/GodotRuntime.class"],
                            "media": ["com/sun/media/jfxmediaimpl/platform/osx/OSXPlatform.class"]}
                for entry in required.get(name, []):
                    if entry not in entries:
                        raise ValueError(f"{module} is missing {entry}")
                inventory[module] = {"sha256": hashlib.sha256(packaged.read_bytes()).hexdigest(),
                                     "entries": entries, "additionalCompiledEntries": additions}
            packaged.replace(target)
        coordinate = output / "repository/org/godotjfx" / artifact / version
        coordinate.mkdir(exist_ok=True, parents=True)
        prefix = coordinate / f"{artifact}-{version}"
        published = Path(str(prefix) + ".jar")
        pom = Path(str(prefix) + ".pom")
        shutil.copyfile(target, published)
        write_pom(pom, artifact, version, dependencies)
        files = [pom, published]
        if name in ("graphics", "media"):
            platform = Path(str(prefix) + "-" + classifier + ".jar")
            shutil.copyfile(target, platform)
            with ZipFile(platform, "a", compression=ZIP_DEFLATED) as archive:
                for library in natives:
                    if (library.name in media_libs) == (name == "media"):
                        archive.write(library, library.name)
                if name == "graphics":
                    archive.writestr("META-INF/godot-jfx/natives.id", build_id.hexdigest())
                    for legal in ("COPYRIGHT.txt", "LICENSE.txt", "LICENSE"):
                        archive.write(output / legal, "META-INF/godot-jfx/" + legal)
                for legal in (output / "legal" / module).glob("*"):
                    if legal.is_file():
                        archive.write(legal, f"META-INF/licenses/{module}/{legal.name}")
            files.append(platform)
            key = "windowsClassifierSha256" if windows else "macArm64ClassifierSha256"
            inventory[module][key] = hashlib.sha256(platform.read_bytes()).hexdigest()
        for file in files:
            Path(str(file) + ".sha1").write_text(hashlib.sha1(file.read_bytes()).hexdigest(), encoding="ascii")
    (output / "module-inventory.json").write_text(json.dumps(inventory, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("version")
    parser.add_argument("jar_tool", type=Path)
    parser.add_argument("--classifier", choices=("win", "mac-aarch64"), default="win")
    args = parser.parse_args()
    publish(Path(__file__).resolve().parents[1] / "jfx", args.output, args.version, args.jar_tool, args.classifier)
