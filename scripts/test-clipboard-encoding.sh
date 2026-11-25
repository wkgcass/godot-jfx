#!/bin/sh
set -e
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
JDK="$JAVA_HOME"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference agentdir/logs
"$JDK/bin/javac" -encoding UTF-8 -d artifacts/reference tests/reference/ClipboardEncodingProbe.java
log='agentdir/logs/clipboard-encoding.log'
"$JDK/bin/java" -Xmx32m -XX:MaxDirectMemorySize=96m --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-opens javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -cp artifacts/reference ClipboardEncodingProbe > "$log" 2>&1 || {
    echo "Clipboard encoding failed: $log" >&2
    exit 1
}
if ! grep -q 'CLIPBOARD_ENCODING_PASS' "$log" || ! grep -q 'CLIPBOARD_IMAGE_BUDGET_PASS' "$log"; then
    echo "Clipboard encoding failed: $log" >&2
    exit 1
fi
echo 'Clipboard encoding passed (no system clipboard access)'
if [ "$(uname -s)" = Linux ]; then
    classes=artifacts/reference/wayland-clipboard-encoding
    mkdir -p "$classes"
    "$JDK/bin/javac" --module-path jfx/build/sdk/lib --patch-module javafx.graphics=tests/reference \
        -encoding UTF-8 -d "$classes" tests/reference/LinuxClipboardInterop.java tests/reference/WaylandClipboardEncodingProbe.java
    # A forced graphical AWT environment with no display catches accidental desktop toolkit access.
    env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET "$JDK/bin/java" -Djava.awt.headless=false \
        --module-path jfx/build/sdk/lib --patch-module "javafx.graphics=$classes" \
        -m javafx.graphics/com.sun.javafx.tk.godot.WaylandClipboardEncodingProbe >> "$log" 2>&1 ||
        { cat "$log" >&2; exit 1; }
    grep -Fx WAYLAND_CLIPBOARD_ENCODING_PASS "$log"
fi
