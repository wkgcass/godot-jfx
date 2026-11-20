#!/bin/sh
# macOS equivalent of test-drag-drop-external.ps1. Builds a Cocoa helper
# (tests/native/dnd_helper_macos.mm) with two endpoints — an NSPasteboard drop
# target and a drag source — and drives the physical mouse with the JavaFX
# Robot through three phases: drag text+URL+files out to the helper, receive a
# helper drag-in, cancel an outbound drag with Escape.
#
# This test moves the real mouse and reads the screen: the terminal needs
# Accessibility and Screen Recording permissions; keep the desktop idle.
# Usage: test-drag-drop-external.sh [--renderer mobile|gl_compatibility] [--render-thread safe]
set -eu
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

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs artifacts/native-tests

HELPER="artifacts/native-tests/dnd_helper_macos"
BUILD_LOG="agentdir/logs/dnd-helper-build.log"
if ! clang++ -std=c++17 -fobjc-arc -O2 -framework AppKit -framework Foundation \
        tests/native/dnd_helper_macos.mm -o "$HELPER" >"$BUILD_LOG" 2>&1; then
    echo "dnd_helper_macos build failed: $BUILD_LOG" >&2; exit 1
fi
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    -encoding UTF-8 -d artifacts/reference tests/reference/ExternalDragProbe.java \
    || { echo "ExternalDragProbe compilation failed" >&2; exit 1; }

TARGET_LOG="agentdir/logs/dnd-helper-target.log"
SOURCE_LOG="agentdir/logs/dnd-helper-source.log"
rm -f "$TARGET_LOG" "$SOURCE_LOG"

HELPER_PIDS=""
cleanup() {
    for pid in $HELPER_PIDS; do kill "$pid" 2>/dev/null || true; done
    rm -f /tmp/drag-test.txt /tmp/helper-source.txt
}
trap cleanup EXIT

# Cross-process Cocoa drags silently drop file items whose path does not
# exist, so the fixture files must be real (Windows OLE tolerated C:/ paths).
touch /tmp/drag-test.txt /tmp/helper-source.txt

# Chromeless topmost helper windows in JavaFX logical points, right of the
# 400x160 stage at FX (300,300). Unlike Windows, Cocoa window placement and
# CoreGraphics event coordinates share the same point space, so no DPI
# scaling is applied here.
"./$HELPER" target 780 300 320 200 "$TARGET_LOG" &
HELPER_PIDS="$HELPER_PIDS $!"
# Inbound file rides a Cocoa file URL, so it must be a real absolute path
# (Windows OLE round-tripped the synthetic C:/helper-source.txt verbatim).
"./$HELPER" source 1140 300 320 200 "$SOURCE_LOG" "外部拖入 text" "https://example.org/inbound" "/tmp/helper-source.txt" "外部自定义负载 🙂" &
HELPER_PIDS="$HELPER_PIDS $!"

READY=0
i=0
while [ "$i" -lt 100 ]; do
    if grep -q 'DND_HELPER_READY' "$TARGET_LOG" 2>/dev/null \
        && grep -q 'DND_HELPER_READY' "$SOURCE_LOG" 2>/dev/null; then
        READY=1; break
    fi
    sleep 0.1 2>/dev/null || sleep 1
    i=$((i + 1))
done
[ "$READY" = "1" ] || { echo "dnd_helper windows did not initialize: $TARGET_LOG / $SOURCE_LOG" >&2; exit 1; }

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
export GODOT_JFX_HELPER_X=940 GODOT_JFX_HELPER_Y=400
export GODOT_JFX_HELPER_SRC_X=1300 GODOT_JFX_HELPER_SRC_Y=400
LOG="agentdir/logs/drag-drop-external-$RENDERER-$RENDER_THREAD.log"
CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --path tests/godot res://drag_drop_external.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 30000 || CODE=$?

if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_EXTERNAL_DRAG_PASS' "$LOG" \
    || ! grep -q 'EXTERNAL_DRAG_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG"; then
    echo "External drag/drop test failed or incomplete (exit $CODE). See $LOG" >&2
    exit 1
fi
# The probe publishes /tmp/drag-test.txt on macOS (the per-OS fixture path);
# the filename plist must round-trip it verbatim, like the Windows path does.
if ! grep -qF 'DND_HELPER_DROP text=[外部 OLE 拖放 text] url=[https://example.org/ole] files=1 first=[/tmp/drag-test.txt] custom=[出站自定义负载 🙂]' "$TARGET_LOG"; then
    echo "Helper drop payload mismatch: $TARGET_LOG" >&2
    exit 1
fi
# Dragboard.setDragView(8x6, offset 5,3) must reach the destination: the
# helper observes the Cocoa draggingImage during DragEnter. The offset is a
# source-side cursor anchor and is not observable through NSDraggingInfo, so
# the macOS assertion covers the image size only.
if ! grep -E 'DND_HELPER_ENTER .*image=8x6 bytes=[0-9]+' "$TARGET_LOG" >/dev/null; then
    echo "Helper did not observe the drag image (8x6): $TARGET_LOG" >&2
    exit 1
fi
if ! grep -q 'DND_HELPER_SOURCE_DONE effect=1' "$SOURCE_LOG"; then
    echo "Helper drag source did not complete with COPY: $SOURCE_LOG" >&2
    exit 1
fi
echo "External drag/drop passed: $LOG"
