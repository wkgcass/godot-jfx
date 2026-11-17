#!/bin/sh
# macOS equivalent of test-startup.ps1. Window visibility is sampled through
# CGWindowList (scripts/macos-window-titles.m) instead of Win32 EnumWindows.
# Window titles are validated only when macOS exposes them to us: without
# screen-recording permission the system redacts other processes' window
# names, in which case only the visibility timing is enforced (noted in the
# output).
# Usage: test-startup.sh [--renderer mobile|gl_compatibility] [--render-thread safe]
set -eu
cd "$(dirname "$0")/.."

JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
RENDERER="mobile"
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
mkdir -p artifacts/reference artifacts/logs artifacts/native-tests

HELPER="artifacts/native-tests/macos-window-titles"
if [ ! -x "$HELPER" ] || [ scripts/macos-window-titles.m -nt "$HELPER" ]; then
    clang -O2 -framework Foundation -framework CoreGraphics \
        scripts/macos-window-titles.m -o "$HELPER"
fi

"$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
    -d artifacts/reference tests/reference/StartupProbe.java

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

run_case() {
    case_name="$1" mode="$2" cancel="$3"
    prefix="artifacts/logs/startup-$case_name-$RENDERER-$RENDER_THREAD"
    GODOT_JFX_JDK="$JDK" GODOT_JFX_STARTUP="$mode" GODOT_JFX_STARTUP_CANCEL="$cancel" \
        "$GODOT" --path tests/godot res://startup.tscn \
        --rendering-method "$RENDERER" --render-thread "$RENDER_THREAD" >"$prefix.log" 2>&1 &
    pid=$!
    start=$(now_ms)
    visible=0
    titles_known=0
    failed=""
    while kill -0 "$pid" 2>/dev/null; do
        titles=$("$HELPER" "$pid")
        if [ -n "$titles" ]; then
            visible=1
            elapsed=$(( $(now_ms) - start ))
            if [ "$elapsed" -lt 1200 ]; then
                failed="Window visible before application show (${elapsed} ms)"
                break
            fi
            if printf '%s\n' "$titles" | grep -qv '^Startup'; then
                # "(unknown)" lines mean macOS redacted the window names; any
                # other unexpected title is a failure.
                bad=$(printf '%s\n' "$titles" | grep -v '^Startup' | grep -v '^(unknown)$' || true)
                if [ -n "$bad" ]; then
                    failed="Unexpected startup window at ${elapsed} ms: $bad"
                    break
                fi
            fi
            if printf '%s\n' "$titles" | grep -qE '^Startup(Probe|Secondary)?( \(DEBUG\))?$'; then
                titles_known=1
            fi
        fi
        if [ $(( $(now_ms) - start )) -gt 30000 ]; then
            failed="Startup test timed out"
            break
        fi
        sleep 0.02 2>/dev/null || sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    CODE=0
    wait "$pid" || CODE=$?
    if [ -z "$failed" ]; then
        if [ "$CODE" -ne 0 ]; then
            failed="native exit $CODE"
        elif [ "$visible" -ne 1 ]; then
            failed="no window ever became visible"
        elif ! grep -q "STARTUP_PASS mode=$mode" "$prefix.log"; then
            failed="missing STARTUP_PASS mode=$mode"
        elif grep -qE '^(ERROR:|SCRIPT ERROR:|Exception)' "$prefix.log"; then
            failed="error output present"
        fi
    fi
    if [ -n "$failed" ]; then
        echo "Startup test failed ($case_name): $failed. See $prefix.log" >&2
        return 1
    fi
    note=""
    if [ "$titles_known" -ne 1 ]; then
        note=" (window titles unavailable: screen-recording permission missing; timing enforced)"
    fi
    echo "STARTUP_PASS $case_name $RENDERER $RENDER_THREAD (native visibility sampled every 20 ms)$note"
}

for case_spec in "logo logo 0" "hidden hidden 0" "logo-cancel logo 1" "hidden-cancel hidden 1"; do
    set -- $case_spec
    run_case "$1" "$2" "$3"
done
