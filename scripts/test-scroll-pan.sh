#!/bin/sh
# Trackpad pan-stream contract probe: monotonic accumulation, exact boundary
# clamping and no movement after the gesture ends ("fingers released").
# Usage: test-scroll-pan.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
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
    -encoding UTF-8 -d artifacts/reference tests/reference/PanScrollProbe.java

LOG="agentdir/logs/scroll_pan-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://scroll_pan.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 3600 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'PAN_SCROLL_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_SCROLL_PAN_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Scroll pan test failed: $LOG" >&2
    exit 1
fi
# Exactly-once contract: injected InputEventPanGesture count must equal the
# Java ScrollEvent count. Upstream Godot dispatches gesture events twice; the
# engine patch in this fork keeps exactly one delivery per OS event.
INJECTED=$(sed -n 's/^PAN_INJECTED total=//p' "$LOG")
EVENTS=$(sed -n 's/^PAN_EVENTS total=//p' "$LOG")
if [ -z "$INJECTED" ] || [ "$INJECTED" != "$EVENTS" ]; then
    echo "Scroll pan test failed: injected $INJECTED != java events $EVENTS ($LOG)" >&2
    exit 1
fi
echo "Scroll pan passed ($EVENTS events): $LOG"
