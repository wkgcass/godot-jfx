#!/bin/sh
# macOS equivalent of test-host-lifetime.ps1.
# Usage: test-host-lifetime.sh [--driver metal|opengl] [--render-thread safe] [--runtime] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
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
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    -encoding UTF-8 -d artifacts/reference tests/reference/HostLifetimeProbe.java \
    || { echo "Host lifetime probe compilation failed" >&2; exit 1; }

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

SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/agentdir/logs/host-lifetime-$DRIVER-$RENDER_THREAD$SUFFIX.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    # Import this isolated project before passing its directory to the library.
    FIXTURE="$PWD/artifacts/runtime-host-lifetime"
    mkdir -p "$FIXTURE"
    cp tests/godot/host_lifetime.tscn tests/godot/host_lifetime_test.gd "$FIXTURE/"
    sed 's|res://main.tscn|res://host_lifetime.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$PWD/godot/bin/godot.macos.editor.arm64" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Runtime fixture import failed: $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" \
        --render-thread "$RENDER_THREAD" --quit-after 10000) || CODE=$?
else
    run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://host_lifetime.tscn \
        --render-thread "$RENDER_THREAD" --quit-after 10000 || CODE=$?
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_HOST_LIFETIME_PASS' "$LOG" \
    || ! grep -q 'HOST_LIFETIME_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Host lifetime test failed: $LOG" >&2
    exit 1
fi
echo "Host lifetime passed: $LOG"
