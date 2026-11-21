#!/bin/sh
# macOS equivalent of test-fxml.ps1.
# Usage: test-fxml.sh [--driver metal|opengl] [--render-thread safe] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
DRIVER="metal"
RENDER_THREAD="safe"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference/fxml agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.fxml \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/FXMLProbe.java || { echo "FXML probe compilation failed" >&2; exit 1; }
cp tests/reference/fxml/* artifacts/reference/fxml/

# run_watchdog <log> <seconds> <command...>: the FXML scene quits by itself,
# so bound the wait instead of relying on --quit-after.
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

export GODOT_JFX_JDK="$JDK"
SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/agentdir/logs/fxml-$DRIVER-$RENDER_THREAD$SUFFIX.log"
if [ "$RUNTIME" -eq 1 ]; then
    FIXTURE="$PWD/artifacts/runtime-fxml"
    mkdir -p "$FIXTURE"
    cp tests/godot/fxml.gd tests/godot/fxml.tscn "$FIXTURE/"
    sed 's|res://main.tscn|res://fxml.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    CODE=0
    "$PWD/godot/bin/godot.macos.editor.arm64" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "FXML runtime import failed: $LOG.import" >&2; exit 1; fi
    CODE=0
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" \
        --render-thread "$RENDER_THREAD") || CODE=$?
else
    CODE=0
    run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://fxml.tscn \
        --render-thread "$RENDER_THREAD" || CODE=$?
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_FXML_PASS' "$LOG" \
    || ! grep -q 'FXML_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:' "$LOG"; then
    echo "FXML failed: $LOG" >&2
    exit 1
fi
for step in 0 1 2 3; do
    cp "artifacts/reference/fxml-$step.png" "artifacts/reference/fxml-$DRIVER-$RENDER_THREAD$SUFFIX-$step.png"
done
echo "FXML passed: $LOG"
