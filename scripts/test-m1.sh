#!/bin/sh
# macOS equivalent of test-m1.ps1.
# Usage: test-m1.sh [--renderer gl_compatibility|mobile]
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

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

LOG="artifacts/logs/m1-$RENDERER.log"
# Frame limit prevents an unhandled GDScript error from hanging the test.
# Exit zero alone is insufficient: an explicit PASS is required below.
"$GODOT" --path tests/godot --rendering-method "$RENDERER" --quit-after 300 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'M1_RESULT PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:)' "$LOG"; then
    echo "M1 failed or never completed (exit $CODE). See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-m1.png "artifacts/reference/godot-m1-$RENDERER.png"
cp artifacts/reference/godot-prism-vertices.png "artifacts/reference/godot-prism-vertices-$RENDERER.png"
echo "M1 passed on $RENDERER. Log: $LOG"
