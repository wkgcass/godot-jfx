#!/bin/sh
# macOS equivalent of test-clipboard.ps1.
#
# Clipboard safety: the shared system pasteboard is snapshotted before the
# test (every type as raw bytes, via tests/native/macos_clipboard_peer.mm —
# the NSPasteboard counterpart of ClipboardSnapshot.cs) and restored
# afterwards. Restoration is refused when the pasteboard change count moved
# beyond the test's own writes, so newer user content is never overwritten;
# on any failure the snapshot directory is kept for manual recovery. The
# peer validates the same wire contracts the Windows runspace peer checks
# (CF_HTML fragment offsets, RTF, Unicode URL, file list, image, custom
# format) and then publishes the two external sets ClipboardProbe expects.
#
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

GODOT="./godot/bin/godot.macos.editor.arm64"
TEMPLATE="./godot/bin/godot.macos.template_release.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
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
BACKUP="$PWD/artifacts/native-tests/clipboard-backup-$UUID"
PEER_LOG="artifacts/logs/clipboard-peer.log"
# The macOS pasteboard server hides file lists of nonexistent paths from
# other processes, so the probe fixtures (ClipboardProbe FILES and the
# external peer's second set) must be real files.
FIXTURE_DIR="/tmp/godot-jfx-clipboard-fixture"
mkdir -p "$FIXTURE_DIR/godot-jfx测试" "$FIXTURE_DIR/外部"
touch "$FIXTURE_DIR/godot-jfx测试/报告 🙂.txt" "$FIXTURE_DIR/README.md" \
    "$FIXTURE_DIR/外部/文件 甲.txt" "$FIXTURE_DIR/外部/乙🙂.png"

# Materialize the complete snapshot before any test write; the peer refuses
# unreadable, empty or oversized content and the test then never runs.
"$PEER" backup "$BACKUP" >"$PEER_LOG" 2>&1 || {
    echo "Clipboard backup failed; test did not run: $PEER_LOG" >&2
    exit 1
}
EXPECTED_COUNT=$(cat "$BACKUP/changecount")

restore_clipboard() {
    # Newer content wins: a moved change count keeps the user's clipboard
    # untouched and retains the snapshot for manual recovery.
    if "$PEER" restore "$BACKUP" "$EXPECTED_COUNT" >>"$PEER_LOG" 2>&1; then
        rm -rf "$BACKUP"
    else
        echo "Clipboard restoration refused; original snapshot retained at $BACKUP" >&2
    fi
    rm -f "$SYNC" "$SYNC.external" "$SYNC.external2" "$SYNC.ack"
    rm -rf "$FIXTURE_DIR"
}
trap restore_clipboard EXIT

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_CLIPBOARD_SYNC="$SYNC"
"$PEER" exchange "$SYNC" >>"$PEER_LOG" 2>&1 &
PEER_PID=$!

SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/artifacts/logs/clipboard-$RENDERER$SUFFIX.log"
CODE=0
if [ "$RUNTIME" -eq 1 ]; then
    [ -x "$TEMPLATE" ] || { echo "Godot template not found: $TEMPLATE" >&2; exit 1; }
    FIXTURE="$PWD/artifacts/runtime-clipboard"
    mkdir -p "$FIXTURE"
    cp "$TEMPLATE" tests/godot/clipboard_test.gd tests/godot/clipboard.tscn "$FIXTURE/"
    sed 's|res://main.tscn|res://clipboard.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    "$GODOT" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Clipboard runtime import failed: $LOG.import" >&2; exit 1; fi
    (cd "$FIXTURE" && run_watchdog "$LOG" 240 "./godot.macos.template_release.arm64" \
        --rendering-method "$RENDERER" --render-thread safe --quit-after 3000) || CODE=$?
else
    run_watchdog "$LOG" 240 "$GODOT" --path tests/godot res://clipboard.tscn \
        --rendering-method "$RENDERER" --render-thread safe --quit-after 3000 || CODE=$?
fi
PEER_CODE=0
wait "$PEER_PID" || PEER_CODE=$?
# Track the test's last own publication for the restoration guard.
LAST_COUNT=$(grep 'CLIPBOARD_CHANGE_COUNT ' "$PEER_LOG" | tail -1 | awk '{print $2}')
[ -n "$LAST_COUNT" ] && EXPECTED_COUNT="$LAST_COUNT"
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
echo "Clipboard probe and exact restoration passed: $LOG"
