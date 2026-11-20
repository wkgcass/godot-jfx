#!/bin/sh
# macOS equivalent of test-window-lifecycle.ps1.
# Usage: test-window-lifecycle.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
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

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowLifecycleProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="agentdir/logs/window-lifecycle-$RENDERER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://window_lifecycle.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_WINDOW_LIFECYCLE_PASS' "$LOG" \
    || ! grep -q 'WINDOW_LIFECYCLE_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Window lifecycle test failed: $LOG" >&2
    exit 1
fi
echo "Window lifecycle passed: $LOG"
