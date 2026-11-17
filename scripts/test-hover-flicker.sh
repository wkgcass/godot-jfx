#!/bin/sh
# macOS equivalent of test-hover-flicker.ps1. Default is the synthetic mode
# (host-side motion injection). --robot drives the real OS cursor via the
# Glass Robot: the terminal needs Accessibility and Screen Recording
# permissions; keep the desktop idle and the test window frontmost.
# Usage: test-hover-flicker.sh [--renderer mobile|gl_compatibility] [--render-thread safe] [--robot]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
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

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

VFX_CP="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/resources/main:artifacts/vfx/resources/test"
for jar in artifacts/vfx/dependencies/*.jar; do VFX_CP="$VFX_CP:$jar"; done
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -cp "$VFX_CP" -encoding UTF-8 -d artifacts/reference tests/reference/HoverFlickerProbe.java \
    || { echo "Hover flicker probe compilation failed" >&2; exit 1; }

run_watchdog() {
    wlog="$1"; limit="$2"; shift 2
    "$@" >"$wlog" 2>&1 &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$limit" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wcode=0
    wait "$pid" || wcode=$?
    return "$wcode"
}

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_HOVER_ROBOT="$ROBOT"
SUFFIX=""
[ "$ROBOT" = "1" ] && SUFFIX="-robot"
LOG="artifacts/logs/hover-flicker-$RENDERER-$RENDER_THREAD$SUFFIX.log"
CODE=0
run_watchdog "$LOG" 240 "$GODOT" --path tests/godot res://hover_flicker.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'HOVER_PIXEL_STATS' "$LOG" \
    || ! grep -q 'HOVER_FLICKER_PASS' "$LOG" \
    || ! grep -q 'HOVER_FUSION_PIXEL_PASS' "$LOG" \
    || ! grep -q 'HOVER_RESOURCE_CLEANUP_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:' "$LOG"; then
    echo "Hover flicker probe failed. See $LOG" >&2
    exit 1
fi
echo "Hover flicker probe passed: $LOG"
