#!/bin/sh
# macOS equivalent of test-node-shaders.ps1.
# Usage: test-node-shaders.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
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
    -encoding UTF-8 -d artifacts/reference tests/reference/NodeShaderProbe.java || { echo "Node shader probe compilation failed" >&2; exit 1; }

LOG="agentdir/logs/node-shaders-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://node_shaders.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 4000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_NODE_SHADER_PASS' "$LOG" \
    || ! grep -q 'NODE_SHADER_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "Node shader probe failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-node-shaders.png "artifacts/reference/godot-node-shaders-$DRIVER-$RENDER_THREAD.png"
echo "Node shader probe passed: $LOG"
