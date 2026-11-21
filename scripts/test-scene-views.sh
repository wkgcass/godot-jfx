#!/bin/sh
# macOS equivalent of test-scene-views.ps1.
# Usage: test-scene-views.sh [--driver metal|opengl]
set -u
cd "$(dirname "$0")/.."

DRIVER="metal"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs artifacts/reference

LOG="agentdir/logs/scene-views-$DRIVER.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://scene_views.tscn \
    --quit-after 3000 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'SCENE_VIEW_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Scene view test failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-scene-view.png "artifacts/reference/godot-scene-view-$DRIVER.png"
echo "Scene view test passed: $LOG"
