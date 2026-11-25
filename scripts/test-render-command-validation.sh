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
export GODOT_JFX_GEOMETRY_CACHE='1'
export GODOT_JFX_GEOMETRY_CACHE_MAX='1024'
module_path=$(python3 scripts/maven_local.py module-path)
module_args='--add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path "$module_path" $module_args -encoding UTF-8 -d artifacts/reference tests/reference/RenderCommandValidationProbe.java tests/reference/ShaderStateSuppressionProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" --module-path "$module_path" $module_args --add-opens javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp artifacts/reference RenderCommandValidationProbe > agentdir/logs/render-command-validation.log 2>&1 || {
    echo "Encoder validation failed: agentdir/logs/render-command-validation.log" >&2
    exit 1
}
if ! grep -q 'RENDER_COMMAND_VALIDATION_PASS' agentdir/logs/render-command-validation.log; then
    echo "Encoder validation failed: agentdir/logs/render-command-validation.log" >&2
    exit 1
fi
for suppress in 0 1; do
    log="agentdir/logs/shader-state-suppression-$suppress.log"
    # shellcheck disable=SC2086
    if ! GODOT_JFX_STATE_SUPPRESS=$suppress "$JDK/bin/java" --module-path "$module_path" $module_args -cp artifacts/reference ShaderStateSuppressionProbe > "$log" 2>&1; then
        echo "Shader state suppression check failed: $log" >&2
        exit 1
    fi
done
echo 'Render command validation passed'
