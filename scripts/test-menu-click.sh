#!/bin/sh
# macOS equivalent of test-menu-click.ps1.
# Usage: test-menu-click.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
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

VFX_BASE="artifacts/vfx"
VFX_CP="$VFX_BASE/classes/java/main:$VFX_BASE/classes/java/test:$VFX_BASE/resources/main:$VFX_BASE/resources/test"
for jar in "$VFX_BASE"/dependencies/*.jar; do
    [ -e "$jar" ] || continue
    VFX_CP="$VFX_CP:$jar"
done

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    -cp "$VFX_CP" -encoding UTF-8 -d artifacts/reference tests/reference/MenuClickProbe.java

LOG="agentdir/logs/menu-click-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://menu_click.tscn \
    --render-thread "$RENDER_THREAD" >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'MENU_CLICK_PASS' "$LOG" \
    || ! grep -q 'GODOT_MENU_CLICK_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:' "$LOG"; then
    echo "Menu click probe failed. See $LOG" >&2
    exit 1
fi
echo "Menu click probe passed: $LOG"
