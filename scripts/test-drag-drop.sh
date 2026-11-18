#!/bin/sh
# macOS equivalent of test-drag-drop.ps1. Default is the synthetic input mode.
# --robot drives the real mouse/keyboard (the terminal needs Accessibility and
# Screen Recording permissions; keep the desktop idle and the window frontmost).
# Usage: test-drag-drop.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--robot]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
ROBOT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --robot) ROBOT=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/DragDropProbe.java

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_ROBOT_DRAG="$ROBOT"
SUFFIX=""
[ "$ROBOT" = "1" ] && SUFFIX="-robot"
LOG="artifacts/logs/drag-drop-$RENDERER-$RENDER_THREAD$SUFFIX.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://drag_drop.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_DRAG_DROP_PASS' "$LOG" \
    || ! grep -q 'DRAG_DROP_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Drag/drop test failed: $LOG" >&2
    exit 1
fi
echo "Drag/drop passed: $LOG"
