#!/bin/sh
# macOS equivalent of test-window-drag.ps1.
# Usage: test-window-drag.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
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

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowDragProbe.java

LOG="agentdir/logs/window_drag-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://window_drag.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 5400 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'WINDOW_DRAG_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_WINDOW_DRAG_PASS' "$LOG" \
    || ! grep -q 'DRAG_LAG_AVG' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Window drag test failed: $LOG" >&2
    exit 1
fi
LAG=$(sed -n 's/^DRAG_LAG_AVG \([0-9.]*\).*/\1/p' "$LOG" | head -1)
WORST=$(sed -n 's/^DRAG_LAG_MAX \([0-9]*\).*/\1/p' "$LOG" | head -1)
echo "Window drag passed (avg lag $LAG frames, max $WORST): $LOG"
