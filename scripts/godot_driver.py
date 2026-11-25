"""Select a Godot driver and verify the active API in the engine's device header."""
import argparse
import os
from pathlib import Path
import re
import sys


WINDOWS_DRIVERS = {"d3d12": "d3d12", "vulkan": "vulkan", "opengl": "opengl3"}
MACOS_DRIVERS = {"metal": "metal", "opengl": "opengl3"}
ENGINE_DRIVERS = WINDOWS_DRIVERS | MACOS_DRIVERS
LINUX_DRIVERS = {"vulkan": "vulkan", "opengl": "opengl3"}
DEFAULT_DRIVER = {"linux": "vulkan", "darwin": "metal"}.get(sys.platform, "d3d12")
DEVICE_APIS = {"D3D12": "d3d12", "Vulkan": "vulkan", "Metal": "metal", "OpenGL API": "opengl"}
DEVICE_LINE = re.compile(r"^\S[^\r\n]*? - Using Device(?: #\d+)?: \S[^\r\n]*", re.MULTILINE)
DRIVER_MARKER = re.compile(r"^GODOT_LIBRARY_DRIVER (\S+)\r?$", re.MULTILINE)
DISPLAY_MARKER = re.compile(r"^GODOT_LIBRARY_DISPLAY_DRIVER (\S+)\r?$", re.MULTILINE)
HOST_LOG = re.compile(r"^(?:GODOT_FIXTURE_LIBRARY |GODOT_LIBRARY_DRIVER |GODOT_LIBRARY_INSTANCE_CREATED|VFX_DEMO_CLOSED)", re.MULTILINE)


def add_driver_argument(parser):
    if sys.platform == "win32":
        drivers = WINDOWS_DRIVERS
    elif sys.platform == "darwin":
        drivers = MACOS_DRIVERS
    elif sys.platform == "linux":
        drivers = LINUX_DRIVERS
    else:
        drivers = ENGINE_DRIVERS  # Offline screenshot comparison.
    parser.add_argument("--driver", choices=drivers, help="select the Godot graphics driver")


def check_driver(output, expected, log, display_driver=None):
    if "A fatal error has been detected by the Java Runtime Environment" in output:
        raise AssertionError(f"{log}: the JVM reported a fatal native error")
    headers = DEVICE_LINE.findall(output)
    if len(headers) != 1:
        raise AssertionError(f"{log}: expected one Using Device line, found {len(headers)}")
    header = headers[0]
    actual = next((driver for api, driver in DEVICE_APIS.items() if header.startswith(api + " ")), None)
    if actual != expected:
        raise AssertionError(f"{log}: expected {expected}, Using Device reports {header!r}")
    markers = DRIVER_MARKER.findall(output)
    if markers != [ENGINE_DRIVERS[actual]]:
        raise AssertionError(f"{log}: Using Device reports {actual}, GODOT_LIBRARY_DRIVER reports {markers}")
    display_driver = display_driver or os.environ.get("GODOT_JFX_TEST_DISPLAY_DRIVER")
    if display_driver and DISPLAY_MARKER.findall(output) != [display_driver]:
        raise AssertionError(f"{log}: expected display driver {display_driver}, found {DISPLAY_MARKER.findall(output)}")
    return actual, header


def check_case_logs(logs, driver, display_driver=None):
    """A scene case can launch several JVMs and also write helper or import logs."""
    evidence = []
    for log in logs:
        output = log.read_text(encoding="utf-8-sig", errors="replace")
        if not HOST_LOG.search(output) and not DEVICE_LINE.search(output):
            continue
        _, header = check_driver(output, driver, log, display_driver)
        evidence.append(f"{log.name}: {header}")
    if not evidence:
        raise AssertionError(f"No Godot launch log with Using Device for {driver} in this run")
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", required=True, choices=ENGINE_DRIVERS)
    parser.add_argument("--display-driver", choices=("Wayland",))
    parser.add_argument("--case-logs", action="store_true", help="ignore auxiliary logs in a regression case")
    parser.add_argument("logs", nargs="*", type=Path)
    args = parser.parse_args()
    try:
        if args.case_logs:
            print("\n".join(check_case_logs(args.logs, args.driver, args.display_driver)))
        elif len(args.logs) == 1:
            log, = args.logs
            check_driver(log.read_text(encoding="utf-8-sig", errors="replace"), args.driver, log, args.display_driver)
        else:
            parser.error("expected one launch log")
    except (OSError, AssertionError) as error:
        sys.exit(str(error))
