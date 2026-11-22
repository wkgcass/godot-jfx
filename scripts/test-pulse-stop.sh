#!/bin/sh
set -e
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
JDK="$JAVA_HOME"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/pulse-stop-patch artifacts/reference agentdir/logs
source_dir='jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot'
patch='artifacts/pulse-stop-patch'
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --patch-module "javafx.graphics=$source_dir" -d "$patch" "$source_dir/GodotPulseScheduler.java"
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --patch-module "javafx.graphics=$patch" --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -d artifacts/reference tests/reference/PulseStopProbe.java
"$JDK/bin/java" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --patch-module "javafx.graphics=$patch" --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -cp artifacts/reference PulseStopProbe > agentdir/logs/pulse-stop.log 2>&1 || {
    echo "Pulse stop failed: agentdir/logs/pulse-stop.log" >&2
    exit 1
}
if ! grep -q 'PULSE_STOP_PROBE_PASS' agentdir/logs/pulse-stop.log; then
    echo "Pulse stop failed: agentdir/logs/pulse-stop.log" >&2
    exit 1
fi
echo 'Pulse stop passed: agentdir/logs/pulse-stop.log'
