#!/bin/sh
# macOS equivalent of test-media-planes.ps1.
# Usage: test-media-planes.sh [--driver metal|opengl]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
DRIVER="metal"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -d artifacts/reference tests/reference/MediaPlanesProbe.java \
    || { echo "Media planes compilation failed" >&2; exit 1; }

# run_watchdog <log> <seconds> <command...>: the scene quits by itself once the
# probe finishes; bound the wait in case the JVM or composition stalls.
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
LOG="agentdir/logs/media-planes-$DRIVER.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://media_planes.tscn \
    --render-thread safe --quit-after 3000 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'MEDIA_PLANES_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_MEDIA_PLANES_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Media planes failed: $LOG" >&2
    exit 1
fi
echo "Media planes passed: $LOG"
