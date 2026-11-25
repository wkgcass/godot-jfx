#!/usr/bin/env bash
set -euo pipefail
case ${1:-} in
    --driver) shift ;;
esac
[[ $# == 1 && ( $1 == vulkan || $1 == opengl ) ]] || { echo "Usage: $0 [--driver] vulkan|opengl" >&2; exit 2; }
driver=vulkan
method=mobile
if [[ $1 == opengl ]]; then driver=opengl3; method=gl_compatibility; fi
root=$(cd "$(dirname "$0")/.." && pwd)
editor="$root/godot/bin/godot.linuxbsd.editor.x86_64"
mkdir -p "$root/agentdir/logs"
trace="$root/agentdir/logs/wayland-windows-$1.log"
rc=0
env -u DISPLAY WAYLAND_DEBUG=client EXPECTED_DRIVER="$driver" EXPECTED_METHOD="$method" timeout -k 3 45 "$editor" \
    --display-driver wayland --rendering-driver "$driver" --rendering-method "$method" \
    --path "$root/tests/wayland" --script res://windows.gd > "$trace" 2>&1 || rc=$?
if [[ -n ${WAYLAND_DEBUG:-} || $rc != 0 ]]; then cat "$trace"; else grep '^WAYLAND_' "$trace" || true; fi
(( rc == 0 )) || exit "$rc"
python3 "$root/scripts/check-wayland-windows.py" "$1" "$trace"
