"""Exercise Weston's task switcher on the isolated Wayland seat of the VFX fixture."""
import os
from pathlib import Path
import re
import signal
import subprocess
import sys


class WestonSwitcher:
    def __init__(self):
        control = Path(os.environ["XDG_RUNTIME_DIR"], "seat.fifo")
        if (os.environ.get("GODOT_JFX_WESTON_SEAT") != str(control) or not control.is_fifo()
                or os.environ.get("WAYLAND_DISPLAY") != "godot-private"
                or Path("/mnt/wslg/runtime-dir/wayland-0").exists()):
            raise RuntimeError("Run this test inside wsl-wayland-session.sh --isolate-wslg")
        self.control = os.open(control, os.O_WRONLY | os.O_NONBLOCK)

    def select(self, tabs):
        os.write(self.control, str(tabs).encode("ascii"))

    def close(self):
        os.close(self.control)


def check(stream, seat):
    # Map protocol objects from this client's trace. The VFX control window
    # is the one that issued set_minimized, regardless of its object IDs.
    surfaces = {}
    toplevels = {}
    child = focused = None
    phase = "minimize"
    for line in stream:
        sys.stdout.write(line)
        match = re.search(r"get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)", line)
        if match:
            surfaces[match[1]] = match[2]
        match = re.search(r"xdg_surface#(\d+)\.get_toplevel\(new id xdg_toplevel#(\d+)\)", line)
        if match:
            toplevels[match[2]] = surfaces[match[1]]
        match = re.search(r"xdg_toplevel#(\d+)\.set_minimized\(", line)
        if match:
            child = toplevels[match[1]]
        match = re.search(r"wl_keyboard#\d+\.enter\(\d+, wl_surface#(\d+)", line)
        if match:
            focused = match[1]
        elif re.search(r"wl_keyboard#\d+\.leave\(", line):
            focused = None

        if phase == "minimize" and line.startswith("VFX_WINDOW_MODE step=3 "):
            if child is None or len(toplevels) != 2:
                raise AssertionError("Expected two native Stages and a child minimize request")
            seat.select(1)
            phase = "other window"
        elif phase == "other window" and line.startswith("VFX_CONTROLS_STATE step=4 "):
            if focused in set(toplevels.values()) - {child}:
                if 'title=VfxControls 3 ' not in line or '"mode": 1' not in line:
                    raise AssertionError("Selecting the other Stage cleared child minimization")
                print("WESTON_OTHER_STAGE_CHILD_MINIMIZED", flush=True)
                seat.select(2)
                phase = "restore"
        elif line.startswith("VFX_WINDOW_MODE step=4 "):
            if phase != "restore" or focused != child or "mode=0 " not in line:
                raise AssertionError("VFX reported restore before Weston selected the child")
            phase = "close"
    if phase != "close":
        raise AssertionError(f"Weston did not finish the VFX restore sequence ({phase})")


def main():
    seat = WestonSwitcher()
    try:
        with subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
                              text=True, errors="replace", env=os.environ | {"WAYLAND_DEBUG": "client"}) as fixture:
            try:
                check(fixture.stdout, seat)
                return fixture.wait()
            finally:
                if fixture.poll() is None:
                    os.killpg(fixture.pid, signal.SIGTERM)
    finally:
        seat.close()


if __name__ == "__main__":
    sys.exit(main())
