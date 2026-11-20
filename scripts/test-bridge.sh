#!/bin/sh
# macOS equivalent of test-bridge.ps1. Each probe is a separate mode; run the
# script once per mode exactly like the Windows switches.
# Usage: test-bridge.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
#        [--stop-from-host|--encoded|--textures|--prism-textures|--shader-states|--prism-context]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
STOP_FROM_HOST=0
ENCODED=0
TEXTURES=0
PRISM_TEXTURES=0
SHADER_STATES=0
PRISM_CONTEXT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --stop-from-host) STOP_FROM_HOST=1 ;;
        --encoded) ENCODED=1 ;;
        --textures) TEXTURES=1 ;;
        --prism-textures) PRISM_TEXTURES=1 ;;
        --shader-states) SHADER_STATES=1 ;;
        --prism-context) PRISM_CONTEXT=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

MODES=$((STOP_FROM_HOST + ENCODED + TEXTURES + PRISM_TEXTURES + SHADER_STATES + PRISM_CONTEXT))
if [ "$MODES" -gt 1 ]; then echo "Probe modes are separate runs." >&2; exit 2; fi

SUFFIX=""
[ "$STOP_FROM_HOST" -eq 1 ] && SUFFIX="$SUFFIX-host-stop"
[ "$ENCODED" -eq 1 ] && SUFFIX="$SUFFIX-encoded"
[ "$TEXTURES" -eq 1 ] && SUFFIX="$SUFFIX-textures"
[ "$PRISM_TEXTURES" -eq 1 ] && SUFFIX="$SUFFIX-prism-textures"
[ "$SHADER_STATES" -eq 1 ] && SUFFIX="$SUFFIX-shaders"
[ "$PRISM_CONTEXT" -eq 1 ] && SUFFIX="$SUFFIX-context"
[ "$RENDERER" != "gl_compatibility" ] && SUFFIX="$SUFFIX-$RENDERER"

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference \
    tests/reference/BridgeProbe.java tests/reference/BridgeStopProbe.java \
    tests/reference/RenderCommandsProbe.java tests/reference/TextureCommandsProbe.java \
    tests/reference/PrismTextureProbe.java tests/reference/ShaderCommandsProbe.java \
    tests/reference/PrismContextProbe.java || { echo "BridgeProbe compilation failed" >&2; exit 1; }

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_TEST_STOP="$STOP_FROM_HOST"
export GODOT_JFX_TEST_ENCODED="$ENCODED"
export GODOT_JFX_TEST_TEXTURES="$TEXTURES"
export GODOT_JFX_TEST_CONTEXT="$PRISM_CONTEXT"
export GODOT_JFX_TEST_SHADER_STATES="$SHADER_STATES"
export GODOT_JFX_TEST_PRISM_TEXTURES="$PRISM_TEXTURES"

LOG="agentdir/logs/m2-bridge$SUFFIX.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --path tests/godot res://bridge.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'M2_BRIDGE_PASS' "$LOG" \
    || ! grep -q 'BRIDGE_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$LOG"; then
    echo "Bridge test failed or incomplete (exit $CODE). See $LOG" >&2
    exit 1
fi
if [ "$STOP_FROM_HOST" -eq 1 ] && ! grep -q 'BRIDGE_STOP_PASS' "$LOG"; then
    echo "Host stop was not observed by Java. See $LOG" >&2
    exit 1
fi
if [ "$ENCODED" -eq 1 ] && ! grep -q 'ENCODER_BACKPRESSURE_OBSERVED' "$LOG"; then
    echo "Native backpressure was not exercised. See $LOG" >&2
    exit 1
fi
if [ "$TEXTURES" -eq 1 ]; then
    cp artifacts/reference/godot-texture-versions.png "artifacts/reference/godot-texture-versions-$RENDERER.png"
fi
if [ "$PRISM_TEXTURES" -eq 1 ]; then
    cp artifacts/reference/godot-prism-textures.png "artifacts/reference/godot-prism-textures-$RENDERER.png"
fi
if [ "$SHADER_STATES" -eq 1 ]; then
    cp artifacts/reference/godot-shader-bridge.png "artifacts/reference/godot-shader-bridge-$RENDERER.png"
fi
if [ "$PRISM_CONTEXT" -eq 1 ]; then
    cp artifacts/reference/godot-prism-context.png "artifacts/reference/godot-prism-context-$RENDERER.png"
fi
echo "M2 bridge test passed. Log: $LOG"
