#!/usr/bin/env bash
# Run the existing external GTK drag Robot cases inside a nested niri desktop.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
[[ ${WAYLAND_DISPLAY:-} == godot-private && -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || {
    echo 'Run inside scripts/wsl-wayland-session.sh --isolate-wslg' >&2; exit 2;
}

theme=$XDG_RUNTIME_DIR/icons/DragMeasurement
mkdir -p "$theme/cursors"
# The 64px theme asset marks the pointer around a transparent central 41px square.
cp tests/wayland/drag-measurement.cursor "$theme/cursors/reticle"
for name in default left_ptr arrow copy dnd-copy dnd-none no-drop not-allowed grab grabbing move dnd-move pointer; do
    ln -s reticle "$theme/cursors/$name"
done
printf '[Icon Theme]\nName=Drag measurement\nInherits=Adwaita\n' > "$theme/index.theme"
export XCURSOR_PATH="$XDG_RUNTIME_DIR/icons:${XCURSOR_PATH:-/usr/share/icons}"
export XCURSOR_THEME=DragMeasurement XCURSOR_SIZE=64
export GODOT_JFX_WAYLAND_MEASURE_DRAG_WITH_CURSOR=1
niri=${GODOT_JFX_NIRI_BIN:-niri}
niri_env=()
if [[ -n ${GODOT_JFX_NIRI_LIBRARY_PATH:-} ]]; then
    niri_env+=("LD_LIBRARY_PATH=$GODOT_JFX_NIRI_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}")
fi
unset NIRI_SOCKET GODOT_JFX_WAYLAND_TEST_LAYOUT
env "${niri_env[@]}" LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe "$niri" -c tests/wayland/niri-external-drag.kdl &
child=$!
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' EXIT
# niri includes its chosen Wayland display name in its IPC socket name.
shopt -s nullglob
for ((i=0; i<120; ++i)); do
    sockets=("$XDG_RUNTIME_DIR"/niri.*."$child".sock)
    if [[ ${#sockets[@]} == 1 ]]; then
        export NIRI_SOCKET=${sockets[0]}
        socket_name=${NIRI_SOCKET##*/niri.}
        export WAYLAND_DISPLAY=${socket_name%%.*}
        break
    fi
    kill -0 "$child"
    sleep .1
done
[[ -n ${NIRI_SOCKET:-} && -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || { echo 'niri startup timed out' >&2; exit 1; }
# The parent scale notification can arrive after the first 1280x800 mode.
# All three test windows must fit on the nested output at scale one.
for ((i=0; i<100; ++i)); do
    output=$(env "${niri_env[@]}" "$niri" msg --json outputs)
    if layout=$(python3 -c '
import json
import sys

output = json.load(sys.stdin).get("winit", {}).get("logical") or {}
width = output.get("width", 0)
height = output.get("height", 0)
if output.get("scale") != 1 or width < 1460 or height < 660:
    sys.exit(1)
print(f"{width}x{height}+40+260")
' <<< "$output"); then
        export GODOT_JFX_WAYLAND_TEST_LAYOUT="$layout"
        break
    fi
    sleep .1
done
[[ -n ${GODOT_JFX_WAYLAND_TEST_LAYOUT:-} ]] || { echo 'niri output does not fit the GTK and JavaFX fixtures' >&2; exit 1; }
scripts/run-linux-tests.py --group Robot --test test-drag-drop-external "$@"
