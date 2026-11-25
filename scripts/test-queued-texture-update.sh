#!/bin/sh
# macOS equivalent of test-queued-texture-update.ps1.
# Usage: test-queued-texture-update.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
#        [--batch-boundary] [--viewport-state]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
RENDER_THREAD="safe"
BATCH=0
VIEWPORT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --batch-boundary) BATCH=1 ;;
        --viewport-state) VIEWPORT=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
if [ "$BATCH" -eq 1 ] && [ "$VIEWPORT" -eq 1 ]; then
    echo "Choose one fixture mode" >&2
    exit 2
fi

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

export GODOT_JFX_DIRECT_OFFSCREEN="1"
export GODOT_JFX_TEST_VIEWPORT_STATE="$VIEWPORT"
[ "$VIEWPORT" -eq 1 ] && export GODOT_JFX_INSTANCE_UNIFORMS="1"
export GODOT_JFX_TEST_BATCH_BOUNDARY="$BATCH"

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/QueuedTextureUpdateProbe.java || { echo "Queued texture update probe compilation failed" >&2; exit 1; }
if [ "$BATCH" -eq 1 ]; then
    export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} --add-opens=javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED"
fi

SUFFIX=""
[ "$BATCH" -eq 1 ] && SUFFIX="-boundary"
[ "$VIEWPORT" -eq 1 ] && SUFFIX="$SUFFIX-viewport-state"
LOG="agentdir/logs/queued-texture-update-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://queued_texture_update.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if ! grep -q '^SAME_PASS_SAMPLER_REVISION_PASS pixels=128$' "$LOG"; then
    echo "Same-pass sampler revision check incomplete: $LOG" >&2
    exit 1
fi
if ! grep -q 'PARTIAL_TEXTURE_UPDATE_PASS' "$LOG"; then
    echo "Partial texture update check incomplete: $LOG" >&2
    exit 1
fi
if [ "$VIEWPORT" -eq 1 ] && ! grep -q 'VIEWPORT_STATE_PASS' "$LOG"; then
    echo "Viewport state check incomplete: $LOG" >&2
    exit 1
fi
if [ "$BATCH" -eq 1 ] && { ! grep -q 'BATCH_BOUNDARY_PIXELS_PASS' "$LOG" || ! grep -q 'BATCH_BYTE_BOUNDARY_PIXELS_PASS' "$LOG"; }; then
    echo "Batch boundary pixel check incomplete: $LOG" >&2
    exit 1
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_QUEUED_TEXTURE_UPDATE_PASS' "$LOG" \
    || ! grep -q 'QUEUED_TEXTURE_UPDATE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Queued texture update test failed: $LOG" >&2
    exit 1
fi
echo "Queued texture update passed: $LOG"
