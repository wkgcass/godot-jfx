#!/bin/sh
# Usage: test-transparent-stage.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
runtime=""
DRIVER="$native_driver"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --runtime) runtime="-runtime" ;;
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/TransparentStageProbe.java

LOG="agentdir/logs/transparent_stage-$DRIVER-$RENDER_THREAD$runtime.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://transparent_stage.tscn \
    --render-thread "$RENDER_THREAD" >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_TRANSPARENT_STAGE_PASS' "$LOG" \
    || ! grep -q 'TRANSPARENT_STAGE_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:' "$LOG"; then
    echo "Transparent Stage failed: $LOG" >&2
    exit 1
fi
echo "Transparent Stage passed: $LOG"
