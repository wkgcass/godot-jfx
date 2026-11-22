#!/bin/sh
# Usage: test-vfx-blackhole.sh [--driver metal|opengl | --native] [--render-thread safe]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
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
DRIVER=${DRIVER:-metal}
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
[ -d artifacts/vfx/classes/java/main ] || { echo "VFX artifacts missing: artifacts/vfx" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxBlackholeProbe.java || { echo "Blackhole probe compilation failed" >&2; exit 1; }

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

export GODOT_JFX_JDK="$JDK"
CASE_NAME="$DRIVER-$RENDER_THREAD"
if [ "$NATIVE" -eq 1 ]; then CASE_NAME=native-mtl; fi
export GODOT_JFX_BLACKHOLE_OUTPUT="$PWD/artifacts/reference/vfx-blackhole-$CASE_NAME"
LOG="agentdir/logs/vfx-blackhole-$CASE_NAME.log"
CODE=0
if [ "$NATIVE" -eq 1 ]; then
    set -- "$JDK/bin/java" -Dglass.platform=Mac -Dprism.order=mtl --module-path jfx/build/sdk/lib \
        --add-modules javafx.controls,javafx.swing,javafx.media --enable-native-access=javafx.graphics,javafx.media \
        -cp "$CLASSPATH:artifacts/vfx/resources/main:artifacts/vfx/resources/test:artifacts/reference" VfxBlackholeProbe
else
    set -- python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_blackhole.tscn --render-thread "$RENDER_THREAD"
fi
run_watchdog "$LOG" 240 "$@" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'VFX_BLACKHOLE_PROBE_PASS' "$LOG" \
    || { [ "$NATIVE" -eq 0 ] && ! grep -q 'GODOT_VFX_BLACKHOLE_PASS' "$LOG"; } \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError' "$LOG"; then
    echo "Blackhole test failed: $LOG" >&2
    exit 1
fi
echo "Blackhole test passed: $LOG"
