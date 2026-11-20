#!/bin/sh
set -e
cd "$(dirname "$0")/.."
JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference artifacts/logs
export GODOT_JFX_GEOMETRY_CACHE='1'
export GODOT_JFX_GEOMETRY_CACHE_MAX='1024'
module_path=$(python3 scripts/maven_local.py module-path)
module_args='--add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path "$module_path" $module_args -encoding UTF-8 -d artifacts/reference tests/reference/RenderCommandValidationProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" --module-path "$module_path" $module_args --add-opens javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp artifacts/reference RenderCommandValidationProbe > artifacts/logs/render-command-validation.log 2>&1 || {
    echo "Encoder validation failed: artifacts/logs/render-command-validation.log" >&2
    exit 1
}
if ! grep -q 'RENDER_COMMAND_VALIDATION_PASS' artifacts/logs/render-command-validation.log; then
    echo "Encoder validation failed: artifacts/logs/render-command-validation.log" >&2
    exit 1
fi
echo 'Render command validation passed'
