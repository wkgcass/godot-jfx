#!/usr/bin/env bash
# Run Linux GUI tests on a private Wayland desktop with a headless Weston output.
set -euo pipefail
if [[ ${1:-} == --isolate-wslg ]]; then
    shift
    isolation=(--bind / / --dev /dev --dev-bind /dev/dxg /dev/dxg --dev-bind-try /dev/dri /dev/dri
               --unshare-net --unshare-ipc --unshare-pid --proc /proc --tmpfs /tmp)
    if [[ -S /mnt/wslg/PulseServer ]]; then
        isolation+=(--ro-bind /mnt/wslg/PulseServer /tmp/test-pulse --setenv PULSE_SERVER unix:/tmp/test-pulse)
    else
        isolation+=(--unsetenv PULSE_SERVER)
    fi
    isolation+=(--tmpfs /mnt/wslg --tmpfs "/run/user/$(id -u)" --tmpfs /run/WSL --unsetenv WSL_INTEROP)
    exec bwrap "${isolation[@]}" -- "$0" "$@"
fi
compositor=weston
if [[ ${1:-} == --compositor ]]; then
    compositor=${2:-}
    case "$compositor" in
        weston|labwc) shift 2 ;;
        *) echo 'Expected --compositor weston|labwc' >&2; exit 2 ;;
    esac
fi
no_input=0
if [[ ${1:-} == --no-input ]]; then
    [[ $compositor == weston ]] || { echo '--no-input requires Weston' >&2; exit 2; }
    no_input=1
    shift
fi
layout=''
if [[ ${1:-} == --test-layout ]]; then
    layout=${2:-}
    if [[ $compositor != labwc || ! $layout =~ ^[1-9][0-9]{0,4}x[1-9][0-9]{0,4}[+][0-9]{1,5}[+][0-9]{1,5}$ ]]; then
        echo 'Expected --compositor labwc --test-layout WIDTHxHEIGHT+X+Y' >&2
        exit 2
    fi
    shift 2
fi
if [[ $# == 0 ]]; then
    echo "Usage: $0 [--isolate-wslg] [--compositor weston|labwc] [--no-input] [--test-layout WIDTHxHEIGHT+X+Y] COMMAND [ARGS...]" >&2
    exit 2
fi

# Run labwc as a client of the private Weston display. Its first free
# wayland-N socket belongs to this fresh, per-invocation runtime directory.
run_labwc() (
    set -euo pipefail
    local config=$XDG_RUNTIME_DIR/labwc
    mkdir "$config"
    if [[ -n $layout ]]; then
        export GODOT_JFX_WAYLAND_TEST_LAYOUT=$layout
        local coords=${layout#*+}
        # xdg-shell leaves toplevel placement to the compositor. Desktop Robot
        # fixtures can request a known origin on this dedicated test output.
        cat > "$config/rc.xml" <<XML
<labwc_config><windowRules>
  <windowRule identifier="*" serverDecoration="no"><action name="MoveTo" x="${coords%+*}" y="${coords#*+}"/></windowRule>
  <windowRule title="Drag target fixture"><action name="MoveTo" x="780" y="300"/></windowRule>
  <windowRule title="Owned overlap fixture"><action name="MoveTo" x="780" y="300"/></windowRule>
  <windowRule title="Drag source fixture"><action name="MoveTo" x="1140" y="300"/></windowRule>
  <windowRule title="DragDrop owned target"><action name="MoveTo" x="500" y="80"/></windowRule>
</windowRules></labwc_config>
XML
    else
        echo '<labwc_config/>' > "$config/rc.xml"
    fi
    touch "$config/autostart" "$config/shutdown" "$config/environment"
    local executable=labwc root=${GODOT_JFX_LABWC_ROOT:-}
    local -a compositor_env=(WLR_BACKENDS=wayland WLR_RENDERER=pixman WLR_WL_OUTPUTS=1)
    if [[ -n $root ]]; then
        root=$(realpath "$root")
        executable=$root/usr/bin/labwc
        compositor_env+=("LD_LIBRARY_PATH=$root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                         "XDG_DATA_DIRS=$root/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}")
    fi
    env "${compositor_env[@]}" "$executable" -C "$config" &
    local child=$!
    trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' EXIT
    export WAYLAND_DISPLAY=wayland-0
    for ((n=0; n<100; ++n)); do
        [[ ! -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || break
        kill -0 "$child" || return 1
        sleep 0.1
    done
    [[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || { echo 'labwc socket startup timed out' >&2; return 1; }
    if [[ -n $layout ]]; then
        local randr=wlr-randr
        [[ -z $root ]] || randr=$root/usr/bin/wlr-randr
        env "${compositor_env[@]}" "$randr" --output WL-1 --custom-mode "${layout%%+*}"
        env "${compositor_env[@]}" "$randr"
    fi
    "$@"
)

run_session() {
    set -euo pipefail
    local directory=$1 desktop=$2 layout=$3 no_input=$4
    shift 4
    export XDG_RUNTIME_DIR=$directory
    export WAYLAND_DISPLAY=godot-private
    unset WAYLAND_SOCKET
    local args=(-B headless --renderer=pixman --width=1560 --height=1040 --scale=2
                --idle-time=0 --socket="$WAYLAND_DISPLAY")
    unset GODOT_JFX_TEST_WESTON_WITH_INPUT
    local headers=${GODOT_JFX_WESTON_INCLUDE:-$(pkg-config --variable=includedir libweston-14)/libweston-14}
    "${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter -fPIC -shared \
        "-I$headers" $(pkg-config --cflags wayland-server pixman-1 xkbcommon) \
        "$script_dir/../tests/native/wayland_test_seat.c" -o "$directory/seat.so"
    local -a modules=("$directory/seat.so")
    unset GODOT_JFX_WESTON_SEAT
    if ((no_input)); then
        echo 'Private Weston is running without native input devices' >&2
    else
        export GODOT_JFX_WESTON_SEAT=$directory/seat.fifo
        mkfifo -m 600 "$GODOT_JFX_WESTON_SEAT"
        if [[ $desktop == weston ]]; then export GODOT_JFX_TEST_WESTON_WITH_INPUT=1; fi
    fi
    local executable=weston root=${GODOT_JFX_WESTON_ROOT:-}
    local -a weston_env=()
    if [[ -n $root ]]; then
        root=$(realpath "$root")
        local lib=$root/usr/lib/x86_64-linux-gnu
        executable=$root/usr/bin/weston
        weston_env=("LD_LIBRARY_PATH=$lib:$lib/weston${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                    "WESTON_DATA_DIR=$root/usr/share/weston"
                    "WESTON_MODULE_MAP=headless-backend.so=$lib/libweston-14/headless-backend.so;desktop-shell.so=$lib/weston/desktop-shell.so")
    fi
    {
        echo '[shell]'
        [[ -z $root ]] || echo "client=$root/usr/libexec/weston-desktop-shell"
        echo 'locking=false'
        echo 'panel-position=none'
        echo '[input-method]'
        echo 'path='
    } > "$directory/weston.ini"
    if [[ -n ${GODOT_JFX_WESTON_DND_MODULE:-} ]]; then
        modules+=("$GODOT_JFX_WESTON_DND_MODULE")
        export GODOT_JFX_WAYLAND_DND_DIR=$directory
    fi
    local module_list
    module_list=$(IFS=,; echo "${modules[*]}")
    args+=("--modules=$module_list")
    env "${weston_env[@]}" "$executable" "${args[@]}" --config="$directory/weston.ini" &
    local compositor=$!
    trap "kill $compositor 2>/dev/null || true; wait $compositor || true" EXIT
    for ((n=0; n<100; ++n)); do
        [[ ! -S $directory/$WAYLAND_DISPLAY ]] || break
        kill -0 "$compositor" || return 1
        sleep 0.1
    done
    [[ -S $directory/$WAYLAND_DISPLAY ]] || { echo 'Wayland socket startup timed out' >&2; return 1; }
    unset DISPLAY
    export GDK_BACKEND=wayland XDG_SESSION_TYPE=wayland
    if [[ $desktop == labwc ]]; then
        run_labwc "$@"
    else
        "$@"
    fi
}
directory=$(mktemp -d /tmp/godot-jfx-wayland-XXXXXXXX)
trap 'rm -rf -- "$directory"' EXIT
export XDG_RUNTIME_DIR=$directory WAYLAND_DISPLAY=godot-private
unset DISPLAY WAYLAND_SOCKET DBUS_SESSION_BUS_ADDRESS
export script_dir=$(cd "$(dirname "$0")" && pwd)
dbus-run-session -- bash -c "$(declare -f run_labwc run_session)"$'\n''run_session "$@"' bash "$directory" "$compositor" "$layout" "$no_input" "$@"
