#!/bin/sh
# macOS equivalent of test-clipboard-snapshot-guard.ps1.
#
# The Windows script exercises the C# snapshot helper's internals (registered
# format allowlist, budget arithmetic, sequence guards, enumeration and
# allocation failure cleanup) without touching the system clipboard. The
# macOS helper (tests/native/macos_clipboard_peer.mm) stores whole pasteboard
# types as raw bytes, so the registered-format allowlist and the Win32
# enumeration/allocation failure paths have no counterpart here. What remains
# is the same judgment over the shared guard logic: aggregate budget
# accounting and change-count mismatch refusal, checked by the helper's
# guard-selftest mode, which never opens the system clipboard.
set -u
cd "$(dirname "$0")/.."

mkdir -p artifacts/logs artifacts/native-tests
PEER="artifacts/native-tests/macos_clipboard_peer"
if [ ! -x "$PEER" ] || [ tests/native/macos_clipboard_peer.mm -nt "$PEER" ]; then
    clang++ -std=c++17 -fobjc-arc -framework AppKit \
        tests/native/macos_clipboard_peer.mm -o "$PEER" \
        || { echo "Clipboard peer compilation failed" >&2; exit 1; }
fi

LOG="artifacts/logs/clipboard-snapshot-guard.log"
"$PEER" guard-selftest >"$LOG" 2>&1 || {
    echo "Clipboard snapshot guard failed: $LOG" >&2
    exit 1
}
if ! grep -q 'CLIPBOARD_SNAPSHOT_BUDGET_PASS' "$LOG" \
    || ! grep -q 'CLIPBOARD_SNAPSHOT_GUARD_PASS' "$LOG"; then
    echo "Clipboard snapshot guard failed: $LOG" >&2
    exit 1
fi
echo "Clipboard snapshot guard passed (no clipboard access): $LOG"
