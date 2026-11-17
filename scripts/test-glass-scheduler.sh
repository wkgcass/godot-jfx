#!/bin/sh
# macOS equivalent of test-glass-scheduler.ps1.
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/GlassSchedulerProbe.java \
    || { echo "GlassSchedulerProbe compilation failed" >&2; exit 1; }

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/m2-glass-scheduler.log"
CODE=0
# Headroom doubled over the Windows run: the frame budget also covers JVM
# teardown, and this lightweight scene iterates faster on the macOS editor.
"$GODOT" --path tests/godot res://scheduler.tscn --quit-after 6000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'M2_GLASS_SCHEDULER_PASS' "$LOG" \
    || ! grep -q 'GLASS_SCHEDULER_PASS:' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG"; then
    echo "Glass scheduler test failed or incomplete (exit $CODE). See $LOG" >&2
    exit 1
fi
echo "Glass scheduler test passed. Log: $LOG"
