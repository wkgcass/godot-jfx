#!/bin/sh
# macOS equivalent of test-window-immediate-close.ps1.
# Usage: test-window-immediate-close.sh [--driver metal|opengl] [--render-thread safe] [--runtime]
set -u
cd "$(dirname "$0")/.."

runtime=""
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --runtime) runtime="-runtime" ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs

LOG="agentdir/logs/window-immediate-close-$DRIVER-$RENDER_THREAD$runtime.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://window_immediate_close.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 300 > "$LOG" 2>&1
CODE=$?
CYCLES=$(grep -c 'WINDOW_IMMEDIATE_CLOSE_CYCLE ' "$LOG" || true)
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'WINDOW_IMMEDIATE_CLOSE_PASS' "$LOG" \
    || [ "$CYCLES" -ne 32 ] \
    || grep -qE '^(ERROR:|SCRIPT ERROR:)' "$LOG"; then
    echo "Immediate window close failed: $LOG" >&2
    exit 1
fi
echo "Immediate window close passed: $LOG"
