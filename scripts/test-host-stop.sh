#!/bin/sh
# macOS equivalent of test-host-stop.ps1.
# Usage: test-host-stop.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RENDER_THREAD="safe"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

GODOT="./godot/bin/godot.macos.editor.arm64"
TEMPLATE="./godot/bin/godot.macos.template_release.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.impl.ps=ALL-UNNAMED \
    -d artifacts/reference tests/reference/HostStopProbe.java \
    || { echo "Host stop probe compilation failed" >&2; exit 1; }

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
LOG="$PWD/artifacts/logs/host-stop-$RENDERER-$RENDER_THREAD$SUFFIX.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    [ -x "$TEMPLATE" ] || { echo "Godot template not found: $TEMPLATE" >&2; exit 1; }
    FIXTURE="$PWD/artifacts/runtime-host-stop"
    mkdir -p "$FIXTURE"
    cp "$TEMPLATE" tests/godot/host_stop.gd tests/godot/host_stop.tscn "$FIXTURE/"
    sed 's|res://main.tscn|res://host_stop.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$GODOT" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Host stop runtime import failed: $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 "./godot.macos.template_release.arm64" \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD") || CODE=$?
else
    run_watchdog "$LOG" 240 "$GODOT" --path tests/godot res://host_stop.tscn \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" || CODE=$?
fi
# Covers native/Glass destruction, JVM completion and renderer/pool cleanup,
# and rejects leaked cancellation exceptions as well as ordinary failures.
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'HOST_STOP_NATIVE_WINDOWS_PASS' "$LOG" \
    || ! grep -q 'HOST_STOP_APPLICATION_RETURNED' "$LOG" \
    || ! grep -q 'HOST_STOP_GLASS_PEERS_CLOSED' "$LOG" \
    || ! grep -q 'HOST_STOP_PIPELINE_DISPOSED pool_bytes=0' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error)|RenderJob\.run: internal exception|QuantumRenderer-[0-9]+ uncaught:)|GodotHostStoppedException' "$LOG"; then
    echo "Host stop native-window test failed: $LOG" >&2
    exit 1
fi
echo "Host stop native-window test passed: $LOG"
