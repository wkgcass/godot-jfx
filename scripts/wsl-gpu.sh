#!/usr/bin/env bash
set -euo pipefail
usage='Usage: wsl-gpu.sh vulkan|opengl COMMAND [ARGS...]'
[[ $# -ge 2 ]] || { echo "$usage" >&2; exit 2; }
[[ -c /dev/dxg ]] || { echo 'Expected the WSL GPU device /dev/dxg' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd -P)
pulse=$root/.tools/linux/pulse/usr/lib/x86_64-linux-gnu
if [[ -r $pulse/libpulse.so.0 ]]; then
    export LD_LIBRARY_PATH=$pulse:$pulse/pulseaudio${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
if [[ -r $root/.tools/linux/pulse/wsl-alsa.conf && -r $pulse/alsa-lib/libasound_module_pcm_pulse.so ]]; then
    export ALSA_CONFIG_PATH=${ALSA_CONFIG_PATH:-$root/.tools/linux/pulse/wsl-alsa.conf}
    export ALSA_PLUGIN_DIR=${ALSA_PLUGIN_DIR:-$pulse/alsa-lib}
fi
ffmpeg=$root/.tools/linux/ffmpeg-runtime
if [[ -d $ffmpeg ]]; then
    export LD_LIBRARY_PATH=$ffmpeg${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
uses_wslg_wayland() {
    local wslg=/mnt/wslg/runtime-dir/wayland-0 display=${WAYLAND_DISPLAY:-}
    [[ -S $wslg ]] || return 1
    if [[ -n ${WAYLAND_SOCKET:-} ]]; then
        # libwayland gives an inherited connection precedence over WAYLAND_DISPLAY.
        python3 - "$WAYLAND_SOCKET" "$wslg" <<'PYTHON'
import os
import socket
import sys

try:
    with socket.socket(fileno=os.dup(int(sys.argv[1]))) as connection:
        peer = connection.getpeername()
    match = isinstance(peer, str) and os.path.isabs(peer) and os.path.samefile(peer, sys.argv[2])
except (OSError, ValueError, OverflowError):
    match = False
sys.exit(0 if match else 1)
PYTHON
        return $?
    fi
    [[ -n $display ]] || return 1
    if [[ $display != /* ]]; then
        [[ -n ${XDG_RUNTIME_DIR:-} ]] || return 1
        display=$XDG_RUNTIME_DIR/$display
    fi
    [[ $display -ef $wslg ]]
}

case "$1" in
    vulkan)
        mesa=${WSL_DZN_ROOT:-$root/.tools/linux/dzn/mesa}
        [[ -r $mesa/usr/share/vulkan/icd.d/dzn_icd.json && -r $mesa/usr/lib/x86_64-linux-gnu/libvulkan_dzn.so ]] ||
            { echo "Missing extracted Dozen ICD under $mesa" >&2; exit 1; }
        if [[ ! -v GODOT_JFX_VSYNC_FALLBACK ]] && uses_wslg_wayland; then
            export GODOT_JFX_VSYNC_FALLBACK=0
        fi
        export VK_DRIVER_FILES=$mesa/usr/share/vulkan/icd.d/dzn_icd.json
        export LD_LIBRARY_PATH=$mesa/usr/lib/x86_64-linux-gnu:/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        ;;
    opengl)
        export GALLIUM_DRIVER=d3d12
        export MESA_D3D12_DEFAULT_ADAPTER_NAME=${MESA_D3D12_DEFAULT_ADAPTER_NAME:-Intel}
        ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
shift
# Native GTK reference JVMs launched by test scripts use the same WSL GPU.
export GODOT_JFX_WSL_NATIVE_ES2=1
exec "$@"
