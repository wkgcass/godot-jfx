#!/bin/sh
# macOS equivalent of test-vfx-scroll.ps1. --runtime needs the Windows
# release-template fixture layout and is not ported.
# Usage: test-vfx-scroll.sh [--driver metal|opengl] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --runtime) echo "--runtime is not ported to macOS yet" >&2; exit 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxScrollProbe.java \
    || { echo "VFX scroll probe compilation failed" >&2; exit 1; }

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
LOG="agentdir/logs/vfx-scroll-$DRIVER-$RENDER_THREAD.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_scroll.tscn \
    --render-thread "$RENDER_THREAD" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VFX_SCROLL_PASS' "$LOG" \
    || ! grep -q 'VFX_SCROLL_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:' "$LOG"; then
    echo "VFX scroll failed: $LOG" >&2
    exit 1
fi
for step in 0 1 2 3; do
    cp "artifacts/reference/vfx-scroll-$step.png" "artifacts/reference/vfx-scroll-$DRIVER-$RENDER_THREAD-$step.png"
done
echo "VFX scroll passed: $LOG"
