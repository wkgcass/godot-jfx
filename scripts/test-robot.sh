#!/bin/sh
# The fixture moves the desktop pointer, clicks, types and reads screen pixels.
# Usage: test-robot.sh [--driver vulkan|metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
runtime=""
DRIVER="$native_driver"
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
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/RobotProbe.java \
    || { echo "Robot probe compilation failed" >&2; exit 1; }

run_watchdog() {
    wlog="$1"; limit="$2"; shift 2
    "$@" >"$wlog" 2>&1 &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$limit" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wcode=0
    wait "$pid" || wcode=$?
    return "$wcode"
}

LOG="agentdir/logs/robot-$DRIVER-$RENDER_THREAD$runtime.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://robot.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 10000 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_ROBOT_PASS' "$LOG" \
    || ! grep -q 'ROBOT_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Robot test failed: $LOG" >&2
    if [ "$(uname -s)" = Darwin ]; then
        echo "Check the terminal's Accessibility and Screen Recording permissions under Privacy & Security." >&2
    else
        echo "Check the compositor, the foreground window position, and the input and pixel samples in the log." >&2
    fi
    exit 1
fi
echo "Robot passed: $LOG"
