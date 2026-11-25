#!/bin/sh
# macOS equivalent of test-failure-shutdown.ps1.
# Usage: test-failure-shutdown.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
#        [--probe FailureShutdownProbe|FailureApplicationProbe] [--runtime]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
RENDER_THREAD="safe"
PROBE="FailureShutdownProbe"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --probe) PROBE="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
case "$PROBE" in FailureShutdownProbe|FailureApplicationProbe) ;; *) echo "invalid probe: $PROBE" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference "tests/reference/$PROBE.java" \
    || { echo "Failure probe compilation failed" >&2; exit 1; }

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

export GODOT_JFX_FAILURE_PROBE="$PROBE"
SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/agentdir/logs/failure-shutdown-$PROBE-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    FIXTURE="$PWD/artifacts/runtime-failure-shutdown"
    mkdir -p "$FIXTURE"
    cp tests/godot/failure_shutdown.tscn tests/godot/failure_shutdown.gd "$FIXTURE/"
    sed 's|res://main.tscn|res://failure_shutdown.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$PWD/godot/bin/$source_editor" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Failure runtime fixture import failed: $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" \
        --render-thread "$RENDER_THREAD" --quit-after 4000) || CODE=$?
else
    run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://failure_shutdown.tscn \
        --render-thread "$RENDER_THREAD" --quit-after 4000 || CODE=$?
fi
# Injected-failure diagnostics are expected verbatim; any other error line fails.
UNEXPECTED=$(grep -E '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*(Exception|Error))|RejectedExecutionException|RenderJob\.run: internal exception|Suppressed:|Caused by:' "$LOG" \
    | grep -vxF 'ERROR: Java application failed; see JVM exception in the host log' \
    | grep -vxF 'Exception in thread "main" java.lang.IllegalStateException: INJECTED_STAGE_FAILURE' || true)
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_FAILURE_SHUTDOWN_PASS' "$LOG" \
    || ! grep -q 'FAILURE_INNER_LOOP_RETURNED' "$LOG" \
    || ! grep -q 'FAILURE_NESTED_LOOP_RETURNED' "$LOG" \
    || ! grep -q 'INJECTED_STAGE_FAILURE' "$LOG" \
    || [ -n "$UNEXPECTED" ]; then
    echo "Failure shutdown test failed: $LOG" >&2
    [ -n "$UNEXPECTED" ] && echo "Unexpected diagnostics: $UNEXPECTED" >&2
    exit 1
fi
echo "Failure shutdown passed: $LOG"
