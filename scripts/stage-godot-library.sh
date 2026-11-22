#!/bin/sh
set -eu
out=artifacts/godot-library
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != --destination ] || [ -z "$2" ]; then
        echo "Usage: $0 [--destination DIRECTORY]" >&2
        exit 2
    fi
    case "$2" in
        /*) out=$2 ;;
        *) out=$PWD/$2 ;;
    esac
fi
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
sdk=jfx/build/sdk
engine=godot/bin/libgodot.macos.template_release.arm64.library.dylib
for required in "$engine" "$sdk/lib/libjfxmedia_avf.dylib" "$sdk/lib/javafx.controls.jar"; do
    [ -f "$required" ] || { echo "Missing source build product: $required" >&2; exit 1; }
done
mkdir -p "$out/legal"
cp -R "$sdk/legal/." "$out/legal/"
cp godot/LICENSE.txt godot/COPYRIGHT.txt LICENSE "$out/"
python3 scripts/publish-godot-modules.py "$out" "$JAVA_HOME/bin/jar" --classifier mac-aarch64 --engine "$engine"
