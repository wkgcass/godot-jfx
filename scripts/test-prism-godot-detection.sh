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
"$JDK/bin/javac" -encoding UTF-8 -d artifacts/reference tests/reference/PrismGodotDetectionProbe.java
"$JDK/bin/java" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp 'artifacts/reference:artifacts/vfx/dependencies/*' PrismGodotDetectionProbe
