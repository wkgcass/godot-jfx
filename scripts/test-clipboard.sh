#!/bin/sh
# macOS equivalent of test-clipboard.ps1.
#
# The peer checks Java output and publishes its two test datasets directly.
# Usage: test-clipboard.sh [--renderer mobile|gl_compatibility] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in mobile|gl_compatibility) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs artifacts/native-tests

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/ClipboardProbe.java \
    || { echo "Clipboard probe compilation failed" >&2; exit 1; }

PEER="artifacts/native-tests/macos_clipboard_peer"
if [ ! -x "$PEER" ] || [ tests/native/macos_clipboard_peer.mm -nt "$PEER" ]; then
    clang++ -std=c++17 -fobjc-arc -framework AppKit \
        tests/native/macos_clipboard_peer.mm -o "$PEER" \
        || { echo "Clipboard peer compilation failed" >&2; exit 1; }
fi

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

UUID=$(uuidgen | tr -d '-' | tr 'A-F' 'a-f')
SYNC="$PWD/artifacts/native-tests/clipboard-$UUID.ready"
PEER_LOG="artifacts/logs/clipboard-peer.log"
# The macOS pasteboard server hides file lists of nonexistent paths from
# other processes, so the probe fixtures (ClipboardProbe FILES and the
# external peer's second set) must be real files.
FIXTURE_DIR="/tmp/godot-jfx-clipboard-fixture"
mkdir -p "$FIXTURE_DIR/godot-jfx测试" "$FIXTURE_DIR/外部"
touch "$FIXTURE_DIR/godot-jfx测试/报告 🙂.txt" "$FIXTURE_DIR/README.md" \
    "$FIXTURE_DIR/外部/文件 甲.txt" "$FIXTURE_DIR/外部/乙🙂.png"

cleanup() {
    if [ -n "${PEER_PID:-}" ]; then
        kill "$PEER_PID" 2>/dev/null || true
        wait "$PEER_PID" 2>/dev/null || true
    fi
    rm -f "$SYNC" "$SYNC.external" "$SYNC.external2" "$SYNC.ack"
    rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_CLIPBOARD_SYNC="$SYNC"
"$PEER" exchange "$SYNC" >"$PEER_LOG" 2>&1 &
PEER_PID=$!

SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/artifacts/logs/clipboard-$RENDERER$SUFFIX.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    FIXTURE="$PWD/artifacts/runtime-clipboard"
    mkdir -p "$FIXTURE"
    cp tests/godot/clipboard_test.gd tests/godot/clipboard.tscn "$FIXTURE/"
    sed 's|res://main.tscn|res://clipboard.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$PWD/godot/bin/godot.macos.editor.arm64" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Clipboard runtime import failed: $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" \
        --rendering-method "$RENDERER" --render-thread safe --quit-after 3000) || CODE=$?
else
    run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --path tests/godot res://clipboard.tscn \
        --rendering-method "$RENDERER" --render-thread safe --quit-after 3000 || CODE=$?
fi
PEER_CODE=0
wait "$PEER_PID" || PEER_CODE=$?
PEER_PID=""
if [ "$PEER_CODE" -ne 0 ] || ! grep -q 'CLIPBOARD_EXTERNAL_RICH_PASS' "$PEER_LOG"; then
    echo "External clipboard validation failed: $PEER_LOG" >&2
    exit 1
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_CLIPBOARD_PASS' "$LOG" \
    || ! grep -q 'CLIPBOARD_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "Clipboard probe failed: $LOG" >&2
    exit 1
fi
echo "Clipboard exchange passed: $LOG"
