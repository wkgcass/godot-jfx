#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
    --driver) shift ;;
esac
case ${1:-} in
    vulkan) driver=vulkan; method=mobile ;;
    opengl) driver=opengl3; method=gl_compatibility ;;
    *) echo "Usage: $0 --driver vulkan|opengl" >&2; exit 2 ;;
esac
[[ $# == 1 ]] || exit 2
root=$(cd "$(dirname "$0")/.." && pwd)
log="$root/agentdir/logs/wayland-msaa-$1.log"
mkdir -p "$(dirname "$log")"
env -u DISPLAY timeout -k 3 40 "$root/godot/bin/godot.linuxbsd.editor.x86_64" \
    --display-driver wayland --rendering-driver "$driver" --rendering-method "$method" \
    --path "$root/tests/wayland" --script res://msaa.gd 2>&1 | tee "$log"
grep -F "WAYLAND_MSAA_PASS display=Wayland driver=$driver method=$method " "$log" >/dev/null

if [[ $driver == opengl3 ]]; then
    grep -F "WARNING: 2D MSAA is not yet supported for GLES3." "$log" >/dev/null
    grep -Fx "MSAA_2D_UNSUPPORTED renderer=gl_compatibility pixels_unchanged=true" "$log" >/dev/null
fi
