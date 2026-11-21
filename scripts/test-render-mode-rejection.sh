#!/bin/sh
# macOS equivalent of test-render-mode-rejection.ps1.
set -u
driver=metal
if [ "$#" -ne 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != --driver ]; then
        echo "Usage: $0 [--driver metal|opengl]" >&2
        exit 2
    fi
    driver=$2
fi
case "$driver" in
    opengl) ;;
    metal) echo "SKIP: OpenGL-only render mode rejection test. Run with --driver opengl."; exit 0 ;;
    *) echo "expected --driver metal or opengl" >&2; exit 2 ;;
esac
cd "$(dirname "$0")/.."

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs

LOG="agentdir/logs/render-mode-rejection.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver opengl --path tests/godot --script res://render_mode_rejection.gd \
    --render-thread separate >"$LOG" 2>&1 || CODE=$?
EXPECTED='JavaFX hosting requires --render-thread safe; separate is unsupported.'
python3 scripts/godot_driver.py --driver "$driver" "$LOG" || exit 1
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'RENDER_MODE_REJECTION_PASS' "$LOG" \
    || ! grep -qF "$EXPECTED" "$LOG"; then
    echo "Render mode rejection failed: $LOG" >&2
    exit 1
fi
ERRORS=$(grep -E '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG" || true)
if [ "$(printf '%s\n' "$ERRORS" | grep -c .)" -ne 1 ] || ! printf '%s' "$ERRORS" | grep -qF "$EXPECTED"; then
    echo "Unexpected diagnostics during rejection: $LOG" >&2
    exit 1
fi
echo "Unsupported render mode rejected: $LOG"
