#!/bin/sh
# Usage: test-vfx-ripple.sh [--driver metal|opengl | --native] [--render-thread safe] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER=""
NATIVE=0
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --native) NATIVE=1 ;;
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ "$NATIVE" -eq 1 ] && [ -n "$DRIVER" ]; then
    echo "--driver selects the Godot backend" >&2; exit 2
fi
DRIVER=${DRIVER:-$native_driver}
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
[ -d artifacts/vfx/classes/java/main ] || { echo "VFX artifacts missing: artifacts/vfx" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxRippleProbe.java || { echo "Ripple probe compilation failed" >&2; exit 1; }

# run_watchdog <log> <seconds> <command...>: the scene quits by itself once
# the probe finishes; bound the wait in case the JVM or composition stalls.
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

CASE_NAME="$DRIVER-$RENDER_THREAD"
if [ "$NATIVE" -eq 1 ]; then CASE_NAME=native-$native_prism; fi
export GODOT_JFX_RIPPLE_OUTPUT="$PWD/artifacts/reference/vfx-ripple-$CASE_NAME"
LOG="agentdir/logs/vfx-ripple-$CASE_NAME.log"
CODE=0
if [ "$NATIVE" -eq 1 ]; then
    set -- python3 "$PWD/scripts/native_prism.py" "$JDK/bin/java" --module-path jfx/build/sdk/lib \
        --add-modules javafx.controls,javafx.swing,javafx.media --enable-native-access=javafx.graphics,javafx.media \
        -cp "$CLASSPATH:artifacts/vfx/resources/main:artifacts/vfx/resources/test:artifacts/reference" io.vproxy.vfx.intro.VfxRippleProbe
else
    set -- python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_ripple.tscn --render-thread "$RENDER_THREAD"
fi
run_watchdog "$LOG" 240 "$@" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'VFX_RIPPLE_PROBE_PASS' "$LOG" \
    || { [ "$NATIVE" -eq 0 ] && ! grep -q 'GODOT_VFX_RIPPLE_PASS' "$LOG"; } \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError' "$LOG"; then
    echo "Ripple test failed: $LOG" >&2
    exit 1
fi
echo "Ripple test passed: $LOG"
