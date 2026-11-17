#!/bin/sh
# macOS equivalent of test-native-exit.ps1.
# Usage: test-native-exit.sh [--renderer mobile|gl_compatibility] [--render-thread safe]
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

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
mkdir -p artifacts/logs

LOG="artifacts/logs/native-exit-$RENDERER-$RENDER_THREAD.log"
"$GODOT" --path tests/godot res://native_exit.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 1500 > "$LOG" 2>&1
CODE=$?
CYCLES=$(grep -c 'NATIVE_EXIT_CYCLE ' "$LOG" || true)
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'NATIVE_EXIT_PASS' "$LOG" \
    || [ "$CYCLES" -ne 12 ] \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Native exit test failed: $LOG" >&2
    exit 1
fi
echo "Native exit passed: $LOG"
