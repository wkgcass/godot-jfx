#!/bin/sh
# macOS equivalent of test-stage.ps1.
# Usage: test-stage.sh [--driver metal|opengl]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
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
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/StageProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="agentdir/logs/stage-$DRIVER.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://stage.tscn \
    --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_STAGE_PASS' "$LOG" \
    || ! grep -q 'STAGE_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "Stage probe failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-stage.png "artifacts/reference/godot-stage-$DRIVER.png"
cp artifacts/reference/godot-stage-interaction.png "artifacts/reference/godot-stage-interaction-$DRIVER.png"
echo "Stage probe passed: $LOG"
