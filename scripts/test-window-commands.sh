#!/bin/sh
# macOS equivalent of test-window-commands.ps1.
# Usage: test-window-commands.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -eu
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

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowCommandsProbe.java

LOG="agentdir/logs/window-commands-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://window_commands.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_WINDOW_COMMANDS_PASS' "$LOG" \
    || ! grep -q 'WINDOW_COMMANDS_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Window command test failed: $LOG" >&2
    exit 1
fi
for stage in 0 1 2 3 4 5 6 7; do
    cp "artifacts/reference/window-commands-$stage.png" "artifacts/reference/window-commands-$DRIVER-$RENDER_THREAD-$stage.png"
done
echo "Window commands passed: $LOG"
