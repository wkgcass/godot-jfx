#!/bin/sh
# macOS equivalent of test-stage-churn.ps1.
# Usage: test-stage-churn.sh [--renderer mobile|gl_compatibility] [--render-thread safe] [--cycles N] [--heap-mib N]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RENDER_THREAD="safe"
CYCLES=36
HEAP_MIB=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --cycles) CYCLES="$2"; shift ;;
        --heap-mib) HEAP_MIB="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
case "$CYCLES" in ''|*[!0-9]*) echo "invalid cycles: $CYCLES" >&2; exit 2 ;; esac
case "$HEAP_MIB" in ''|*[!0-9]*) echo "invalid heap mib: $HEAP_MIB" >&2; exit 2 ;; esac
if [ "$CYCLES" -lt 6 ] || [ "$CYCLES" -gt 1000 ]; then echo "invalid cycles: $CYCLES" >&2; exit 2; fi
if [ "$HEAP_MIB" -gt 4096 ]; then echo "invalid heap mib: $HEAP_MIB" >&2; exit 2; fi

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    -d artifacts/reference tests/reference/StageChurnProbe.java

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_CHURN_CYCLES="$CYCLES"
if [ "$HEAP_MIB" -gt 0 ]; then
    export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Xmx${HEAP_MIB}m"
fi
SUFFIX="-$CYCLES-heap$HEAP_MIB"
LOG="agentdir/logs/stage-churn-$RENDERER-$RENDER_THREAD$SUFFIX.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://stage_churn.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_STAGE_CHURN_PASS' "$LOG" \
    || ! grep -q 'STAGE_CHURN_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:' "$LOG"; then
    echo "Stage churn failed: $LOG" >&2
    exit 1
fi

# Merge the log samples into the renderer-specific churn report, mirroring the
# PowerShell sample-count assertions.
CYCLES="$CYCLES" HEAP_MIB="$HEAP_MIB" LOG="$LOG" \
OUT_JSON="artifacts/reference/stage-churn-$RENDERER-$RENDER_THREAD$SUFFIX.json" \
python3 - <<'PY'
import json, os, re, sys

cycles = int(os.environ["CYCLES"])
heap_mib = int(os.environ["HEAP_MIB"])
with open(os.environ["LOG"], encoding="utf-8", errors="replace") as fh:
    output = fh.read()

java_samples = [
    {"cycle": int(m.group(1)), "heap_used": int(m.group(2)),
     "gc_count": int(m.group(3)), "collected_stages": int(m.group(4))}
    for m in re.finditer(r"STAGE_CHURN_JAVA cycle=(\d+) heap_used=(\d+) gc_count=(\d+) collected_stages=(\d+)", output)
]
if len(java_samples) != cycles:
    sys.exit("Stage churn Java sample count differs")
with open("artifacts/reference/stage-churn.json", encoding="utf-8") as fh:
    report = json.load(fh)
native_samples = [json.loads(m.group(1)) for m in re.finditer(r"(?m)^STAGE_CHURN_RESOURCES (\{[^\r\n]+\})", output)]
if len(native_samples) != cycles + 1:
    sys.exit("Stage churn native sample count differs")
report["samples"] = native_samples
report["java_samples"] = java_samples
report["heap_limit_mib"] = heap_mib
with open(os.environ["OUT_JSON"], "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
PY
echo "Stage churn passed: $LOG"
