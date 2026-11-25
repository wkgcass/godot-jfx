#!/bin/sh
# macOS equivalent of test-physical-drag.ps1. Default is the synthetic mode,
# which injects the gesture host-side and never touches the OS cursor.
# --robot restores the physical Glass-Robot drive: it moves the real cursor
# (the terminal needs Accessibility and Screen Recording permissions; keep the
# desktop idle and the test window frontmost).
# Usage: test-physical-drag.sh [--driver metal|opengl] [--render-thread safe] [--robot] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
RENDER_THREAD="safe"
ROBOT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --robot) ROBOT=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics,javafx.swing \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/PhysicalDragProbe.java

# Synthetic mode injects the gesture host-side and never touches the OS cursor;
# --robot switches the probe to the real Glass Robot.
export GODOT_JFX_PHYSICAL_DRAG_ROBOT="$ROBOT"
export GODOT_JFX_PHYSICAL_DRAG_CAPTURE="$PWD/artifacts/reference/physical-drag-desktop.png"
SUFFIX=""
[ "$ROBOT" = "1" ] && SUFFIX="-robot"
LOG="agentdir/logs/physical_drag-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
# --quit-after is only a hang backstop (the scene has its own 120s deadline):
# when the window server declines to vsync this session the main loop runs
# unthrottled and 3600 iterations elapse in a few seconds, killing the test
# mid-gesture. Keep the frame budget well above the worst-case duration.
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://physical_drag.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 60000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'PHYSICAL_DRAG_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_PHYSICAL_DRAG_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG"; then
    echo "Physical drag test failed: $LOG" >&2
    exit 1
fi
echo "Physical drag passed: $LOG"
