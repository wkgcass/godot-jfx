#!/bin/sh
# macOS Media video using the source-built platform JAR.
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
runtime=""
DRIVER=""
NATIVE=0
SAMPLE="oracle"
while [ $# -gt 0 ]; do
    case "$1" in
        --native) NATIVE=1 ;;
        --driver) DRIVER="${2-}"; shift ;;
        --sample) SAMPLE="$2"; shift ;;
        --runtime) runtime="-runtime" ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ "$NATIVE" -eq 1 ] && [ -n "$DRIVER$runtime" ]; then
    echo "--driver and --runtime require the Godot backend" >&2; exit 2
fi
DRIVER=${DRIVER:-metal}
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
BACKEND=$DRIVER
if [ "$NATIVE" -eq 1 ]; then BACKEND=native-mtl; fi

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

VIDEO=$(./scripts/setup-env.py --sample-path "$SAMPLE")
suffix=""
if [ "$SAMPLE" = lk ]; then suffix="-lk"; fi

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
export GODOT_JFX_MEDIA_CAPTURE="$PWD/artifacts/reference/media-video-$BACKEND$runtime$suffix.png"
LOG="agentdir/logs/media-video-$BACKEND$runtime$suffix.log"
CODE=0
if [ "$NATIVE" -eq 1 ]; then
    set -- "$JDK/bin/java" -Dglass.platform=Mac -Dprism.order=mtl --module-path jfx/build/sdk/lib \
        --add-modules javafx.controls,javafx.media,javafx.swing --enable-native-access=javafx.graphics,javafx.media,ALL-UNNAMED \
        -cp artifacts/reference MediaVideoProbe
else
    set -- python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://media_video.tscn --render-thread safe
fi
run_watchdog "$LOG" 240 "$@" || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'MEDIA_VIDEO_PROBE_PASS' "$LOG" \
    || ! grep -q 'MEDIA_VIDEO_CONTROLS_PASS' "$LOG" \
    || { [ "$NATIVE" -eq 0 ] && ! grep -q 'GODOT_MEDIA_VIDEO_PASS' "$LOG"; } \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Media video failed: $LOG" >&2
    exit 1
fi
echo "Source Media video playback passed: $LOG"
