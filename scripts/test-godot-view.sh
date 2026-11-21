#!/bin/sh
# macOS equivalent of test-godot-view.ps1. The transform clip reference run
# uses the stock macOS Prism pipeline (Metal by default) instead of D3D.
# Usage: test-godot-view.sh [--driver metal|opengl] [--render-thread safe] [--transform] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
DRIVER="metal"
RENDER_THREAD="safe"
TRANSFORM=0
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --transform) TRANSFORM=1 ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

if [ "$TRANSFORM" -eq 1 ]; then
    "$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
        -d artifacts/reference tests/reference/TransformClipReference.java || { echo "Transform clip reference compilation failed" >&2; exit 1; }
    CODE=0
    "$JDK/bin/java" -Dglass.platform=Mac --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
        --enable-native-access=javafx.graphics \
        -cp artifacts/reference TransformClipReference >agentdir/logs/transform-clip-mac-native.log 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ] || ! grep -q 'TRANSFORM_CLIP_REFERENCE_PASS' agentdir/logs/transform-clip-mac-native.log; then
        echo "Native transform clip reference failed: agentdir/logs/transform-clip-mac-native.log" >&2
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
LOG="$PWD/agentdir/logs/godot-view-$DRIVER$SUFFIX.log"
if [ "$RUNTIME" -eq 1 ]; then
    FIXTURE="$PWD/artifacts/runtime-godot-view"
    mkdir -p "$FIXTURE"
    for file in godot_view.tscn godot_view_test.gd embedded_scene.tscn embedded_scene.gd; do
        cp "tests/godot/$file" "$FIXTURE/"
    done
    sed 's|res://main.tscn|res://godot_view.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    CODE=0
    "$PWD/godot/bin/godot.macos.editor.arm64" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "GodotView runtime import failed: $LOG.import" >&2; exit 1; fi
    CODE=0
    (cd "$FIXTURE" && python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" \
        --render-thread "$RENDER_THREAD" --quit-after 4000 >"$LOG" 2>&1) || CODE=$?
else
    CODE=0
    python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://godot_view.tscn \
        --render-thread "$RENDER_THREAD" --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VIEW_PASS' "$LOG" \
    || ! grep -q 'GODOT_VIEW_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "GodotView probe failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-view.png "artifacts/reference/godot-view-$DRIVER$SUFFIX.png"
echo "GodotView probe passed: $LOG"
