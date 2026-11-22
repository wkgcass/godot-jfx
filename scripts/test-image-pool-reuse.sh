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
options='--module-path jfx/build/sdk/lib --add-modules javafx.graphics'
for package in com.sun.javafx.geom com.sun.javafx.geom.transform com.sun.scenario.effect com.sun.scenario.effect.impl; do
    options="$options --add-exports javafx.graphics/$package=ALL-UNNAMED"
done
# shellcheck disable=SC2086
"$JDK/bin/javac" $options -encoding UTF-8 -d artifacts/reference tests/reference/ImagePoolReuseProbe.java
for mode in 1 0; do
    export GODOT_JFX_IMAGE_POOL_LIFO="$mode"
    log="agentdir/logs/image-pool-reuse-$mode.log"
    # shellcheck disable=SC2086
    "$JDK/bin/java" $options --add-opens javafx.graphics/com.sun.scenario.effect.impl=ALL-UNNAMED -cp artifacts/reference ImagePoolReuseProbe > "$log" 2>&1 || {
        echo "Image pool reuse failed: $log" >&2
        exit 1
    }
    if ! grep -q 'IMAGE_POOL_REUSE_PASS' "$log"; then
        echo "Image pool reuse failed: $log" >&2
        exit 1
    fi
done
echo 'Image pool reuse passed in FIFO and LIFO modes'
