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
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media \
    -d artifacts/reference tests/reference/MediaAudioProbe.java \
    || { echo "Media audio probe compilation failed" >&2; exit 1; }

# new_audio_fixture <wav|mp3|aiff>: prints the fixture path. Mirrors the
# Windows tool's 2 s 440 Hz tone (WAV stays the silent PCM fixture) and the
# "verified before use" semantics via ffprobe stream checks.
new_audio_fixture() {
    kind="$1"
    if [ "$kind" = "wav" ]; then
        wave="artifacts/reference/media-silence.wav"
        python3 -c 'import wave,sys; w=wave.open(sys.argv[1],"wb"); w.setparams((1,2,44100,0,"NONE","not compressed")); w.writeframes(bytes(44100*2*2)); w.close()' "$PWD/$wave" \
            || { echo "PCM fixture generation failed" >&2; exit 1; }
        printf '%s\n' "$PWD/$wave"
        return
    fi
    tone_wav="artifacts/reference/media-tone-src.wav"
    python3 - "$PWD/$tone_wav" <<'EOF' || { echo "Tone PCM generation failed" >&2; exit 1; }
import wave, sys, math, struct
w = wave.open(sys.argv[1], "wb")
w.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
frames = b"".join(struct.pack("<h", int(12000.0 * math.sin(2.0 * math.pi * 440.0 * i / 44100))) for i in range(44100 * 2))
w.writeframes(frames)
w.close()
EOF
    output="artifacts/reference/media-tone.$kind"
    fixlog="artifacts/logs/audio-fixture-$kind.log"
    if [ "$kind" = "mp3" ]; then
        command -v ffmpeg >/dev/null || { echo "ffmpeg is required to encode the MP3 fixture on macOS" >&2; exit 1; }
        ffmpeg -y -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" \
            -ac 1 -c:a libmp3lame "$PWD/$output" >"$fixlog" 2>&1 \
            || { echo "Audio fixture generation failed (mp3): $fixlog" >&2; exit 1; }
    else
        # AIFF stores big-endian PCM; LEI16 is rejected by afconvert here.
        afconvert -f AIFF -d BEI16@44100 -c 1 "$PWD/$tone_wav" "$PWD/$output" >"$fixlog" 2>&1 \
            || { echo "Audio fixture generation failed (aiff): $fixlog" >&2; exit 1; }
    fi
    rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$PWD/$output" 2>>"$fixlog" || true)
    [ "$rate" = "44100" ] || { echo "Encoded fixture verification incomplete ($kind): sample rate $rate" >&2; exit 1; }
    echo "MAKE_AUDIO_FIXTURE_PASS codec=$kind rate=44100 seconds=2" >>"$fixlog"
    printf '%s\n' "$PWD/$output"
}

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
    media_file=$(new_audio_fixture "$kind")
    case "$kind" in
        mp3) tolerance=300 ;;
        *) tolerance=50 ;;
    esac
    codec_tag=""
    [ "$kind" = "wav" ] || codec_tag="-$kind"
    LOG="artifacts/logs/media-audio-$RENDERER$codec_tag.log"
    CODE=0
    GODOT_JFX_MEDIA_FILE="$media_file" GODOT_JFX_MEDIA_EXPECT_MS=2000 GODOT_JFX_MEDIA_TOLERANCE_MS=$tolerance \
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
