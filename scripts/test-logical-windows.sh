#!/bin/sh
# macOS equivalent of test-logical-windows.ps1.
# 陈旧诊断，保留供参考：断言已被独立原生 Stage 替代的历史嵌入式逻辑窗口模型
# （子 Stage 合成进主视口、根窗口合成输入路由到子窗口），在当前架构的双平台
# 全新构建上都会失败，不作为 macOS 验收项。见 docs/logical-windows.md。
# Usage: test-logical-windows.sh [--renderer gl_compatibility|mobile] [--render-thread safe]
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
    --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED \
    -encoding UTF-8 -d artifacts/reference tests/reference/LogicalWindowProbe.java

export GODOT_JFX_JDK="$JDK"
LOG="artifacts/logs/logical-windows-$RENDERER-$RENDER_THREAD.log"
CODE=0
"$GODOT" --path tests/godot res://logical_windows.tscn \
    --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" --quit-after 10000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'GODOT_LOGICAL_WINDOWS_PASS' "$LOG" \
    || ! grep -q 'LOGICAL_WINDOW_PROBE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)' "$LOG"; then
    echo "Logical window test failed: $LOG" >&2
    exit 1
fi
cp artifacts/reference/logical-windows-initial.png "artifacts/reference/logical-windows-$RENDERER-$RENDER_THREAD.png"
echo "Logical windows passed: $LOG"
