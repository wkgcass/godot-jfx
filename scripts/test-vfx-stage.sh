#!/bin/sh
# macOS equivalent of test-vfx-stage.ps1.
# Usage: test-vfx-stage.sh [--driver metal|opengl] [--render-thread safe] [--abrupt] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
RENDER_THREAD="safe"
ABRUPT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --abrupt) ABRUPT=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxStageProbe.java \
    || { echo "VFX Stage observer compilation failed" >&2; exit 1; }

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

SUFFIX=""
if [ "$ABRUPT" -eq 1 ]; then
    export GODOT_JFX_VFX_ABRUPT=1
    SUFFIX="-abrupt"
fi
LOG="agentdir/logs/vfx-stage-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_stage.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 20000 || CODE=$?
if [ "$ABRUPT" -eq 1 ]; then
    if [ "$CODE" -ne 0 ] \
        || ! grep -q 'VFX_ABRUPT_EXIT_REQUESTED' "$LOG" \
        || ! grep -q 'VFX_STAGE_ABRUPT_RETURNED' "$LOG" \
        || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error)|RenderJob.run: internal exception)|GodotHostStoppedException|uncaught:|Suppressed:' "$LOG"; then
        echo "VFX abrupt exit failed: $LOG" >&2
        exit 1
    fi
    echo "VFX abrupt exit passed: $LOG"
    exit 0
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VFX_STAGE_PASS' "$LOG" \
    || ! grep -q 'VFX_STAGE_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception|com\.sun\.javafx\.tk\.godot\.GodotHostStoppedException)' "$LOG"; then
    echo "VFX Stage test failed: $LOG" >&2
    exit 1
fi
for step in 0 1 2 3 4 5 6 7 8 9 10 11; do
    cp "artifacts/reference/vfx-stage-$step.png" "artifacts/reference/vfx-stage-$DRIVER-$RENDER_THREAD-$step.png"
done
echo "VFX Stage passed: $LOG"
