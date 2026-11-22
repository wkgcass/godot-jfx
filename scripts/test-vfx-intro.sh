#!/bin/sh
# macOS equivalent of test-vfx-intro.ps1.
# Usage: test-vfx-intro.sh [--driver metal|opengl] [--render-thread safe] [--jdk DIRECTORY]
#        [--all-pages] [--page-limit N] [--freeze-fusion]
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."

JDK="$JAVA_HOME"
DRIVER="metal"
RENDER_THREAD="safe"
ALL_PAGES=0
PAGE_LIMIT=0
FREEZE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        --all-pages) ALL_PAGES=1 ;;
        --page-limit) PAGE_LIMIT="$2"; shift ;;
        --freeze-fusion) FREEZE=1 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
[ -x "$JDK/bin/javac" ] || { echo "javac not found under $JDK" >&2; exit 1; }
mkdir -p artifacts/reference agentdir/logs

if [ "$FREEZE" -eq 1 ]; then export GODOT_JFX_VFX_FREEZE=1; else export GODOT_JFX_VFX_FREEZE=0; fi
if [ "$ALL_PAGES" -eq 1 ]; then
    PAGES=$(grep -c 'mainScenes\.add(new' vfx/src/test/java/io/vproxy/vfx/intro/IntroFXMain.java)
else
    PAGES=2
fi
if [ "$PAGE_LIMIT" -ne 0 ]; then
    if [ "$ALL_PAGES" -ne 1 ] || [ "$PAGE_LIMIT" -lt 3 ] || [ "$PAGE_LIMIT" -gt "$PAGES" ]; then
        echo "PageLimit requires AllPages and a valid count of at least 3" >&2; exit 2
    fi
    PAGES=$PAGE_LIMIT
fi
export GODOT_JFX_VFX_PAGES="$PAGES"

if [ "$ALL_PAGES" -eq 1 ]; then
    CLASSPATH="artifacts/vfx/classes/java/main:artifacts/vfx/classes/java/test:artifacts/vfx/dependencies/*"
    "$JDK/bin/javac" --module-path jfx/build/sdk/lib --add-modules javafx.controls \
        --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED \
        -cp "$CLASSPATH" -encoding UTF-8 -d artifacts/reference tests/reference/VfxNavigationProbe.java \
        || { echo "VFX navigation observer compilation failed" >&2; exit 1; }
fi

COVERAGE=""
[ "$ALL_PAGES" -eq 1 ] && COVERAGE="-all-pages"
[ "$PAGE_LIMIT" -ne 0 ] && COVERAGE="$COVERAGE-$PAGE_LIMIT"
[ "$FREEZE" -eq 1 ] && COVERAGE="$COVERAGE-frozen"
LOG="agentdir/logs/vfx-intro-$DRIVER-$RENDER_THREAD$COVERAGE.log"

run_watchdog() {
    wlog="$1"; limit="$2"; shift 2
    "$@" >"$wlog" 2>&1 &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$limit" ]; then
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wcode=0
    wait "$pid" || wcode=$?
    return "$wcode"
}

CODE=0
run_watchdog "$LOG" 240 python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://vfx_intro.tscn \
    --render-thread "$RENDER_THREAD" --quit-after 30000 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! grep -q 'VFX_INTRO_SMOKE_PASS' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)' "$LOG"; then
    echo "VFX Intro smoke failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/vfx-intro.png "artifacts/reference/vfx-intro-$DRIVER.png"
cp artifacts/reference/vfx-intro-next.png "artifacts/reference/vfx-intro-next-$DRIVER.png"
echo "VFX Intro smoke passed: $LOG"
