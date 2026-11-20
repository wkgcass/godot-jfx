#!/bin/sh
# macOS equivalent of test-native-window-pixels.ps1.
# Usage: test-native-window-pixels.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/NativeWindowPixelsProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="agentdir/logs/native-window-pixels-$RENDERER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://native_window_pixels.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_NATIVE_WINDOW_PIXELS_PASS' "$LOG" \
    || ! grep -q 'NATIVE_WINDOW_PIXELS_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Native window pixels test failed: $LOG" >&2
    exit 1
fi
echo "Native window pixels passed: $LOG"
