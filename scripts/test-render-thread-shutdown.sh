#!/bin/sh
# macOS equivalent of test-render-thread-shutdown.ps1.
# Usage: test-render-thread-shutdown.sh [--driver metal|opengl] [--runtime] [--jdk DIRECTORY]
set -u
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

runtime=""
DRIVER="metal"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --runtime) runtime="-runtime" ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
mkdir -p agentdir/logs

LOG="agentdir/logs/render-thread-shutdown-scene-safe$runtime.log"
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" ${runtime:+--runtime} --path tests/godot res://render_thread_shutdown.tscn \
    --render-thread safe --quit-after 3 > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! python3 scripts/godot_driver.py --driver "$DRIVER" "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:)|leaked at exit' "$LOG"; then
    echo "Render thread shutdown failed: $LOG" >&2
    exit 1
fi
echo "Render thread shutdown passed: scene / safe"
