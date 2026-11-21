#!/bin/sh
# macOS equivalent of test-native-windows.ps1.
# Usage: test-native-windows.sh [--driver metal|opengl] [--render-thread safe]
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
mkdir -p agentdir/logs

LOG="agentdir/logs/native-windows-$DRIVER-$RENDER_THREAD.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://native_windows.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 3000 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'NATIVE_WINDOWS_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Native windows test failed: $LOG" >&2
    exit 1
fi
echo "Native windows passed: $LOG"
