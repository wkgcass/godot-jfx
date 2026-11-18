#!/bin/sh
# macOS equivalent of test-vfx-animation.ps1. --runtime needs the Windows
# release-template fixture layout and is not ported.
# Usage: test-vfx-animation.sh [--renderer mobile|gl_compatibility] [--render-thread safe] [--timing-only]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RENDER_THREAD="safe"
TIMING_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --timing-only) TIMING_ONLY=1 ;;
        --runtime) echo "--runtime is not ported to macOS yet" >&2; exit 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxAnimationProbe.java \
    || { echo "VFX animation probe compilation failed" >&2; exit 1; }

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
export GODOT_JFX_ANIMATION_TIMING_ONLY="$TIMING_ONLY"
SUFFIX=""
[ "$TIMING_ONLY" -eq 1 ] && SUFFIX="-timing-only"
LOG="artifacts/logs/vfx-animation-$RENDERER-$RENDER_THREAD$SUFFIX.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --path tests/godot res://vfx_animation.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_VFX_ANIMATION_PASS' "$LOG" \
    || ! grep -q 'VFX_ANIMATION_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:' "$LOG"; then
    echo "VFX animation failed: $LOG" >&2
    exit 1
fi
if [ "$TIMING_ONLY" -eq 1 ]; then
    grep -q 'VFX_ANIMATION_TIMING_STATS' "$LOG" || { echo "Missing timing evidence: $LOG" >&2; exit 1; }
    echo "Animation timing control completed (no GPU-motion acceptance): $LOG"
    exit 0
fi
for step in 0 1 2 3 4 5 6 7; do
    cp "artifacts/reference/vfx-animation-$step.png" "artifacts/reference/vfx-animation-$RENDERER-$RENDER_THREAD-$step.png"
done
grep -q 'VFX_ANIMATION_GPU_MOTION' "$LOG" || { echo "No GPU motion evidence: $LOG" >&2; exit 1; }
for file in motion-start.png motion.json; do
    cp "artifacts/reference/vfx-animation-$file" "artifacts/reference/vfx-animation-$RENDERER-$RENDER_THREAD-$file"
done
echo "VFX animation passed: $LOG"
