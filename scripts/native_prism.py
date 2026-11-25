"""Launch reference JVMs with the platform's native Glass and Prism backends."""
import ctypes
import os
from pathlib import Path
import sys


GLASS, PRISM = {"darwin": ("Mac", "mtl"), "linux": ("Gtk", "es2"), "win32": ("Win", "d3d")}[sys.platform]


def wsl_reference():
    return PRISM == "es2" and os.environ.get("GODOT_JFX_WSL_NATIVE_ES2") == "1" and Path("/dev/dxg").is_char_device()


def wayland_output_scale(name):
    # Match Godot's current maximum-output scale policy. Open a separate
    # connection by name to read scale without initializing the reference JVM.
    gdk = ctypes.CDLL("libgdk-3.so.0")
    gdk.gdk_display_open.argtypes = [ctypes.c_char_p]
    gdk.gdk_display_open.restype = ctypes.c_void_p
    gdk.gdk_display_close.argtypes = [ctypes.c_void_p]
    gdk.gdk_display_get_n_monitors.argtypes = [ctypes.c_void_p]
    gdk.gdk_display_get_monitor.argtypes = [ctypes.c_void_p, ctypes.c_int]
    gdk.gdk_display_get_monitor.restype = ctypes.c_void_p
    gdk.gdk_monitor_get_scale_factor.argtypes = [ctypes.c_void_p]
    display = gdk.gdk_display_open(os.fsencode(name))
    if not display:
        raise RuntimeError(f"Cannot query Wayland output scale on {name}")
    try:
        monitors = range(gdk.gdk_display_get_n_monitors(display))
        return max(gdk.gdk_monitor_get_scale_factor(gdk.gdk_display_get_monitor(display, i)) for i in monitors)
    finally:
        gdk.gdk_display_close(display)


def properties():
    result = {"glass.platform": GLASS, "prism.order": PRISM}
    if wsl_reference():
        # The stock ES2 qualifier excludes Mesa's "Microsoft Corporation" vendor.
        result.update({"prism.forceGPU": "true", "prism.verbose": "true"})
        if os.environ.get("WAYLAND_DISPLAY"):
            result["glass.gtk.uiScale"] = str(wayland_output_scale(os.environ["WAYLAND_DISPLAY"]))
    return result


def environment():
    if wsl_reference():
        env = {"GALLIUM_DRIVER": "d3d12", "MESA_D3D12_DEFAULT_ADAPTER_NAME": os.environ.get("MESA_D3D12_DEFAULT_ADAPTER_NAME", "Intel")}
        return env
    return {}


if __name__ == "__main__":
    java, *arguments = sys.argv[1:]
    os.execve(java, [java, *(f"-D{k}={v}" for k, v in properties().items()), *arguments], os.environ | environment())
