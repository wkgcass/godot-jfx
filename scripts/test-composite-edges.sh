#!/bin/sh
# macOS equivalent of test-composite-edges.ps1. The native reference run uses
# the stock macOS Prism pipeline (Metal by default) instead of D3D; the pixel
# comparison against the Godot pipeline keeps the same per-channel tolerance.
# Usage: test-composite-edges.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
PY=".tools/pyenv/bin/python3"
[ -x "$PY" ] || PY="python3"
mkdir -p artifacts/reference agentdir/logs

EXPORTS="--add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED"
EXPORTS="$EXPORTS --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED"
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics $EXPORTS \
    -encoding UTF-8 -d artifacts/reference tests/reference/CompositeEdgeProbe.java || { echo "Edge probe compilation failed" >&2; exit 1; }

REFERENCE="$PWD/artifacts/reference/composite-edges-mac-native.txt"
REFLOG="agentdir/logs/composite-edges-mac-native.log"
CODE=0
# shellcheck disable=SC2086
"$JDK/bin/java" -Dglass.platform=Mac --module-path jfx/build/sdk/lib --add-modules javafx.graphics $EXPORTS \
    "-Dedges.output=$REFERENCE" -cp artifacts/reference CompositeEdgeProbe >"$REFLOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'COMPOSITE_EDGE_PROBE_PASS ' "$REFLOG" \
    || grep -qi 'COMPOSITE_EDGE_PROBE_PASS GodotPipeline' "$REFLOG"; then
    echo "Native edge reference failed: $REFLOG" >&2
    exit 1
fi

export GODOT_JFX_EDGE_OUTPUT="$PWD/artifacts/reference/composite-edges-$DRIVER-$RENDER_THREAD.txt"
LOG="agentdir/logs/composite-edges-$DRIVER-$RENDER_THREAD.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://composite_edges.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_COMPOSITE_EDGES_PASS' "$LOG" \
    || ! grep -qi 'COMPOSITE_EDGE_PROBE_PASS GodotPipeline' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Edge probe failed: $LOG" >&2
    exit 1
fi

"$PY" - "$REFERENCE" "$GODOT_JFX_EDGE_OUTPUT" "$LOG.diff" <<'EOF'
import sys
exp_path, act_path, diff_path = sys.argv[1:4]
exp = open(exp_path).read().splitlines()
act = open(act_path).read().splitlines()
if len(exp) != 20 or len(act) != 20:
    sys.exit('Incomplete edge coverage')
diffs = []
for row in range(20):
    a = act[row].split()
    e = exp[row].split()
    if len(a) != 17 or len(e) != 17 or a[0] != e[0]:
        sys.exit('Edge case layout differs')
    for pixel in range(1, 17):
        av = int(a[pixel], 16)
        ev = int(e[pixel], 16)
        for shift in (0, 8, 16, 24):
            if abs(((av >> shift) & 255) - ((ev >> shift) & 255)) > 2:
                diffs.append('%s pixel=%d actual=%s native=%s' % (a[0], pixel - 1, a[pixel], e[pixel]))
                break
with open(diff_path, 'w') as fh:
    fh.write('\n'.join(diffs))
    if diffs:
        fh.write('\n')
if diffs:
    sys.exit('Composite edge comparison has %d differing pixels; see %s' % (len(diffs), diff_path))
EOF
[ $? -eq 0 ] || exit 1
echo "Composite edge native comparison passed: $LOG"
