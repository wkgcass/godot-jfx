#!/bin/sh
set -e
JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
cd "$(dirname "$0")/.."
mkdir -p artifacts/reference artifacts/logs
options='--module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" $options -encoding UTF-8 -d artifacts/reference tests/reference/ScrollSettingsProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" $options -cp artifacts/reference ScrollSettingsProbe > artifacts/logs/scroll-settings.log 2>&1 || {
    echo "Scroll settings failed: artifacts/logs/scroll-settings.log" >&2
    exit 1
}
if ! grep -q '^SCROLL_SETTINGS_PASS' artifacts/logs/scroll-settings.log; then
    echo "Scroll settings failed: artifacts/logs/scroll-settings.log" >&2
    exit 1
fi
echo 'Scroll settings codec passed'
