#!/bin/sh
# macOS equivalent of test-shader-cache.ps1.
# Usage: test-shader-cache.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

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
mkdir -p artifacts/logs

export GODOT_JFX_INSTANCE_UNIFORMS=1
LOG="artifacts/logs/shader-cache-$RENDERER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://shader_cache.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'SHADER_CACHE_PASS' "$LOG" \
    || ! grep -q 'SAMPLER_MATERIAL_COLLISION_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Shader cache test failed. See $LOG" >&2
    exit 1
fi
echo "Shader cache test passed: $LOG"
