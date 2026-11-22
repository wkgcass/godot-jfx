#!/bin/sh
set -e
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
JDK="$JAVA_HOME"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -d artifacts/reference tests/reference/TimerCadenceProbe.java
"$JDK/bin/java" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED --add-opens javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -cp artifacts/reference TimerCadenceProbe
