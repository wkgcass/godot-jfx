#!/bin/sh
# macOS equivalent of test-window-immediate-close.ps1.
# Usage: test-window-immediate-close.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--runtime]
# The isolated project variant is unavailable for this fixture.
set -u
cd "$(dirname "$0")/.."

RENDERER="gl_compatibility"
RENDER_THREAD="safe"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
if [ "$RUNTIME" -eq 1 ]; then
    echo "This fixture does not implement --runtime on macOS" >&2
    exit 2
fi

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p artifacts/logs

LOG="artifacts/logs/window-immediate-close-$RENDERER-$RENDER_THREAD.log"
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://window_immediate_close.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 300 > "$LOG" 2>&1
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
