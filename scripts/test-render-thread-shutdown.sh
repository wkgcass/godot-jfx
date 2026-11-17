#!/bin/sh
# macOS equivalent of test-render-thread-shutdown.ps1.
# Usage: test-render-thread-shutdown.sh [--runtime]
# Note: --runtime (release template) is not available on macOS yet; only the
# editor binary is built. The Windows script requires the log to mention
# 'Vulkan'; on macOS the mobile renderer is Metal, so any render driver
# banner (Metal|Vulkan|OpenGL ES) is accepted here instead.
set -u
cd "$(dirname "$0")/.."

RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ "$RUNTIME" -eq 1 ]; then
    echo "--runtime requires a template_release build, which is not available on macOS yet" >&2
    exit 2
fi

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
mkdir -p artifacts/logs

LOG="artifacts/logs/render-thread-shutdown-editor-safe.log"
"$GODOT" --path tests/godot res://render_thread_shutdown.tscn \
    --rendering-method mobile --render-thread safe --quit-after 3 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -qE 'Metal|Vulkan|OpenGL ES' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:)|leaked at exit' "$LOG"; then
    echo "Render thread shutdown failed: $LOG" >&2
    exit 1
fi
echo "Render thread shutdown passed: editor / safe"
