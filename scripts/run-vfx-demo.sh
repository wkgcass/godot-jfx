#!/bin/sh
# macOS equivalent of run-vfx-demo.ps1.
# Usage: run-vfx-demo.sh [--smoke] [--renderer mobile|gl_compatibility] [--render-thread safe] [--no-godot-logo] [--disable-vsync] [--max-fps N]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RENDER_THREAD="safe"
SMOKE=0
STARTUP="logo"
VSYNC_ARGS=""
MAX_FPS=0
DISABLE_VSYNC=0
while [ $# -gt 0 ]; do
    case "$1" in
        --smoke) SMOKE=1 ;;
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --no-godot-logo) STARTUP="hidden" ;;
        --disable-vsync) DISABLE_VSYNC=1 ;;
        --max-fps) MAX_FPS="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in mobile|gl_compatibility) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
# Like the Windows script: disabling swapchain vsync falls back to CPU pacing.
if [ "$DISABLE_VSYNC" -eq 1 ]; then
    VSYNC_ARGS="--disable-vsync"
    [ "$MAX_FPS" -le 0 ] && MAX_FPS=60
fi
if [ "$MAX_FPS" -gt 0 ]; then VSYNC_ARGS="$VSYNC_ARGS --max-fps $MAX_FPS"; fi
if [ ! -x "$JDK/bin/java" ]; then echo "JDK not found at $JDK" >&2; exit 1; fi

LOG="artifacts/logs/vfx-demo-$RENDERER-$RENDER_THREAD.log"
mkdir -p artifacts/logs

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_STARTUP="$STARTUP"
export GODOT_JFX_DEMO_SMOKE="$SMOKE"

echo "Starting the VFX Demo ($RENDERER + $RENDER_THREAD). Log: $LOG"
# shellcheck disable=SC2086
./godot/bin/godot.macos.editor.arm64 --path tests/godot res://vfx_demo.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" $VSYNC_ARGS > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ]; then echo "VFX Demo failed (native exit $CODE): $LOG" >&2; exit 1; fi
if ! grep -q 'VFX_DEMO_CLOSED' "$LOG"; then echo "VFX Demo missing VFX_DEMO_CLOSED: $LOG" >&2; exit 1; fi
if grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then echo "VFX Demo reported errors: $LOG" >&2; exit 1; fi
echo "VFX Demo closed cleanly: $LOG"
