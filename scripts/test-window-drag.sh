#!/bin/sh
# macOS equivalent of test-window-drag.ps1.
# Usage: test-window-drag.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
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
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowDragProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/window_drag-$RENDERER-$RENDER_THREAD.log"
CODE=0
"$GODOT" --path tests/godot res://window_drag.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 5400 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'WINDOW_DRAG_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_WINDOW_DRAG_PASS' "$LOG" \
    || ! grep -q 'DRAG_LAG_AVG' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Window drag test failed: $LOG" >&2
    exit 1
fi
LAG=$(sed -n 's/^DRAG_LAG_AVG \([0-9.]*\).*/\1/p' "$LOG" | head -1)
WORST=$(sed -n 's/^DRAG_LAG_MAX \([0-9]*\).*/\1/p' "$LOG" | head -1)
echo "Window drag passed (avg lag $LAG frames, max $WORST): $LOG"
