#!/bin/sh
# macOS equivalent of test-glass-window.ps1.
# Usage: test-glass-window.sh [--driver metal|opengl] [--runtime] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
RUNTIME=0
DRIVER="$native_driver"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/GlassWindowProbe.java \
    || { echo "GlassWindowProbe compilation failed" >&2; exit 1; }

run_watchdog() {
    wlog="$1"; limit="$2"; shift 2
    "$@" >"$wlog" 2>&1 &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$limit" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wcode=0
    wait "$pid" || wcode=$?
    return "$wcode"
}

LOG="$PWD/agentdir/logs/m2-glass-window.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    LOG="$PWD/agentdir/logs/m2-glass-window-runtime.log"
    FIXTURE="$PWD/artifacts/runtime-window"
    mkdir -p "$FIXTURE"
    cp tests/godot/window.tscn tests/godot/window_test.gd "$FIXTURE/"
    sed 's|res://main.tscn|res://window.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$PWD/godot/bin/$source_editor" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Runtime fixture import failed. See $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" \
        --quit-after 3000) || CODE=$?
else
    run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://window.tscn \
        --quit-after 3000 || CODE=$?
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'M2_GLASS_WINDOW_PASS' "$LOG" \
    || ! grep -q 'GLASS_WINDOW_PASS:' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG"; then
    echo "Glass window test failed or incomplete (exit $CODE). See $LOG" >&2
    exit 1
fi
echo "Glass window test passed. Log: $LOG"
