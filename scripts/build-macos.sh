#!/bin/sh
set -eu

usage='Usage: build-macos.sh --target godot-editor|godot-library|jfx'
if [ "$#" -eq 1 ] && [ "$1" = '--help' ]; then
    echo "$usage"
    exit 0
fi
if [ "$#" -ne 2 ] || [ "$1" != '--target' ]; then
    echo "$usage" >&2
    exit 2
fi

cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
case "$2" in
    godot-editor)
        set -- target=editor
        ;;
    godot-library)
        set -- target=template_release library_type=shared_library extra_suffix=library \
            disable_path_overrides=no "custom_modules=$PWD/native/godot_modules"
        ;;
    jfx)
        export ANT_HOME="${ANT_HOME:-$PWD/.tools/apache-ant-1.10.15}"
        export GRADLE_USER_HOME="$PWD/.gradle-cache"
        cd jfx
        exec ./gradlew sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false --no-daemon
        ;;
    *)
        echo "$usage" >&2
        exit 2
        ;;
esac
exec .tools/pyenv/bin/scons -C godot platform=macos arch=arm64 vulkan=no accesskit=no angle=no -j8 "$@"
