#!/bin/sh
# macOS equivalent of test-scene-textures.ps1.
# Usage: test-scene-textures.sh [--renderer gl_compatibility|mobile] [--missing-scene] [--resize]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
MISSING=0
RESIZE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --missing-scene) MISSING=1 ;;
        --resize) RESIZE=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.graphics \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/SceneTextureProbe.java || { echo "Scene texture probe compilation failed" >&2; exit 1; }

export GODOT_JFX_JDK="$JDK"
export GODOT_JFX_SCENE_MISSING="$MISSING"
export GODOT_JFX_SCENE_RESIZE="$RESIZE"
SUFFIX=""
if [ "$MISSING" -eq 1 ]; then SUFFIX="-missing"; elif [ "$RESIZE" -eq 1 ]; then SUFFIX="-resize"; fi
LOG="artifacts/logs/scene-textures-$RENDERER$SUFFIX.log"
CODE=0
"$GODOT" --path tests/godot res://scene_textures.tscn \
    --rendering-method "$RENDERER" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
if [ "$MISSING" -eq 1 ]; then
    if [ "$CODE" -ne 0 ] \
        || ! grep -q 'SCENE_TEXTURE_FAILURE_PASS' "$LOG" \
        || grep -qE '^(SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
        echo "Scene failure probe failed. See $LOG" >&2
        exit 1
    fi
else
    if [ "$CODE" -ne 0 ] \
        || ! grep -q 'GODOT_SCENE_TEXTURE_PASS' "$LOG" \
        || ! grep -q 'SCENE_TEXTURE_PROBE_PASS' "$LOG" \
        || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
        echo "Scene texture probe failed. See $LOG" >&2
        exit 1
    fi
    cp artifacts/reference/godot-scene-textures.png "artifacts/reference/godot-scene-textures-$RENDERER$SUFFIX.png"
fi
echo "Scene texture probe passed: $LOG"
