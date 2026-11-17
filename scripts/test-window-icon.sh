#!/bin/sh
# macOS equivalent of test-window-icon.ps1 (editor mode only; the -Runtime
# template_release fixture variant is Windows-specific and not ported).
#
# SKIPPED on macOS: NSWindow has no per-window icon concept (the dock icon is
# per-application, set via NSApplication), so the host reports
# get_window_icon_info() -> installed=false by design. This script exists only
# to record that platform gap explicitly instead of silently passing or
# failing; it does not run the probe.
# Usage: test-window-icon.sh [--renderer mobile|gl_compatibility] [--render-thread safe]
set -eu
echo "SKIP: macOS has no per-window icons (NSApplication owns the dock icon); get_window_icon_info reports installed=false by design"
exit 0
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowIconProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/window-icon-$RENDERER-$RENDER_THREAD.log"
CODE=0
"$GODOT" --path tests/godot res://window_icon.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'WINDOW_ICON_PROBE_PASS' "$LOG" \
    || ! grep -q 'GODOT_WINDOW_ICON_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:' "$LOG"; then
    echo "Window icon failed: $LOG" >&2
    exit 1
fi
echo "Window icon passed: $LOG"
