#!/bin/sh
set -e
JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
cd "$(dirname "$0")/.."
patch='artifacts/reference/lcd-shader-format-patch'
resource='com/sun/prism/godot/shaders'
mkdir -p "$patch/$resource" artifacts/logs artifacts/reference
for name in Solid_TextureSecondPassLCD Solid_TextureSecondPassLCD_AlphaTest; do
    stock="jfx/build/modular-sdk/modules/javafx.graphics/$resource/$name.gdshader"
    if ! grep -q 'uniform sampler2D dstColor;' "$stock"; then
        echo "Stock shader fixture no longer matches: $name" >&2
        exit 1
    fi
    sed 's/uniform sampler2D dstColor;/uniform sampler2D dstColor ;/' "$stock" > "$patch/$resource/$name.gdshader"
done
module_args='--module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED'
# shellcheck disable=SC2086
"$JDK/bin/javac" $module_args -encoding UTF-8 -d artifacts/reference tests/reference/LcdShaderLoadProbe.java
for mode in 0 1; do
    export GODOT_JFX_LCD_SCREEN="$mode"
    for altered in false true; do
        extra=''
        expect=''
        if [ "$altered" = 'true' ]; then
            extra="--patch-module javafx.graphics=$patch"
            if [ "$mode" = '1' ]; then
                expect='reject'
            fi
        fi
        log="artifacts/logs/lcd-shader-load-$mode-$altered.log"
        # shellcheck disable=SC2086
        "$JDK/bin/java" $module_args $extra -cp artifacts/reference LcdShaderLoadProbe $expect > "$log" 2>&1 || {
            echo "LCD shader loading failed: $log" >&2
            exit 1
        }
        if ! grep -q 'LCD_SHADER_LOAD_PASS' "$log"; then
            echo "LCD shader loading failed: $log" >&2
            exit 1
        fi
    done
done
echo 'LCD shader loading passed: stock and changed format, both LCD modes'
