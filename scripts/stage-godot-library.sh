#!/bin/sh
set -eu
. "$(dirname "$0")/macos-jdk.sh"
out=artifacts/godot-library
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != --destination ] || [ -z "$2" ]; then
        echo "Usage: $0 [--destination DIRECTORY] [--jdk DIRECTORY]" >&2
        exit 2
    fi
    case "$2" in
        /*) out=$2 ;;
        *) out=$PWD/$2 ;;
    esac
fi
cd "$(dirname "$0")/.."
sdk=jfx/build/sdk
case "$(uname -s):$(uname -m)" in
    Linux:x86_64) classifier=linux; engine=godot/bin/libgodot.linuxbsd.template_release.x86_64.library.so ;;
    Darwin:arm64) classifier=mac-aarch64; engine=godot/bin/libgodot.macos.template_release.arm64.library.dylib ;;
    *) echo "Unsupported staging platform" >&2; exit 1 ;;
esac
for required in "$engine" "$sdk/lib/javafx.controls.jar"; do
    [ -f "$required" ] || { echo "Missing source build product: $required" >&2; exit 1; }
done
mkdir -p "$out/legal"
cp -R "$sdk/legal/." "$out/legal/"
cp godot/LICENSE.txt godot/COPYRIGHT.txt LICENSE "$out/"
python3 scripts/publish-godot-modules.py "$out" "$JAVA_HOME/bin/jar" --classifier "$classifier" --engine "$engine"
