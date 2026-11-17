#!/bin/sh
# macOS equivalent of test-native-churn.ps1.
# Usage: test-native-churn.sh [--kind Idle|SubViewport|Window|JavaFXNativeWindow]
#                             [--renderer gl_compatibility|mobile] [--render-thread safe]
#                             [--static-range-limit-bytes N]
set -u
cd "$(dirname "$0")/.."

KIND="Window"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
STATIC_LIMIT=-1
while [ $# -gt 0 ]; do
    case "$1" in
        --kind) KIND="$2"; shift ;;
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --static-range-limit-bytes) STATIC_LIMIT="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$KIND" in Idle|SubViewport|Window|JavaFXNativeWindow) ;; *) echo "invalid kind: $KIND" >&2; exit 2 ;; esac
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
PY="$(command -v python3)" || { echo "python3 not found" >&2; exit 1; }
mkdir -p artifacts/logs artifacts/reference

LOG="artifacts/logs/native-churn-$KIND-$RENDERER-$RENDER_THREAD.log"
GODOT_JFX_NATIVE_CHURN_KIND="$KIND" \
    "$GODOT" --path tests/godot res://native_churn.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 12000 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'NATIVE_CHURN_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Native churn failed: $LOG" >&2
    exit 1
fi

REPORT="artifacts/reference/native-churn-$KIND-$RENDERER-$RENDER_THREAD.json"
STATIC_LIMIT="$STATIC_LIMIT" "$PY" - "$LOG" "$REPORT" <<'EOF'
import json, os, sys

log_path, report_path = sys.argv[1], sys.argv[2]
static_limit = int(os.environ["STATIC_LIMIT"])
samples = []
with open(log_path, encoding="utf-8", errors="replace") as handle:
    for line in handle:
        if line.startswith("NATIVE_CHURN_SAMPLE "):
            samples.append(json.loads(line[len("NATIVE_CHURN_SAMPLE "):]))
if len(samples) != 181:
    print("Incomplete native churn samples", file=sys.stderr)
    sys.exit(1)
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(samples, handle, indent=2)
    handle.write("\n")
if static_limit >= 0:
    tail = [s["static_bytes"] for s in samples if s["cycle"] >= 20]
    if max(tail) - min(tail) > static_limit:
        print(f"Native static-memory range exceeds {static_limit} bytes: {log_path}", file=sys.stderr)
        sys.exit(1)
print(json.dumps(samples[6]))
print(json.dumps(samples[-1]))
EOF
[ $? -eq 0 ] || exit 1
echo "Native churn passed: $LOG"
