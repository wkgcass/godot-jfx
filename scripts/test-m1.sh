#!/bin/sh
# macOS equivalent of test-m1.ps1.
# Usage: test-m1.sh [--driver metal|opengl]
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
mkdir -p artifacts/reference agentdir/logs

LOG="agentdir/logs/m1-$DRIVER.log"
# Frame limit prevents an unhandled GDScript error from hanging the test.
# Exit zero alone is insufficient: an explicit PASS is required below.
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot --quit-after 300 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! python3 scripts/godot_driver.py --driver "$DRIVER" "$LOG" \
    || ! grep -q 'M1_RESULT PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:)' "$LOG"; then
    echo "M1 failed or never completed (exit $CODE). See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-m1.png "artifacts/reference/godot-m1-$DRIVER.png"
cp artifacts/reference/godot-prism-vertices.png "artifacts/reference/godot-prism-vertices-$DRIVER.png"
echo "M1 passed on $DRIVER. Log: $LOG"
