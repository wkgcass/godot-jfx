#!/bin/sh
# macOS equivalent of test-texture-lookup.ps1.
# Usage: test-texture-lookup.sh [--renderer mobile|gl_compatibility] [--render-thread safe]
set -u
cd "$(dirname "$0")/.."

RENDERER="mobile"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs

LOG="agentdir/logs/texture-lookup-$RENDERER-$RENDER_THREAD.log"
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://texture_lookup.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'TEXTURE_LOOKUP_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Texture lookup failed: $LOG" >&2
    exit 1
fi
grep 'TEXTURE_LOOKUP_PASS' "$LOG"
