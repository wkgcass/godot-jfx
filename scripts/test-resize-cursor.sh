#!/bin/sh
# macOS equivalent of test-resize-cursor.ps1 (standard scene fixture only; the -Runtime
# isolated project variant is Windows-specific and not ported).
# Usage: test-resize-cursor.sh [--driver metal|opengl] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
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
    -encoding UTF-8 -d artifacts/reference tests/reference/ResizeCursorProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="agentdir/logs/resize_cursor-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://resize_cursor.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'RESIZE_CURSOR_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_RESIZE_CURSOR_PASS' "$LOG" \
    || ! grep -q 'RESIZE_HOVER true' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Resize cursor test failed: $LOG" >&2
    exit 1
fi
echo "Resize cursor passed: $LOG"
