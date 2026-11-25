#!/bin/sh
# macOS equivalent of test-hover-flicker.ps1. Default is the synthetic mode
# (host-side motion injection). --robot drives the real OS cursor via the
# Glass Robot: the terminal needs Accessibility and Screen Recording
# permissions; keep the desktop idle and the test window frontmost.
# Usage: test-hover-flicker.sh [--driver metal|opengl] [--render-thread safe] [--robot] [--jdk DIRECTORY]
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

VFX_CP="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/resources/main:artifacts/vfx/resources/test"
for jar in artifacts/vfx/dependencies/*.jar; do VFX_CP="$VFX_CP:$jar"; done
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -cp "$VFX_CP" -encoding UTF-8 -d artifacts/reference tests/reference/HoverFlickerProbe.java \
    || { echo "Hover flicker probe compilation failed" >&2; exit 1; }

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

export GODOT_JFX_HOVER_ROBOT="$ROBOT"
SUFFIX=""
[ "$ROBOT" = "1" ] && SUFFIX="-robot"
LOG="agentdir/logs/hover-flicker-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
# The pixel probe excludes 23 frames for the 300 ms Fusion transition.
# Keep those samples at desktop cadence when WSLg's swapchain is uncapped.
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://hover_flicker.tscn \
    --render-thread "$RENDER_THREAD" --max-fps 60 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'HOVER_PIXEL_STATS' "$LOG" \
    || ! grep -q 'HOVER_FLICKER_PASS' "$LOG" \
    || ! grep -q 'HOVER_FUSION_PIXEL_PASS' "$LOG" \
    || ! grep -q 'HOVER_RESOURCE_CLEANUP_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:' "$LOG"; then
    echo "Hover flicker probe failed. See $LOG" >&2
    exit 1
fi
echo "Hover flicker probe passed: $LOG"
