#!/bin/sh
# macOS equivalent of test-ime.ps1. The -SpacedClick variant is folded into a
# flag for parity; default matches the ps1 default run.
# Usage: test-ime.sh [--driver metal|opengl] [--spaced-click] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
SPACED_CLICK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --spaced-click) SPACED_CLICK=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/ImeProbe.java

export GODOT_JFX_IME_SPACED_CLICK="$SPACED_CLICK"
SUFFIX=""
if [ "$SPACED_CLICK" = "1" ]; then SUFFIX="-spaced"; fi
LOG="agentdir/logs/ime-$DRIVER$SUFFIX.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://ime.tscn \
    --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_IME_PASS' "$LOG" \
    || ! grep -q 'IME_PROBE_PASS' "$LOG" \
    || ! grep -q 'IME_MOUSE_ORDER_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "IME probe failed: $LOG" >&2
    exit 1
fi
echo "IME probe passed: $LOG"
