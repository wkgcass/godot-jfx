#!/bin/sh
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
classes=artifacts/linux-clipboard
mkdir -p "$classes" agentdir/logs
modules=$(python3 scripts/maven_local.py module-path)
patched="$classes/wayland"
mkdir -p "$patched"
"$JAVA_HOME/bin/javac" --module-path "$modules" --patch-module javafx.graphics=tests/reference \
    -encoding UTF-8 -d "$patched" tests/reference/LinuxClipboardInterop.java tests/reference/WaylandClipboardInterop.java
exchange=$(mktemp -d "$PWD/$classes/exchange-XXXXXXXX")
run_peer() {
    set -- timeout -k 3 40 "$JAVA_HOME/bin/java" --module-path "$modules" --patch-module "javafx.graphics=$patched" \
        --enable-native-access=javafx.graphics -Djavafx.godot.verbose=true \
        -m javafx.graphics/com.sun.javafx.tk.godot.WaylandClipboardInterop "$1" "$exchange/ready"
    if [ -c /dev/dxg ]; then set -- scripts/wsl-gpu.sh vulkan "$@"; fi
    env -u DISPLAY "$@"
}
owner_log=agentdir/logs/linux-clipboard-owner.log
reader_log=agentdir/logs/linux-clipboard-reader.log
run_peer owner >"$owner_log" 2>&1 &
owner=$!
for i in $(seq 1 150); do
    [ ! -e "$exchange/ready" ] && kill -0 "$owner" 2>/dev/null || break
    sleep .1
done
reader_code=1
if [ -e "$exchange/ready" ]; then
    reader_code=0
    run_peer reader >"$reader_log" 2>&1 || reader_code=$?
fi
wait "$owner" && [ "$reader_code" -eq 0 ] || { cat "$owner_log" "$reader_log" >&2; exit 1; }
grep -qx WAYLAND_CLIPBOARD_OWNER_PASS "$owner_log"
grep -qx WAYLAND_CLIPBOARD_READER_PASS "$reader_log"
for log in "$owner_log" "$reader_log"; do
    python3 scripts/godot_driver.py --driver vulkan --display-driver Wayland "$log"
done
echo LINUX_CLIPBOARD_INTEROP_PASS
