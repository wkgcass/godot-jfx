#!/bin/sh
# macOS Media churn using the source-built platform JAR.
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
runtime=""
DRIVER=""
NATIVE=0
CYCLES=24
SETTLE=0
AUDIO_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --native) NATIVE=1 ;;
        --driver) DRIVER="${2-}"; shift ;;
        --cycles) CYCLES="$2"; shift ;;
        --settle-seconds) SETTLE="$2"; shift ;;
        --audio-only) AUDIO_ONLY=1 ;;
        --runtime) runtime="-runtime" ;;
        --handle-types|--providers)
            echo "$1 requires Windows process APIs" >&2; exit 2 ;;
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
[ "$CYCLES" -ge 24 ] && [ "$CYCLES" -le 240 ] || { echo "invalid cycles: $CYCLES" >&2; exit 2; }
case "$SETTLE" in 0|30|60) ;; *) echo "invalid settle seconds: $SETTLE" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

echo "Media churn backend: $BACKEND"
if [ "$AUDIO_ONLY" -eq 1 ]; then
    VIDEO=$(./scripts/prepare-audio-fixtures.py churn)
else
    VIDEO=$(./scripts/setup-env.py --sample-path oracle)
fi

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media \
    -d artifacts/reference \
    tests/reference/CurrentProcessHandles.java tests/reference/CurrentProcessMemory.java tests/reference/MediaChurnProbe.java \
    || { echo "Media churn compilation failed" >&2; exit 1; }

if [ "$AUDIO_ONLY" -eq 1 ]; then echo "Media churn fixture: PCM audio only"; else echo "Media churn fixture: MP4 audio/video"; fi

SUFFIX=""
[ "$AUDIO_ONLY" -eq 1 ] && SUFFIX="$SUFFIX-pcm"
SUFFIX="$SUFFIX-cycles$CYCLES-process"
[ "$SETTLE" -gt 0 ] && SUFFIX="$SUFFIX-idle${SETTLE}s"

LOG="agentdir/logs/media-churn-$BACKEND$runtime$SUFFIX.log"

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
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Xmx256m --enable-native-access=ALL-UNNAMED"
export GODOT_JFX_MEDIA_CYCLES="$CYCLES"
export GODOT_JFX_MEDIA_SETTLE="$SETTLE"
export GODOT_JFX_MEDIA_PROVIDERS=0
export GODOT_JFX_MEDIA_HANDLES=0
export GODOT_JFX_MEDIA_AUDIO_ONLY="$AUDIO_ONLY"

# The Godot fixture owns its timeout (30s + 6s/cycle + settle) and shutdown.
CODE=0
if [ "$NATIVE" -eq 1 ]; then
    set -- "$JDK/bin/java" -Dglass.platform=Mac -Dprism.order=mtl --module-path jfx/build/sdk/lib \
        --add-modules javafx.controls,javafx.media --enable-native-access=javafx.graphics,javafx.media,ALL-UNNAMED \
        -cp artifacts/reference MediaChurnProbe
else
    set -- python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://media_churn.tscn --render-thread safe
fi
run_watchdog "$LOG" $((60 + CYCLES * 7 + SETTLE + 60)) "$@" || CODE=$?

EXPECTED_IDLE=$((1 + SETTLE / 10))
REPORT="artifacts/reference/media-churn-$BACKEND$runtime$SUFFIX.json"
PASS=0
python3 - "$LOG" "$REPORT" "$CODE" "$CYCLES" "$EXPECTED_IDLE" "$BACKEND" "$SETTLE" "$AUDIO_ONLY" "${runtime:+1}" <<'EOF' || PASS=$?
import json, re, sys
log_path, report_path = sys.argv[1:3]
code, cycles, expected_idle = map(int, sys.argv[3:6])
driver = sys.argv[6]
settle, audio_only = map(int, sys.argv[7:9])
runtime = bool(sys.argv[9])
output = open(log_path, encoding="utf-8", errors="replace").read()
native = [json.loads(m.group(1)) for m in re.finditer(r"(?m)^MEDIA_CHURN_SAMPLE (\{[^\r\n]+\})", output)]
java = [{"cycle": int(c), "heap_used": int(h), "gc_count": int(g)} for c, h, g in
        re.findall(r"MEDIA_CHURN_JAVA cycle=(\d+) heap_used=(\d+) gc_count=(\d+)", output)]
sample_re = r"cycle=(\d+) pid=(\d+) private_bytes=(\d+) working_set=(\d+) handles=(\d+) elapsed_ms=(\d+) java_threads=(\d+)"
def samples(prefix):
    return [{"cycle": int(c), "pid": int(p), "private_bytes": int(pb), "working_set": int(ws),
             "handles": int(h), "elapsed_ms": int(e), "java_threads": int(t)}
            for c, p, pb, ws, h, e, t in re.findall(prefix + " " + sample_re, output)]
process_samples, idle_samples = samples("MEDIA_CHURN_PROCESS"), samples("MEDIA_CHURN_IDLE")
passed = (code == 0 and "MEDIA_CHURN_PROBE_PASS" in output and (driver == "native-mtl" or
          ("GODOT_MEDIA_CHURN_PASS" in output and len(native) == cycles))
          and len(java) == cycles and len(process_samples) == cycles
          and len(idle_samples) == expected_idle
          and not re.search(r"(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|OutOfMemoryError|uncaught:", output))
report = {"aac_registration_stable": None, "providers": False, "audio_only": bool(audio_only),
          "handle_types": False, "playback_and_cleanup_passed": passed,
          "resource_growth_acceptance": "requires separate trend analysis", "cycles": cycles,
          "runtime": bool(runtime), "native_d3d": False, "native_mtl": driver == "native-mtl", "driver": driver, "settle_seconds": settle,
          "idle_samples": idle_samples, "forced_gc": False, "heap_limit_mib": 256,
          "process_memory_sampled": True, "process_samples": process_samples,
          "static_memory_available": any(n.get("static_bytes", 0) > 0 for n in native),
          "native_samples": native, "java_samples": java}
with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
sys.exit(0 if passed else 1)
EOF
if [ "$PASS" -ne 0 ]; then
    echo "Media churn failed: $LOG" >&2
    exit 1
fi
echo "Media churn passed: $LOG"
