#!/bin/sh
# macOS equivalent of test-readback.ps1.
# Usage: test-readback.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
#        [--snapshot] [--stop-during-read] [--runtime] [--snapshot-stress]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
SNAPSHOT=0
STOP=0
RUNTIME=0
STRESS=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --snapshot) SNAPSHOT=1 ;;
        --stop-during-read) STOP=1 ;;
        --runtime) RUNTIME=1 ;;
        --snapshot-stress) STRESS=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
if [ "$STRESS" -eq 1 ]; then SNAPSHOT=1; fi
if [ "$SNAPSHOT" -eq 1 ] && [ "$STOP" -eq 1 ]; then
    echo "Snapshot and stop probes are separate modes" >&2
    exit 2
fi

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

EXPORTS="--add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED"
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics $EXPORTS \
    -encoding UTF-8 -d artifacts/reference tests/reference/ReadbackProbe.java || { echo "Readback probe compilation failed" >&2; exit 1; }
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    -encoding UTF-8 -d artifacts/reference tests/reference/SnapshotProbe.java || { echo "Snapshot compilation failed" >&2; exit 1; }

export GODOT_JFX_SNAPSHOT="$SNAPSHOT"
export GODOT_JFX_SNAPSHOT_STRESS="$STRESS"
export GODOT_JFX_READBACK_STOP="$STOP"
SUFFIX=""
[ "$SNAPSHOT" -eq 1 ] && SUFFIX="-snapshot"
[ "$STRESS" -eq 1 ] && SUFFIX="$SUFFIX-stress"
[ "$STOP" -eq 1 ] && SUFFIX="$SUFFIX-stop"
[ "$RUNTIME" -eq 1 ] && SUFFIX="$SUFFIX-runtime"
LOG="$PWD/agentdir/logs/readback-$DRIVER-$RENDER_THREAD$SUFFIX.log"
if [ "$RUNTIME" -eq 1 ]; then
    FIXTURE="$PWD/artifacts/runtime-readback"
    mkdir -p "$FIXTURE"
    cp tests/godot/readback.tscn tests/godot/readback.gd "$FIXTURE/"
    sed 's|res://main.tscn|res://readback.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    CODE=0
    "$PWD/godot/bin/godot.macos.editor.arm64" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Readback runtime fixture import failed: $LOG.import" >&2; exit 1; fi
    CODE=0
    (cd "$FIXTURE" && python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" \
        --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1) || CODE=$?
else
    CODE=0
    python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://readback.tscn \
        --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
fi
if [ "$STOP" -eq 1 ] && ! grep -q 'READBACK_STOP_OBSERVED_PENDING_REQUEST' "$LOG"; then
    echo "Pending readback stop was not exercised: $LOG" >&2
    exit 1
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'READBACK_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_READBACK_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Readback test failed: $LOG" >&2
    exit 1
fi
echo "Readback passed: $LOG"
