#!/bin/sh
# macOS equivalent of test-render-mode-rejection.ps1.
set -u
cd "$(dirname "$0")/.."

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
mkdir -p artifacts/logs

LOG="artifacts/logs/render-mode-rejection.log"
CODE=0
"$GODOT" --path tests/godot --script res://render_mode_rejection.gd \
    --rendering-method gl_compatibility --render-thread separate >"$LOG" 2>&1 || CODE=$?
EXPECTED='JavaFX hosting requires --render-thread safe; separate is unsupported.'
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
