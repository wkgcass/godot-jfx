#!/bin/sh
# Usage: test-image-cursor.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
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

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/ImageCursorProbe.java

LOG="agentdir/logs/image_cursor-$DRIVER-$RENDER_THREAD$runtime.log"
CODE=0
# On WSLg an uncapped fixture can consume 3000 frames in under 15 seconds.
# Leave the scene's 40-second wall-clock deadline time to report the failing step.
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://image_cursor.tscn \
    --render-thread "$RENDER_THREAD" --max-fps 60 --quit-after 3600 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'IMAGE_CURSOR_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_IMAGE_CURSOR_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Image cursor test failed: $LOG" >&2
    exit 1
fi
echo "Image cursor passed: $LOG"
