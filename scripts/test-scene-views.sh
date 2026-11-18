#!/bin/sh
# macOS equivalent of test-scene-views.ps1.
# Usage: test-scene-views.sh [--renderer gl_compatibility|mobile]
set -u
cd "$(dirname "$0")/.."

RENDERER="gl_compatibility"
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p artifacts/logs artifacts/reference

LOG="artifacts/logs/scene-views-$RENDERER.log"
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://scene_views.tscn \
    --rendering-method "$RENDERER" --quit-after 3000 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'SCENE_VIEW_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Scene view test failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-scene-view.png "artifacts/reference/godot-scene-view-$RENDERER.png"
echo "Scene view test passed: $LOG"
