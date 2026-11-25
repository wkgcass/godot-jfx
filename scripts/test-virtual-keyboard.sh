#!/bin/sh
# Check the desktop backend's unsupported-keyboard response and continued host ticks.
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
driver=$native_driver
mode=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --driver) driver=$2; shift ;;
        --robot|--compile-only) mode=$1 ;;
        *) echo "Unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
case "$mode" in --robot|--compile-only) ;; *) echo "Select --robot or --compile-only" >&2; exit 2 ;; esac
jdk="$JAVA_HOME"
mkdir -p artifacts/reference agentdir/logs
"$jdk/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED \
    -d artifacts/reference tests/reference/VirtualKeyboardProbe.java
[ "$mode" = --robot ] || exit 0
log="agentdir/logs/virtual-keyboard-$driver.log"
./scripts/godot-fixture.py --driver "$driver" --path tests/godot res://virtual_keyboard.tscn --quit-after 3000 >"$log" 2>&1
case "$(uname -s)" in
    Darwin) platform=macOS ;;
    Linux)
        display=$(sed -n 's/^GODOT_LIBRARY_DISPLAY_DRIVER //p' "$log" | head -n 1)
        case "$display" in Wayland) platform=Linux/$display ;; *) echo "Missing Linux display driver in $log" >&2; exit 1 ;; esac ;;
    *) echo "Unsupported platform" >&2; exit 2 ;;
esac
for marker in GODOT_VIRTUAL_KEYBOARD_PASS VIRTUAL_KEYBOARD_PASS: "touch keyboard requests are not supported on $platform" "touch keyboard close requests are not supported on $platform"; do
    grep -Fq "$marker" "$log" || { echo "Missing $marker in $log" >&2; exit 1; }
done
if grep -Eq '^(ERROR:|SCRIPT ERROR:|Exception)' "$log"; then exit 1; fi
echo "Virtual keyboard contract passed: $log"
