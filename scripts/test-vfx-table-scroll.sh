#!/bin/sh
# macOS equivalent of test-vfx-table-scroll.ps1. The default uses direct drag;
# the Robot suite sets GODOT_JFX_DRAG_MODE=robot to exercise real input.
# Usage: test-vfx-table-scroll.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
#        [--profile] [--blackhole] [--sweeps 3..30]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
RENDER_THREAD="safe"
PROFILE=0
BLACKHOLE=0
SWEEPS=3
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --profile) PROFILE=1 ;;
        --blackhole) BLACKHOLE=1 ;;
        --sweeps) SWEEPS="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
[ "$SWEEPS" -ge 3 ] && [ "$SWEEPS" -le 30 ] || { echo "invalid sweeps: $SWEEPS" >&2; exit 2; }

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports=javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports=javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference \
    tests/reference/ThreadStackSampler.java tests/reference/VfxTableScrollProbe.java \
    || { echo "Table scroll probe compilation failed" >&2; exit 1; }

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

export GODOT_JFX_TABLE_SWEEPS="$SWEEPS" GODOT_JFX_TABLE_BLACKHOLE="$BLACKHOLE"
if [ "$PROFILE" -eq 1 ]; then export GODOT_JFX_PROFILE_COMMANDS=1; else unset GODOT_JFX_PROFILE_COMMANDS 2>/dev/null || true; fi
SWEEP_SUFFIX=""
[ "$SWEEPS" -ne 3 ] && SWEEP_SUFFIX="-sweeps$SWEEPS"
[ "$BLACKHOLE" -eq 0 ] || SWEEP_SUFFIX="$SWEEP_SUFFIX-blackhole"
LOG="agentdir/logs/vfx-table-scroll-$DRIVER-$RENDER_THREAD$SWEEP_SUFFIX.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_table_scroll.tscn \
    --render-thread "$RENDER_THREAD" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VFX_TABLE_SCROLL_PASS' "$LOG" \
    || ! grep -q 'VFX_TABLE_SCROLL_PROBE_PASS' "$LOG" \
    || ! grep -q 'VFX_TABLE_SCROLL_STATS' "$LOG" \
    || ! grep -q 'VFX_TABLE_SCROLL_IDLE_STATS' "$LOG" \
    || ! grep -qE '^VFX_TABLE_SCROLL pulses=' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:' "$LOG"; then
    echo "VFX table scroll failed: $LOG" >&2
    exit 1
fi
grep -qF 'VFX_TABLE_SCROLL_BACKEND glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline' "$LOG" \
    || { echo "Unexpected Glass/Prism backend: $LOG" >&2; exit 1; }
grep -E '^VFX_TABLE_SCROLL' "$LOG" || true
echo "VFX table scroll passed: $LOG"
