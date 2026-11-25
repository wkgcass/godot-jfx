#!/bin/sh
# Exercise the same byte budget and sequence checks used by the native snapshot helper.
set -u
cd "$(dirname "$0")/.."

mkdir -p agentdir/logs artifacts/native-tests
PEER=artifacts/native-tests/clipboard_snapshot_guard_test
if [ ! -x "$PEER" ] || [ tests/native/clipboard_snapshot_guard_test.cpp -nt "$PEER" ] || [ tests/native/clipboard_snapshot_guard.h -nt "$PEER" ]; then
    "${CXX:-c++}" -std=c++17 -O2 tests/native/clipboard_snapshot_guard_test.cpp -o "$PEER" || exit 1
fi

LOG="agentdir/logs/clipboard-snapshot-guard.log"
"$PEER" >"$LOG" 2>&1 || {
    echo "Clipboard snapshot guard failed: $LOG" >&2
    exit 1
}
if ! grep -q 'CLIPBOARD_SNAPSHOT_BUDGET_PASS' "$LOG" \
    || ! grep -q 'CLIPBOARD_SNAPSHOT_GUARD_PASS' "$LOG"; then
    echo "Clipboard snapshot guard failed: $LOG" >&2
    exit 1
fi
echo "Clipboard snapshot guard passed (no clipboard access): $LOG"
