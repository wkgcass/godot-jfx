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
module_path=$(python3 scripts/maven_local.py module-path)
options='--add-modules javafx.graphics --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path "$module_path" $options -encoding UTF-8 -d artifacts/reference tests/reference/ScrollSettingsProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" --module-path "$module_path" $options -cp artifacts/reference ScrollSettingsProbe > agentdir/logs/scroll-settings.log 2>&1 || {
    echo "Scroll settings failed: agentdir/logs/scroll-settings.log" >&2
    exit 1
}
if ! grep -q '^SCROLL_SETTINGS_PASS' agentdir/logs/scroll-settings.log; then
    echo "Scroll settings failed: agentdir/logs/scroll-settings.log" >&2
    exit 1
fi
echo 'Scroll settings codec passed'
