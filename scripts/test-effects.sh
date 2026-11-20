#!/bin/sh
# macOS equivalent of test-effects.ps1. The native reference capture uses the
# stock macOS Prism pipeline (Metal by default) instead of D3D; the Godot
# scene still reads artifacts/reference/d3d-effects.png, so the reference
# keeps that file name.
# Usage: test-effects.sh [--renderer gl_compatibility|mobile] [--render-thread safe] [--runtime]
set -u
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
RUNTIME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --runtime) RUNTIME=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/EffectsProbe.java || { echo "Effects probe compilation failed" >&2; exit 1; }

CODE=0
"$JDK/bin/java" -Dglass.platform=Mac --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    -Deffects.reference=artifacts/reference/d3d-effects.png \
    -cp artifacts/reference EffectsProbe >agentdir/logs/effects-mac-native.log 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] || ! grep -q 'EFFECTS_REFERENCE_PASS' agentdir/logs/effects-mac-native.log; then
    echo "Native effects reference failed: agentdir/logs/effects-mac-native.log" >&2
    exit 1
fi

export GODOT_JFX_JDK="$JDK"
SUFFIX=""
[ "$RUNTIME" -eq 1 ] && SUFFIX="-runtime"
LOG="$PWD/agentdir/logs/effects-$RENDERER$SUFFIX.log"
if [ "$RUNTIME" -eq 1 ]; then
    FIXTURE="$PWD/artifacts/runtime-effects"
    mkdir -p "$FIXTURE"
    cp tests/godot/effects.tscn tests/godot/effects_test.gd "$FIXTURE/"
    sed 's|res://main.tscn|res://effects.tscn|' tests/godot/project.godot > "$FIXTURE/project.godot"
    CODE=0
    "$PWD/godot/bin/godot.macos.editor.arm64" --headless --path "$FIXTURE" --editor --import >"$LOG.import" 2>&1 || CODE=$?
    if [ "$CODE" -ne 0 ]; then echo "Effects runtime import failed: $LOG.import" >&2; exit 1; fi
    CODE=0
    (cd "$FIXTURE" && python3 "$FIXTURE_LAUNCHER" \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1) || CODE=$?
else
    CODE=0
    python3 "$FIXTURE_LAUNCHER" --path tests/godot res://effects.tscn \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
fi
echo "EFFECTS_NATIVE_EXIT_CODE $CODE" >>"$LOG"
if [ -f artifacts/reference/godot-effects.png ]; then
    cp artifacts/reference/godot-effects.png "artifacts/reference/godot-effects-$RENDERER$SUFFIX.png"
fi
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_EFFECTS_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "Effects probe failed (native exit $CODE). See $LOG" >&2
    exit 1
fi
echo "Effects probe passed: $LOG"
