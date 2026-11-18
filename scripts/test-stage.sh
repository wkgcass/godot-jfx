#!/bin/sh
# macOS equivalent of test-stage.ps1.
# Usage: test-stage.sh [--renderer gl_compatibility|mobile]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
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
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/StageProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/stage-$RENDERER.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://stage.tscn \
    --rendering-method "$RENDERER" --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_STAGE_PASS' "$LOG" \
    || ! grep -q 'STAGE_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "Stage probe failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-stage.png "artifacts/reference/godot-stage-$RENDERER.png"
cp artifacts/reference/godot-stage-interaction.png "artifacts/reference/godot-stage-interaction-$RENDERER.png"
echo "Stage probe passed: $LOG"
