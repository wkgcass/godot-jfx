#!/bin/sh
# macOS equivalent of test-file-dialog.ps1.
#
# The Windows variant drives the real native dialog with per-process system
# messages (tests/reference/FileDialogDriver.cs) and additionally asserts the
# dialog's OS window class and owner chain. Driving NSOpenPanel/NSSavePanel
# would require accessibility permission and real keyboard input (robot class),
# so the macOS port enables the module test hook instead: with
# GODOT_JFX_DIALOG_HOOK=1 the host completes dialogSubmit requests
# deterministically (selecting the initial file/folder, auto-cancelling the
# dedicated cancel case, staying open for the owner-close and host-stop cases)
# through the same submit/poll/cancel contract the Cocoa panels use. The
# FileDialogProbe assertions are unchanged: FileChooser results, filter
# identity, cancel semantics and FX-loop liveness during the modal chooser.
#
# Usage: test-file-dialog.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--stop-host]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
STOP_HOST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --stop-host) STOP_HOST=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/FileDialogProbe.java

TOKEN="JFX-$(uuidgen | tr -d '-' | tr 'A-F' 'a-f')"
READY_PATH="$PWD/agentdir/logs/$TOKEN.ready"
SUFFIX=""
[ "$STOP_HOST" = 1 ] && SUFFIX="-stop"
LOG="agentdir/logs/file-dialog-$RENDERER-$RENDER_THREAD$SUFFIX.log"

CODE=0
(
    export GODOT_JFX_JDK="$JDK"
    export GODOT_JFX_DIALOG_TOKEN="$TOKEN"
    export GODOT_JFX_DIALOG_HOOK=1
    export GODOT_JFX_DIALOG_STOP="$STOP_HOST"
    if [ "$STOP_HOST" = 1 ]; then export GODOT_JFX_DIALOG_READY="$READY_PATH"; fi
    python3 "$FIXTURE_LAUNCHER" --path tests/godot res://file_dialog.tscn \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" >"$LOG" 2>&1
) || CODE=$?
rm -f "$READY_PATH"

if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_FILE_DIALOG_PASS' "$LOG" \
    || ! grep -q 'FILE_DIALOG_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "File dialog test failed: $LOG" >&2
    exit 1
fi
if [ "$STOP_HOST" = 1 ] && ! grep -q 'FILE_DIALOG_HOST_STOP_RETURNED' "$LOG"; then
    echo "Host-stop path not completed: $LOG" >&2
    exit 1
fi
echo "File dialog passed: $LOG"
