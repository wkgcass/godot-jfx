#!/bin/sh
# Usage: test-window-icon.sh [--driver metal|opengl] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
runtime=""
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) runtime="-runtime" ;;
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowIconProbe.java

LOG="agentdir/logs/window-icon-$DRIVER-$RENDER_THREAD$runtime.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://window_icon.tscn \
    --render-thread "$RENDER_THREAD" >"$LOG" 2>&1
if ! grep -q 'GODOT_WINDOW_ICON_PASS' "$LOG" || ! grep -q 'WINDOW_ICON_PROBE_PASS' "$LOG" \
    || [ "$(grep -c '^WINDOW_ICON_NATIVE ' "$LOG")" -ne 7 ] \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Window icon contract failed: $LOG" >&2
    exit 1
fi
echo "Seven per-window icon updates and teardown passed: $LOG"
