#!/bin/sh
# macOS equivalent of test-media-video.ps1. The -NativeD3D and -Runtime modes
# are Windows-only and are not ported; the scene fixture keeps the same
# checks.
# Usage: test-media-video.sh [--renderer mobile|gl_compatibility]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --runtime|--native-d3d) echo "$1 is not ported to macOS" >&2; exit 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in mobile|gl_compatibility) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

VIDEO="artifacts/reference/media-oracle-sample.mp4"
if [ ! -f "$VIDEO" ]; then
    curl -fL 'https://download.oracle.com/otndocs/products/javafx/oow2010-2.mp4' -o "$VIDEO"
fi
HASH=$(shasum -a 256 "$VIDEO" | cut -d' ' -f1)
[ "$HASH" = "a6b3928991253a7828052612c8b6cec25f5de3648a361f92e5c2ece9a37d7d34" ] \
    || { echo "Video fixture checksum differs: $HASH" >&2; exit 1; }

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media,javafx.swing \
    -d artifacts/reference tests/reference/MediaVideoProbe.java \
    || { echo "Media video probe compilation failed" >&2; exit 1; }

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
export GODOT_JFX_MEDIA_FILE="$PWD/$VIDEO"
export GODOT_JFX_MEDIA_CAPTURE="$PWD/artifacts/reference/media-video-$RENDERER.png"
LOG="artifacts/logs/media-video-$RENDERER.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --path tests/godot res://media_video.tscn \
    --rendering-method "$RENDERER" --render-thread safe || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'MEDIA_VIDEO_PROBE_PASS' "$LOG" \
    || ! grep -q 'MEDIA_VIDEO_CONTROLS_PASS' "$LOG" \
    || ! grep -q 'GODOT_MEDIA_VIDEO_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Media video failed: $LOG" >&2
    exit 1
fi
echo "Source Media video playback passed: $LOG"
