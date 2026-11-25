#!/bin/sh
# macOS equivalent of test-pacing-cap.ps1.
# Usage: test-pacing-cap.sh [--driver metal|opengl] [--mode cap|restore|override] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
MODE="cap"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --mode) MODE="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$MODE" in cap|restore|override) ;; *) echo "invalid mode: $MODE" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" -d artifacts/reference tests/reference/PacingCapProbe.java \
    || { echo "Pacing fixture compilation failed" >&2; exit 1; }

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

export GODOT_JFX_VSYNC_FALLBACK="1"
export GODOT_JFX_TEST_PACING_MODE="$MODE"
LOG="agentdir/logs/pacing-cap-$DRIVER-$MODE.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://pacing_cap.tscn \
    || CODE=$?
# The vsync-fallback banner must be absent exactly in cap mode.
FALLBACK_SEEN=0
grep -q 'JAVAFX_VSYNC_FALLBACK' "$LOG" && FALLBACK_SEEN=1
MODE_IS_CAP=0
[ "$MODE" = "cap" ] && MODE_IS_CAP=1
if [ "$CODE" -ne 0 ] \
    || ! grep -q '^PACING_CAP_PASS' "$LOG" \
    || ! grep -q 'PACING_CAP_JAVA_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG" \
    || [ "$FALLBACK_SEEN" -eq "$MODE_IS_CAP" ]; then
    echo "Pacing cap test failed: $LOG" >&2
    exit 1
fi
echo "Pacing cap test passed: $LOG"
