#!/bin/sh
set -e
cd "$(dirname "$0")/.."
JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference
export GODOT_JFX_SHADER_SOURCE_CACHE='1'
exports='--add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics $exports -d artifacts/reference tests/reference/ShaderSourceCacheProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" --module-path jfx/build/sdk/lib --add-modules javafx.graphics $exports --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-opens javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-opens javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp artifacts/reference ShaderSourceCacheProbe
