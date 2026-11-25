"""Verify the source editor's GPU, toplevel lifetimes and minimize request from its protocol trace."""
from pathlib import Path
import re
import sys

from godot_driver import DEVICE_LINE, LINUX_DRIVERS

requested, log = sys.argv[1:]
trace = Path(log).read_text(errors="replace")
driver = LINUX_DRIVERS[requested]
method = "mobile" if requested == "vulkan" else "gl_compatibility"
api = "Vulkan" if requested == "vulkan" else "OpenGL API"
headers = DEVICE_LINE.findall(trace)
devices = re.findall(rf"^WAYLAND_WINDOWS server=Wayland driver={driver} method={method} gpu=(.+)$", trace, re.M)
if len(headers) != 1 or not headers[0].startswith(api + " ") or len(devices) != 1 or devices[0] not in headers[0]:
    sys.exit(f"Wayland editor device mismatch for {requested}: headers={headers}, devices={devices}")
if re.search(r"^(?:ERROR|SCRIPT ERROR|SHADER ERROR):", trace, re.M) or "WAYLAND_NATIVE_WINDOWS_PASS" not in trace.splitlines():
    sys.exit("The native window probe failed or emitted an engine error.")


def toplevels(title):
    return re.findall(r'(xdg_toplevel[#@]\d+)\.set_title\("' + re.escape(title) + r'"\)', trace)


owners = toplevels("Wayland owner")
children = toplevels("Wayland owned child")
peers = toplevels("Wayland independent peer")
if len(owners) != 1 or len(children) != 2 or len(peers) != 1:
    sys.exit("Missing owner, peer or recreated child toplevel in the protocol trace.")
for child in set(children):
    if trace.count(f"{child}.set_parent({owners[0]})") != children.count(child):
        sys.exit("The compositor did not receive the transient parent for each child surface.")
if f"{owners[0]}.set_minimized()" not in trace or f"{peers[0]}.set_minimized()" in trace:
    sys.exit("Expected a minimize request only for the owner.")
# The fixture enables modality on a mapped child, remaps it, then clears it.
roles = re.findall(r'xdg_wm_dialog_v1[#@]\d+\.get_xdg_dialog\(new id (xdg_dialog_v1[#@]\d+), (xdg_toplevel[#@]\d+)\)', trace)
if re.search(r'wl_registry[#@]\d+\.global\(\d+, "xdg_wm_dialog_v1"', trace):
    if [child for _, child in roles] != children:
        sys.exit("Missing modal role on the original or remapped child.")
    live = set()
    marked = set()
    for line in trace.splitlines():
        created = re.search(r'\.get_xdg_dialog\(new id (xdg_dialog_v1[#@]\d+)', line)
        if created:
            dialog = created[1]
            if dialog in live:
                sys.exit("Duplicate live dialog object.")
            live.add(dialog)
        operation = re.search(r'-> (xdg_dialog_v1[#@]\d+)\.(set_modal|destroy)\(\)', line)
        if operation:
            dialog, name = operation.groups()
            if dialog not in live:
                sys.exit("Request on an unknown dialog.")
            if name == "set_modal":
                marked.add(dialog)
            elif dialog in marked:
                marked.remove(dialog)
                live.remove(dialog)
            else:
                sys.exit("Child dialog destroyed before it was marked modal.")
    if live or marked:
        sys.exit("A native dialog role survived its child.")
    print("WAYLAND_DIALOG_ROLE_PASS")
elif roles:
    sys.exit("Dialog protocol requests on a compositor without the extension.")
print(headers[0])
print("WAYLAND_TOPLEVEL_PROTOCOL_PASS")
