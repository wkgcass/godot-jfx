#!/bin/sh
# macOS equivalent of test-node-shader-dirty.ps1.
# Usage: test-node-shader-dirty.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    -encoding UTF-8 -d artifacts/reference tests/reference/NodeShaderDirtyProbe.java

LOG="agentdir/logs/node-shader-dirty-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://node_shader_dirty.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_NODE_SHADER_DIRTY_PASS' "$LOG" \
    || ! grep -q 'NODE_SHADER_DIRTY_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "Node shader probe failed. See $LOG" >&2
    exit 1
fi
for phase in 0 1; do
    cp "artifacts/reference/node-shader-dirty-$phase.png" "artifacts/reference/node-shader-dirty-$DRIVER-$RENDER_THREAD-$phase.png"
done
echo "Node shader dirty-region probe passed: $LOG"
