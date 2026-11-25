#!/bin/sh
# macOS equivalent of test-nested-menu.ps1.
# Usage: test-nested-menu.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
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

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/NestedMenuProbe.java

LOG="agentdir/logs/nested-menu-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://nested_menu.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_NESTED_MENU_PASS' "$LOG" \
    || ! grep -q 'NESTED_MENU_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Nested menu test failed: $LOG" >&2
    exit 1
fi
cp artifacts/reference/nested-menu.png "artifacts/reference/nested-menu-$DRIVER-$RENDER_THREAD.png"
echo "Nested menu passed: $LOG"
