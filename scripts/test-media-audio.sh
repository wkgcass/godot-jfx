#!/bin/sh
# macOS equivalent of test-media-audio.ps1.
# Usage: test-media-audio.sh [--renderer mobile|gl_compatibility] [--codec wav|mp3|aiff|all]
# The Windows fixture tool (tests/native/make_audio_fixture.cpp) uses Media
# Foundation, so the macOS port generates the same 2 s 44100 Hz mono signal
# with system tools: python3 writes the silent WAV, ffmpeg/libmp3lame encodes
# the MP3 tone, and afconvert wraps the tone in an AIFF container. --runtime
# needs the Windows release-template fixture layout and is not ported.
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
CODEC="wav"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --codec) CODEC="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in mobile|gl_compatibility) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$CODEC" in wav|mp3|aiff|all) ;; *) echo "invalid codec: $CODEC" >&2; exit 2 ;; esac
if [ "$RUNTIME" -eq 1 ]; then
    echo "--runtime is not ported to macOS yet" >&2
    exit 2
fi

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media \
    -d artifacts/reference tests/reference/MediaAudioProbe.java \
    || { echo "Media audio probe compilation failed" >&2; exit 1; }

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

case "$CODEC" in all) CODECS="wav mp3 aiff" ;; *) CODECS="$CODEC" ;; esac
export GODOT_JFX_JDK="$JDK"
for kind in $CODECS; do
    media_file=$(./scripts/prepare-audio-fixtures.py "$kind")
    case "$kind" in
        mp3) tolerance=300 ;;
        *) tolerance=50 ;;
    esac
    codec_tag=""
    [ "$kind" = "wav" ] || codec_tag="-$kind"
    LOG="agentdir/logs/media-audio-$RENDERER$codec_tag.log"
    CODE=0
    GODOT_JFX_MEDIA_FILE="$PWD/$media_file" GODOT_JFX_MEDIA_EXPECT_MS=2000 GODOT_JFX_MEDIA_TOLERANCE_MS=$tolerance \
        run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --path tests/godot res://media_audio.tscn \
        --rendering-method "$RENDERER" --render-thread safe || CODE=$?
    if [ "$CODE" -ne 0 ] \
        || ! grep -q 'MEDIA_AUDIO_PROBE_PASS' "$LOG" \
        || ! grep -q 'GODOT_MEDIA_AUDIO_PASS' "$LOG" \
        || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)|uncaught:' "$LOG"; then
        echo "Media audio failed ($kind): $LOG" >&2
        exit 1
    fi
    echo "Source Media audio playback passed ($kind): $LOG"
done
