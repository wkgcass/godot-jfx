#!/bin/bash
set -euo pipefail

usage='Usage: build-macos.sh --target godot-editor|godot-library|jfx [--jobs 1..64] [--jdk DIRECTORY]'
target=''
jobs=8
while [ "$#" -gt 0 ]; do
    case "$1" in
        --jdk) JAVA_HOME=${2:?--jdk requires a JDK home directory}; export JAVA_HOME; shift ;;
        --target) target=${2:-}; shift ;;
        --jobs) jobs=${2:-}; shift ;;
        --help) echo "$usage"; exit 0 ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
    shift
done
case "$jobs" in ''|*[!0-9]*) echo "$usage" >&2; exit 2 ;; esac
[ "$jobs" -ge 1 ] && [ "$jobs" -le 64 ] || { echo "$usage" >&2; exit 2; }

if [ "$target" = jfx ] || [ "$target" = godot-library ]; then
    . "$(dirname "$0")/macos-jdk.sh"
fi
cd "$(dirname "$0")/.."
root=$PWD
case "$target" in
    godot-editor|godot-library)
        set -- .tools/pyenv/bin/scons -C godot platform=macos arch=arm64 vulkan=no accesskit=no angle=no "-j$jobs"
        if [ "$target" = godot-editor ]; then
            set -- "$@" target=editor
        else
            set -- "$@" target=template_release library_type=shared_library extra_suffix=library \
                disable_path_overrides=no "custom_modules=$root/native/godot_modules"
        fi
        ;;
    jfx)
        export ANT_HOME="${ANT_HOME:-$root/.tools/apache-ant-1.10.15}"
        export GRADLE_USER_HOME="$root/.gradle-cache"
        cd jfx
        set -- ./gradlew sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false --no-daemon "--max-workers=$jobs"
        ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
mkdir -p "$root/agentdir/logs"
"$@" 2>&1 | tee "$root/agentdir/logs/build-macos-$target.log"
