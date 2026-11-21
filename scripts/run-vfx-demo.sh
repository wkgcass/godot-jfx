#!/bin/sh
# macOS equivalent of run-vfx-demo.ps1.
# Usage: run-vfx-demo.sh [--smoke] [--driver metal|opengl] [--render-thread safe] [--no-godot-logo] [--disable-vsync] [--max-fps N]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
DRIVER="metal"
RENDER_THREAD="safe"
SMOKE=0
STARTUP="logo"
MAX_FPS=0
DISABLE_VSYNC=0
while [ $# -gt 0 ]; do
    case "$1" in
        --smoke) SMOKE=1 ;;
        --driver)
            case "${2-}" in metal|opengl) DRIVER="$2" ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
            shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --no-godot-logo) STARTUP="hidden" ;;
        --disable-vsync) DISABLE_VSYNC=1 ;;
        --max-fps) MAX_FPS="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
case "$MAX_FPS" in ''|*[!0-9]*) echo "invalid max fps: $MAX_FPS" >&2; exit 2 ;; esac
[ "$MAX_FPS" -le 1000 ] || { echo "max fps exceeds 1000" >&2; exit 2; }
if [ ! -x "$JDK/bin/java" ]; then echo "JDK not found at $JDK" >&2; exit 1; fi

LOG="agentdir/logs/vfx-demo-$DRIVER-$RENDER_THREAD.log"
mkdir -p agentdir/logs

echo "Starting the VFX Demo ($DRIVER + $RENDER_THREAD). Log: $LOG"
jar=artifacts/vfx/libs/vfx-demo.jar
[ -f "$jar" ] || { echo "Missing $jar. Run sh scripts/build-vfx.sh first." >&2; exit 1; }
set -- -jar "$jar"
set -- "-Djavafx.godot.driver=$DRIVER" "$@"
set -- "$JDK/bin/java" "$@"
[ "$SMOKE" -eq 0 ] || set -- "$@" --smoke
[ "$STARTUP" = logo ] || set -- "$@" --no-godot-logo
if [ "$DISABLE_VSYNC" -eq 1 ]; then
    set -- "$@" --disable-vsync
    [ "$MAX_FPS" -gt 0 ] || MAX_FPS=60
fi
[ "$MAX_FPS" -eq 0 ] || set -- "$@" --max-fps "$MAX_FPS"
"$@" > "$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ]; then echo "VFX Demo failed (native exit $CODE): $LOG" >&2; exit 1; fi
python3 scripts/godot_driver.py --driver "$DRIVER" "$LOG" || exit 1
if ! grep -q 'VFX_DEMO_CLOSED' "$LOG"; then echo "VFX Demo missing VFX_DEMO_CLOSED: $LOG" >&2; exit 1; fi
if grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then echo "VFX Demo reported errors: $LOG" >&2; exit 1; fi
echo "VFX Demo closed cleanly: $LOG"
