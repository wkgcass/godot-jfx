#!/bin/sh
# macOS equivalent of test-hover-demo.ps1. This test moves the real mouse over
# the running VFX demo: the terminal needs Accessibility and Screen Recording
# permissions (System Settings -> Privacy & Security); keep the desktop idle
# and the demo window frontmost.
# Usage: test-hover-demo.sh [--renderer mobile|gl_compatibility] [--render-thread safe] [--compile-only]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RENDER_THREAD="safe"
COMPILE_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --compile-only) COMPILE_ONLY=1 ;;
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
    -cp "$VFX_CP" -encoding UTF-8 -d artifacts/reference tests/reference/HoverDemoProbe.java \
    || { echo "Hover demo probe compilation failed" >&2; exit 1; }
if [ "$COMPILE_ONLY" = "1" ]; then
    echo "Hover demo compilation passed; physical run not performed"
    exit 0
fi

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

export GODOT_JFX_HOVER_DEMO_ROBOT=1
export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/hover-demo-$RENDERER-$RENDER_THREAD.log"
CODE=0
run_watchdog "$LOG" 300 "$GODOT" --path tests/godot res://hover_demo.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'HOVER_DEMO_PASS' "$LOG" \
    || ! grep -q 'HOVER_DEMO_PIXEL_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:' "$LOG"; then
    echo "Hover demo probe failed. See $LOG" >&2
    echo "If the log shows no hover activity at all, this is likely a macOS TCC" >&2
    echo "permission issue: grant the terminal Accessibility and Screen Recording" >&2
    echo "under System Settings -> Privacy & Security, then re-run." >&2
    exit 1
fi
echo "Hover demo probe passed: $LOG"
