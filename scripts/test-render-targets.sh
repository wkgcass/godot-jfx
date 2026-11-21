#!/bin/sh
# macOS equivalent of test-render-targets.ps1.
# Usage: test-render-targets.sh [--driver metal|opengl] [--render-thread safe]
set -u
cd "$(dirname "$0")/.."

DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs artifacts/reference

LOG="agentdir/logs/render-targets-$DRIVER-$RENDER_THREAD.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://render_targets.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 3000 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'RENDER_TARGET_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Render target test failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-render-targets.png "artifacts/reference/godot-render-targets-$DRIVER-$RENDER_THREAD.png"
echo "Render target test passed: $LOG"
