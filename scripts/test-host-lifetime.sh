#!/bin/sh
# macOS equivalent of test-host-lifetime.ps1.
# Usage: test-host-lifetime.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
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

export GODOT_JFX_JDK="$JDK"
SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/artifacts/logs/host-lifetime-$RENDERER-$RENDER_THREAD$SUFFIX.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    [ -x "$TEMPLATE" ] || { echo "Godot template not found: $TEMPLATE" >&2; exit 1; }
    # Release templates load their adjacent project, without --path overrides.
    FIXTURE="$PWD/artifacts/runtime-host-lifetime"
    mkdir -p "$FIXTURE"
    cp "$TEMPLATE" tests/godot/host_lifetime.tscn tests/godot/host_lifetime_test.gd "$FIXTURE/"
    sed 's|res://main.tscn|res://host_lifetime.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$GODOT" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Runtime fixture import failed: $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 "./godot.macos.template_release.arm64" \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000) || CODE=$?
else
    run_watchdog "$LOG" 240 "$GODOT" --path tests/godot res://host_lifetime.tscn \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000 || CODE=$?
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_HOST_LIFETIME_PASS' "$LOG" \
    || ! grep -q 'HOST_LIFETIME_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Host lifetime test failed: $LOG" >&2
    exit 1
fi
echo "Host lifetime passed: $LOG"
