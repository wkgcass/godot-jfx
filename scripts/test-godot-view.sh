#!/bin/sh
# macOS equivalent of test-godot-view.ps1. The transform clip reference run
# uses the stock macOS Prism pipeline (Metal by default) instead of D3D.
# Usage: test-godot-view.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--transform] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
TRANSFORM=0
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --transform) TRANSFORM=1 ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

GODOT="./godot/bin/godot.macos.editor.arm64"
TEMPLATE="./godot/bin/godot.macos.template_release.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

if [ "$TRANSFORM" -eq 1 ]; then
    "$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
        -d artifacts/reference tests/reference/TransformClipReference.java || { echo "Transform clip reference compilation failed" >&2; exit 1; }
    CODE=0
    "$JDK/bin/java" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
        --enable-native-access=javafx.graphics \
        -cp artifacts/reference TransformClipReference >artifacts/logs/transform-clip-mac-native.log 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ] || ! grep -q 'TRANSFORM_CLIP_REFERENCE_PASS' artifacts/logs/transform-clip-mac-native.log; then
        echo "Native transform clip reference failed: artifacts/logs/transform-clip-mac-native.log" >&2
        exit 1
    fi
fi

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/GodotViewProbe.java || { echo "GodotView probe compilation failed" >&2; exit 1; }

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_TEST_VIEW_TRANSFORM="$TRANSFORM"
SUFFIX=""
[ "$TRANSFORM" -eq 1 ] && SUFFIX="-transform"
[ "$RUNTIME" -eq 1 ] && SUFFIX="$SUFFIX-runtime"
LOG="$PWD/artifacts/logs/godot-view-$RENDERER$SUFFIX.log"
if [ "$RUNTIME" -eq 1 ]; then
    [ -x "$TEMPLATE" ] || { echo "Godot template not found: $TEMPLATE" >&2; exit 1; }
    FIXTURE="$PWD/artifacts/runtime-godot-view"
    mkdir -p "$FIXTURE"
    cp "$TEMPLATE" "$FIXTURE/"
    for file in godot_view.tscn godot_view_test.gd embedded_scene.tscn embedded_scene.gd; do
        cp "tests/godot/$file" "$FIXTURE/"
    done
    sed 's|res://main.tscn|res://godot_view.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    CODE=0
    "$GODOT" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "GodotView runtime import failed: $LOG.import" >&2; exit 1; fi
    CODE=0
    (cd "$FIXTURE" && "./godot.macos.template_release.arm64" \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 4000 >"$LOG" 2>&1) || CODE=$?
else
    CODE=0
    "$GODOT" --path tests/godot res://godot_view.tscn \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VIEW_PASS' "$LOG" \
    || ! grep -q 'GODOT_VIEW_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "GodotView probe failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-view.png "artifacts/reference/godot-view-$RENDERER$SUFFIX.png"
echo "GodotView probe passed: $LOG"
