#!/bin/sh
# macOS equivalent of test-media-churn.ps1. The -NativeD3D comparison and the
# -HandleTypes/-Providers handle-census modes depend on Windows process APIs
# and are not ported; the packaged-engine churn test keeps the same checks. Process
# samples come from the probe's own proc_pid_rusage/proc_pidinfo metrics.
# Usage: test-media-churn.sh [--driver metal|opengl] [--cycles 24..240]
#        [--settle-seconds 0|30|60] [--audio-only]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
DRIVER="metal"
CYCLES=24
SETTLE=0
AUDIO_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --cycles) CYCLES="$2"; shift ;;
        --settle-seconds) SETTLE="$2"; shift ;;
        --audio-only) AUDIO_ONLY=1 ;;
        --handle-types|--providers|--runtime|--native-d3d)
            echo "$1 is not ported to macOS (Windows-only process APIs / fixture layout)" >&2; exit 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
[ "$CYCLES" -ge 24 ] && [ "$CYCLES" -le 240 ] || { echo "invalid cycles: $CYCLES" >&2; exit 2; }
case "$SETTLE" in 0|30|60) ;; *) echo "invalid settle seconds: $SETTLE" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

echo "Media churn backend: Java / Glass-Godot / Prism-Godot / $DRIVER"
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
LOG="agentdir/logs/media-churn-$DRIVER$SUFFIX.log"

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
run_watchdog "$LOG" $((60 + CYCLES * 7 + SETTLE + 60)) python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://media_churn.tscn \
    --render-thread safe || CODE=$?

EXPECTED_IDLE=$((1 + SETTLE / 10))
REPORT="artifacts/reference/media-churn-$DRIVER$SUFFIX.json"
PASS=0
python3 - "$LOG" "$REPORT" "$CODE" "$CYCLES" "$EXPECTED_IDLE" "$DRIVER" "$SETTLE" "$AUDIO_ONLY" <<'EOF' || PASS=$?
import json, re, sys
log_path, report_path, code, cycles, driver, settle, audio_only = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6], int(sys.argv[7])
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
expected_idle = int(sys.argv[5])
passed = (code == 0 and "MEDIA_CHURN_PROBE_PASS" in output and "GODOT_MEDIA_CHURN_PASS" in output
          and len(native) == cycles and len(java) == cycles and len(process_samples) == cycles
          and len(idle_samples) == expected_idle
          and not re.search(r"(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|OutOfMemoryError|uncaught:", output))
report = {"aac_registration_stable": None, "providers": False, "audio_only": bool(audio_only),
          "handle_types": False, "playback_and_cleanup_passed": passed,
          "resource_growth_acceptance": "requires separate trend analysis", "cycles": cycles,
          "runtime": False, "native_d3d": False, "driver": driver, "settle_seconds": settle,
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
