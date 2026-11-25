#!/bin/sh
# Unix VFX navigation, cleanup and process-memory observations.
# Usage: test-vfx-soak.sh [--driver vulkan|metal|opengl] [--rounds 1..20] [--heap-mib 128..4096] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="$native_driver"
ROUNDS=3
HEAP=256
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --rounds) ROUNDS="$2"; shift ;;
        --heap-mib) HEAP="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
check_desktop_driver "$DRIVER" || exit 2
[ "$ROUNDS" -ge 1 ] && [ "$ROUNDS" -le 20 ] || { echo "invalid rounds: $ROUNDS" >&2; exit 2; }
[ "$HEAP" -ge 128 ] && [ "$HEAP" -le 4096 ] || { echo "invalid heap MiB: $HEAP" >&2; exit 2; }

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxNavigationProbe.java \
    || { echo "VFX observer compilation failed" >&2; exit 1; }

PAGES=$(grep -c 'mainScenes\.add(new' vfx/src/test/java/io/vproxy/vfx/intro/IntroFXMain.java)
export GODOT_JFX_VFX_PAGES="$PAGES"
export GODOT_JFX_VFX_ROUNDS="$ROUNDS"
export GODOT_JFX_VFX_SOAK=1
export GODOT_JFX_VFX_FREEZE=0
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Xmx${HEAP}m"

STEM="vfx-soak-$DRIVER-$ROUNDS-heap$HEAP"
LOG="agentdir/logs/$STEM.log"
ERR="agentdir/logs/$STEM.stderr.log"
TIMEOUT=$((120 + ROUNDS * PAGES * 8))

python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_soak.tscn \
    --render-thread safe >"$LOG" 2>"$ERR" &
PID=$!
SAMPLES="agentdir/logs/$STEM.samples.jsonl"
: >"$SAMPLES"
if [ -r /proc/uptime ]; then read -r START_UPTIME _ </proc/uptime; fi
ELAPSED=0
TIMED_OUT=0
while kill -0 "$PID" 2>/dev/null; do
    if [ "$native_driver" = vulkan ]; then
        # The fixture launcher execs java. Ignore its preparatory Python process.
        if [ "$(readlink "/proc/$PID/exe" 2>/dev/null)" = "$(readlink -f "$JDK/bin/java")" ]; then
            read -r uptime _ </proc/uptime
            descriptors=$(find "/proc/$PID/fd" -mindepth 1 -maxdepth 1 -printf . 2>/dev/null | wc -c)
            awk -v start="$START_UPTIME" -v now="$uptime" -v unix_ns="$(date +%s%N)" -v descriptors="$descriptors" '
                $1 == "Rss:" { rss = $2 }
                $1 == "Private_Clean:" || $1 == "Private_Dirty:" || $1 == "Private_Hugetlb:" { private_kib += $2 }
                END { if (rss && descriptors) printf "{\"elapsed_ms\":%.0f,\"unix_ms\":%.0f,\"private_bytes\":%.0f,\"working_set\":%.0f,\"handles\":%d}\n",
                    (now-start)*1000, unix_ns/1000000, private_kib*1024, rss*1024, descriptors }
            ' "/proc/$PID/smaps_rollup" 2>/dev/null >>"$SAMPLES"
        fi
    else
        RSS=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ')
        if [ -n "$RSS" ]; then
            printf '{"elapsed_ms":%d,"private_bytes":%d,"working_set":%d,"handles":0}\n' \
                "$((ELAPSED * 1000))" "$((RSS * 1024))" "$((RSS * 1024))" >>"$SAMPLES"
        fi
    fi
    if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
        kill "$PID" 2>/dev/null || true
        sleep 2
        kill -9 "$PID" 2>/dev/null || true
        TIMED_OUT=1
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
CODE=0
wait "$PID" || CODE=$?
if [ "$TIMED_OUT" -eq 1 ]; then
    echo "VFX soak process timeout: $LOG / $ERR" >&2
    exit 1
fi

cat "$LOG" "$ERR" > "agentdir/logs/$STEM.combined.log"
COMBINED="agentdir/logs/$STEM.combined.log"
EXPECTED=$((1 + ROUNDS * 2 * (PAGES - 1)))
REPORT="artifacts/reference/$STEM.json"
PASS=0
python3 - "$COMBINED" "$REPORT" "$CODE" "$EXPECTED" "$ROUNDS" "$PAGES" "$HEAP" "$PID" "$SAMPLES" <<'EOF' || PASS=$?
import json, re, sys
log_path, report_path, code, expected, rounds, pages, heap_mib, pid = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8])
with open(sys.argv[9], encoding="utf-8") as f:
    process_samples = [json.loads(line) for line in f]
output = open(log_path, encoding="utf-8", errors="replace").read()
native = [json.loads(m.group(1)) for m in re.finditer(r"(?m)^VFX_SOAK_SAMPLE (\{[^\r\n]+\})", output)]
java = [{"page": int(p), "heap_used": int(h), "gc_count": int(g)} for p, h, g in
        re.findall(r"VFX_SOAK_JAVA page=(\d+) heap_used=(\d+) gc_count=(\d+)", output)]
passed = (code == 0 and "VFX_SOAK_PASS" in output and len(native) == expected and len(java) == expected
          and not re.search(r"(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|OutOfMemoryError|uncaught:", output))
report = {"navigation_and_cleanup_passed": passed, "memory_acceptance": "requires trend analysis",
          "sampled_process_id": pid, "sampled_executable": "java" if process_samples else None,
          "rounds": rounds, "pages": pages, "forced_gc": False, "heap_limit_mib": heap_mib,
          "process_samples": process_samples,
          "native_samples": native, "java_samples": java}
with open(report_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
sys.exit(0 if passed else 1)
EOF
if [ "$PASS" -ne 0 ]; then
    echo "VFX soak failed: $LOG / $ERR" >&2
    exit 1
fi
echo "VFX soak navigation/cleanup passed; memory observations: $REPORT"
