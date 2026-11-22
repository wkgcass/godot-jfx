#!/bin/sh
# macOS equivalent of test-vfx-dialog.ps1.
# Usage: test-vfx-dialog.sh [--driver metal|opengl] [--render-thread safe] [--inject-failure] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
FAILURE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --inject-failure) FAILURE=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxDialogProbe.java \
    || { echo "VFX dialog observer compilation failed" >&2; exit 1; }

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

export GODOT_JFX_VFX_FAILURE="$FAILURE"
SUFFIX=""
[ "$FAILURE" -eq 1 ] && SUFFIX="-failure"
LOG="agentdir/logs/vfx-dialog-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_dialog.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 20000 || CODE=$?
if [ "$FAILURE" -eq 1 ]; then
    UNEXPECTED=$(grep -E '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*(Exception|Error))|RejectedExecutionException|RenderJob.run: internal exception|Suppressed:|Caused by:' "$LOG" \
        | grep -vF 'ERROR: Java application failed; see JVM exception in the host log' \
        | grep -vF 'Exception in thread "main" java.lang.AssertionError: java.lang.AssertionError: INJECTED_VFX_FAILURE' \
        | grep -vF 'Caused by: java.lang.AssertionError: INJECTED_VFX_FAILURE' || true)
    if [ "$CODE" -ne 0 ] \
        || ! grep -q 'GODOT_VFX_FAILURE_SHUTDOWN_PASS' "$LOG" \
        || ! grep -q 'INJECTED_VFX_FAILURE' "$LOG" \
        || [ -n "$UNEXPECTED" ]; then
        echo "VFX failure shutdown test failed: $LOG" >&2
        exit 1
    fi
    echo "VFX failure shutdown passed: $LOG"
    exit 0
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VFX_DIALOG_PASS' "$LOG" \
    || ! grep -q 'VFX_DIALOG_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "VFX dialog test failed: $LOG" >&2
    exit 1
fi
for step in 0 1 2 3 4; do
    cp "artifacts/reference/vfx-dialog-$step.png" "artifacts/reference/vfx-dialog-$DRIVER-$RENDER_THREAD-$step.png"
done
echo "VFX dialog passed: $LOG"
