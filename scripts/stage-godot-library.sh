#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
sdk=jfx/build/sdk
out=artifacts/godot-library
engine=godot/bin/libgodot.macos.template_release.arm64.library.dylib
for required in "$engine" "$sdk/lib/libjfxmedia_avf.dylib" "$sdk/lib/javafx.controls.jar"; do
    [ -f "$required" ] || { echo "Missing source build product: $required" >&2; exit 1; }
done
mkdir -p "$out/legal"
cp -R "$sdk/legal/." "$out/legal/"
cp godot/LICENSE.txt godot/COPYRIGHT.txt LICENSE "$out/"
python3 scripts/publish-godot-modules.py "$out" "$JAVA_HOME/bin/jar" --classifier mac-aarch64 --engine "$engine"
