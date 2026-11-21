#!/bin/sh
# macOS equivalent of test-glass-scheduler.ps1.
set -u
cd "$(dirname "$0")/.."

DRIVER="metal"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/GlassSchedulerProbe.java \
    || { echo "GlassSchedulerProbe compilation failed" >&2; exit 1; }

export GODOT_JFX_JDK="$JDK"
LOG="agentdir/logs/m2-glass-scheduler.log"
CODE=0
# Headroom doubled over the Windows run: the frame budget also covers JVM
# teardown, and this lightweight scene iterates faster on macOS.
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://scheduler.tscn --quit-after 6000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'M2_GLASS_SCHEDULER_PASS' "$LOG" \
    || ! grep -q 'GLASS_SCHEDULER_PASS:' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG"; then
    echo "Glass scheduler test failed or incomplete (exit $CODE). See $LOG" >&2
    exit 1
fi
echo "Glass scheduler test passed. Log: $LOG"
