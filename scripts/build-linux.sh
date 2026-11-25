#!/usr/bin/env bash
set -euo pipefail

usage='Usage: build-linux.sh --target godot-editor|godot-library|jfx [--jobs N] [--jdk DIRECTORY] [--clean]'
target=''
jobs=$(nproc)
action=build
while (($#)); do
    case "$1" in
        --target) target=${2:?}; shift 2 ;;
        --jobs) jobs=${2:?}; shift 2 ;;
        --jdk) export JAVA_HOME=${2:?}; shift 2 ;;
        --clean) action=clean; shift ;;
        --help) echo "$usage"; exit 0 ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
done
[[ $(uname -s)-$(uname -m) == Linux-x86_64 && $jobs =~ ^[1-9][0-9]*$ ]] || exit 2
cd "$(dirname "$0")/.."
root=$PWD
case "$target" in
    godot-editor|godot-library)
        # Godot disables Wayland when its scanner is missing, even with wayland=yes.
        if ! type -P wayland-scanner >/dev/null; then
            if [[ -x "$root/.tools/linux/wayland/usr/bin/wayland-scanner" ]]; then
                export PATH="$root/.tools/linux/wayland/usr/bin:$PATH"
            elif [[ $action == build ]]; then
                echo 'Building Godot for Wayland requires wayland-scanner on PATH or in .tools/linux/wayland/usr/bin.' >&2
                exit 1
            fi
        fi
        if [[ -n ${SCONS:-} ]]; then
            scons=("$SCONS")
        elif [[ -x $root/.tools/pyenv/bin/scons ]]; then
            scons=("$root/.tools/pyenv/bin/scons")
        else
            scons=(python3 -m SCons)
        fi
        args=(-C godot platform=linuxbsd arch=x86_64 vulkan=yes opengl3=yes x11=no wayland=yes "accesskit=no" "-j$jobs")
        if [[ $target == godot-editor ]]; then
            args+=(target=editor)
        else
            : "${JAVA_HOME:?Set JAVA_HOME to a Linux JDK 25}"
            args+=(target=template_release library_type=shared_library extra_suffix=library use_static_cpp=no
                disable_path_overrides=no "custom_modules=$root/native/godot_modules")
        fi
        if [[ $action == clean ]]; then
            args+=(--clean)
        fi
        command=("${scons[@]}" "${args[@]}")
        ;;
    jfx)
        : "${JAVA_HOME:?Set JAVA_HOME to a Linux JDK 25}"
        export ANT_HOME=${ANT_HOME:-$root/.tools/apache-ant-1.10.15}
        export GRADLE_USER_HOME=$root/.gradle-cache
        cd jfx
        if [[ $action == clean ]]; then
            command=(./gradlew cleanAll --no-problems-report --no-daemon)
        else
            command=(./gradlew sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false --no-daemon "--max-workers=$jobs")
        fi
        ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
mkdir -p "$root/agentdir/logs"
"${command[@]}" 2>&1 | tee "$root/agentdir/logs/$action-linux-$target.log"
