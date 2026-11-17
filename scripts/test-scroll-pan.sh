#!/bin/sh
# Trackpad pan-stream contract probe: monotonic accumulation, exact boundary
# clamping and no movement after the gesture ends ("fingers released").
# Usage: test-scroll-pan.sh [--renderer mobile|gl_compatibility] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
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
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics,javafx.controls \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/PanScrollProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/scroll_pan-$RENDERER-$RENDER_THREAD.log"
CODE=0
"$GODOT" --path tests/godot res://scroll_pan.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 3600 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'PAN_SCROLL_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_SCROLL_PAN_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Scroll pan test failed: $LOG" >&2
    exit 1
fi
# Exactly-once contract: injected InputEventPanGesture count must equal the
# Java ScrollEvent count. Upstream Godot dispatches gesture events twice; the
# engine patch in this fork keeps exactly one delivery per OS event.
INJECTED=$(sed -n 's/^PAN_INJECTED total=//p' "$LOG")
EVENTS=$(sed -n 's/^PAN_EVENTS total=//p' "$LOG")
if [ -z "$INJECTED" ] || [ "$INJECTED" != "$EVENTS" ]; then
    echo "Scroll pan test failed: injected $INJECTED != java events $EVENTS ($LOG)" >&2
    exit 1
fi
echo "Scroll pan passed ($EVENTS events): $LOG"
