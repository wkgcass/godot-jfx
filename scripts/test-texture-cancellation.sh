#!/bin/sh
set -e
JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
cd "$(dirname "$0")/.."
mkdir -p artifacts/texture-cancellation-patch artifacts/reference artifacts/logs
source_dir='jfx/modules/javafx.graphics/src/main/java/com/sun/prism/godot'
patch='artifacts/texture-cancellation-patch'
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --patch-module "javafx.graphics=$source_dir" -d "$patch" "$source_dir/GodotTexture.java"
exports='--add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics $exports -d artifacts/reference tests/reference/TextureCancellationProbe.java
# shellcheck disable=SC2086
"$JDK/bin/java" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --patch-module "javafx.graphics=$patch" $exports -cp artifacts/reference TextureCancellationProbe > artifacts/logs/texture-cancellation.log 2>&1 || {
    echo "Texture cancellation test failed: artifacts/logs/texture-cancellation.log" >&2
    exit 1
}
if ! grep -q 'TEXTURE_CANCELLATION_PASS' artifacts/logs/texture-cancellation.log; then
    echo "Texture cancellation test failed: artifacts/logs/texture-cancellation.log" >&2
    exit 1
fi
echo 'Texture cancellation passed'
