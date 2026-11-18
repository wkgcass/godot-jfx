#!/bin/sh
# macOS equivalent of test-mesh-transform.ps1.
# Usage: test-mesh-transform.sh [--renderer gl_compatibility|mobile] [--cache-pressure]
set -u
cd "$(dirname "$0")/.."

RENDERER="gl_compatibility"
CACHE_PRESSURE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --cache-pressure) CACHE_PRESSURE=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p artifacts/logs

SUFFIX=""
if [ "$CACHE_PRESSURE" -eq 1 ]; then SUFFIX="-cache-pressure"; fi
LOG="artifacts/logs/mesh-transform-$RENDERER$SUFFIX.log"

# Frame limit prevents an unhandled GDScript error from hanging the test.
# Exit zero alone is insufficient: an explicit PASS is required below.
if [ "$CACHE_PRESSURE" -eq 1 ]; then
    env GODOT_JFX_MESH_CACHE_PRESSURE=1 GODOT_JFX_MESH_CACHE=1 \
        python3 "$FIXTURE_LAUNCHER" --path tests/godot res://mesh_transform_probe.tscn \
        --rendering-method "$RENDERER" --quit-after 300 > "$LOG" 2>&1
else
    env GODOT_JFX_MESH_CACHE_PRESSURE=0 \
        python3 "$FIXTURE_LAUNCHER" --path tests/godot res://mesh_transform_probe.tscn \
        --rendering-method "$RENDERER" --quit-after 300 > "$LOG" 2>&1
fi
CODE=$?
if [ "$CACHE_PRESSURE" -eq 1 ] && { ! grep -q 'SHARED_TARGET_MESH_CACHE_PASS' "$LOG" || ! grep -q 'SHARED_TARGET_MESH_RELEASE_PASS' "$LOG"; }; then
    echo "Shared target cache check missing: $LOG" >&2
    exit 1
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'MESH_TRANSFORM_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:)' "$LOG"; then
    echo "Mesh transform probe failed or never completed (exit $CODE). See $LOG" >&2
    exit 1
fi
echo "Mesh transform probe passed on $RENDERER. Log: $LOG"
