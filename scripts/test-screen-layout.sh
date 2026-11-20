#!/bin/sh
set -e
cd "$(dirname "$0")/.."
JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference artifacts/logs
module_path=$(python3 scripts/maven_local.py module-path)
exports='--add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path "$module_path" --add-modules javafx.graphics $exports -d artifacts/reference tests/reference/ScreenLayoutProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" --module-path "$module_path" --add-modules javafx.graphics $exports -cp artifacts/reference ScreenLayoutProbe > artifacts/logs/screen-layout.log 2>&1 || {
    echo "Screen layout probe failed: artifacts/logs/screen-layout.log" >&2
    exit 1
}
if ! grep -q 'SCREEN_LAYOUT_PROBE_PASS' artifacts/logs/screen-layout.log; then
    echo "Screen layout probe failed: artifacts/logs/screen-layout.log" >&2
    exit 1
fi
echo 'Screen layout passed: artifacts/logs/screen-layout.log'
