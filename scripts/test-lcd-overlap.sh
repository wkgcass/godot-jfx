#!/bin/sh
# macOS equivalent of test-lcd-overlap.ps1.
# Usage: test-lcd-overlap.sh [--driver metal|opengl] [--render-thread safe]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDER_THREAD="safe"
DRIVER="metal"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
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
    -encoding UTF-8 -d artifacts/reference tests/reference/LcdOverlapProbe.java || { echo "LCD probe compilation failed" >&2; exit 1; }

export GODOT_JFX_JDK="$JDK"
for mode in 0 1; do
    export GODOT_JFX_LCD_SCREEN="$mode"
    LOG="agentdir/logs/lcd-overlap-$RENDER_THREAD-$mode.log"
    CODE=0
    python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://lcd_overlap.tscn \
        --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ] \
        || ! grep -q 'LCD_OVERLAP_JAVA_PASS' "$LOG" \
        || ! grep -q 'LCD_OVERLAP_CAPTURE_PASS' "$LOG" \
        || { [ "$mode" -eq 1 ] && ! grep -q 'LCD_OVERLAP_DIFF_PASS' "$LOG"; } \
        || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
        echo "LCD overlap failed: $LOG" >&2
        exit 1
    fi
done
echo "LCD overlap passed: $RENDER_THREAD (Godot LCDBuffer vs screen sampling)"
