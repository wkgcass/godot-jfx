#!/bin/sh
# macOS equivalent of test-scroll-wheel.ps1.
# Usage: test-scroll-wheel.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
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

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics,javafx.controls \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/ScrollWheelProbe.java

LOG="agentdir/logs/scroll_wheel-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://scroll_wheel.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 2400 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'SCROLL_WHEEL_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_SCROLL_WHEEL_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Scroll wheel test failed: $LOG" >&2
    exit 1
fi
SCROLL_LINE=$(grep -E '^SCROLL_RESULT events=3 pixels=[0-9.]+ expected=[0-9.]+$' "$LOG" | head -1 || true)
if [ -z "$SCROLL_LINE" ]; then
    echo "Missing three-notch scroll measurement: $LOG" >&2
    exit 1
fi
DELTA=$(printf '%s' "$SCROLL_LINE" | sed 's/^SCROLL_RESULT events=3 pixels=\([0-9.]*\) expected=.*/\1/')
echo "Scroll wheel passed (3 notches = $DELTA px): $LOG"
