#!/bin/sh
# macOS equivalent of test-window-composition.ps1.
# 陈旧诊断，保留供参考：用伪造句柄（90001/90002）创建次级 Presentable 并断言其
# 作为合成图层进入主视口——该嵌入式合成模型已被独立原生 Stage 替代，在当前架构
# 全新构建上同样失败，不作为 macOS 验收项。见 docs/logical-windows.md。
# Usage: test-window-composition.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-/Users/wkgcass/OpenSource/godot-jfx/.tools/jdk-25/Contents/Home}"
RENDERER="gl_compatibility"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --renderer) RENDERER="$2"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$RENDERER" in gl_compatibility|mobile) ;; *) echo "invalid renderer: $RENDERER" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

GODOT="./godot/bin/godot.macos.editor.arm64"
[ -x "$GODOT" ] || { echo "Godot binary not found: $GODOT" >&2; exit 1; }
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference artifacts/logs

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED \
    --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/WindowCompositionProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/window-composition-$RENDERER-$RENDER_THREAD.log"
CODE=0
"$GODOT" --path tests/godot res://window_composition.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_WINDOW_COMPOSITION_PASS' "$LOG" \
    || ! grep -q 'WINDOW_COMPOSITION_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Window composition test failed: $LOG" >&2
    exit 1
fi
for stage in 0 1 2 3 4 5; do
    cp "artifacts/reference/window-composition-$stage.png" "artifacts/reference/window-composition-$RENDERER-$RENDER_THREAD-$stage.png"
done
echo "Window composition passed: $LOG"
