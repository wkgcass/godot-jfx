#!/bin/sh
# macOS equivalent of test-window-icon.ps1 (standard scene fixture only; the -Runtime
# isolated project variant is Windows-specific and not ported).
#
# SKIPPED on macOS: NSWindow has no per-window icon concept (the dock icon is
# per-application, set via NSApplication), so the host reports
# get_window_icon_info() -> installed=false by design. This script exists only
# to record that platform gap explicitly instead of silently passing or
# failing; it does not run the probe.
# Usage: test-window-icon.sh [--driver metal|opengl] [--render-thread safe]
set -eu
DRIVER="metal"
RENDER_THREAD="safe"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        --render-thread) RENDER_THREAD="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac
case "$RENDER_THREAD" in safe) ;; *) echo "invalid render thread: $RENDER_THREAD" >&2; exit 2 ;; esac
echo "SKIP: macOS has no per-window icons (NSApplication owns the dock icon); get_window_icon_info reports installed=false by design"
