#!/bin/sh
# macOS equivalent of test-texture-lookup.ps1.
# Usage: test-texture-lookup.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

DRIVER="$native_driver"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs

LOG="agentdir/logs/texture-lookup-$DRIVER-$RENDER_THREAD.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://texture_lookup.tscn \
    --render-thread "$RENDER_THREAD" > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'TEXTURE_LOOKUP_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Texture lookup failed: $LOG" >&2
    exit 1
fi
grep 'TEXTURE_LOOKUP_PASS' "$LOG"
