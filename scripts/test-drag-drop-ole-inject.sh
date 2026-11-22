#!/bin/sh
# macOS equivalent of test-drag-drop-ole-inject.ps1.
#
# Same fixture and assertions as Windows: the GDScript scene calls
# JavaFXHost.simulate_external_drop, which feeds the payload through the
# module's own pasteboard writer and the inbound drag delegate instead of a
# physical cross-process gesture. The macOS backend publishes the payload on a
# private NSPasteboard (NSFilenamesPboardType keeps the verbatim Windows-style
# fixture paths) and drives the same enter/drop state machine the
# NSDraggingDestination callbacks use.
#
# Usage: test-drag-drop-ole-inject.sh [--driver metal|opengl] [--render-thread safe] [--timeout] [--jdk DIRECTORY]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
TIMEOUT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --timeout) TIMEOUT=1 ;;
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
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/OleInjectProbe.java

SUFFIX=""
[ "$TIMEOUT" = 1 ] && SUFFIX="-timeout"
LOG="agentdir/logs/ole-inject-$DRIVER-$RENDER_THREAD$SUFFIX.log"

CODE=0
(
    export GODOT_JFX_OLE_TIMEOUT="$TIMEOUT"
    python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://ole_inject.tscn \
        --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1
) || CODE=$?

if [ "$TIMEOUT" = 1 ] && ! grep -q 'OLE_TIMEOUT_CANCEL_PASS' "$LOG"; then
    echo "OLE timeout checks failed: $LOG" >&2
    exit 1
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_OLE_INJECT_PASS' "$LOG" \
    || ! grep -q 'OLE_INJECT_PROBE_PASS' "$LOG" \
    || ! grep -qi 'OLE_INJECT_DROP ok=True' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "OLE inject test failed or incomplete (exit $CODE): $LOG" >&2
    exit 1
fi
echo "OLE inject test passed. Log: $LOG"
