#!/bin/sh
set -e
cd "$(dirname "$0")/.."
JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference artifacts/logs
options='--module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.shader=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" $options -encoding UTF-8 -d artifacts/reference tests/reference/ShaderStateProbe.java
# shellcheck disable=SC2086
if ! "$JDK/bin/java" $options -cp artifacts/reference ShaderStateProbe jfx/build/sdk/lib/javafx.graphics.jar > artifacts/logs/m2-shader-state.log 2>&1; then
    echo 'ShaderStateProbe failed; see artifacts/logs/m2-shader-state.log' >&2
    exit 1
fi
cat artifacts/logs/m2-shader-state.log
