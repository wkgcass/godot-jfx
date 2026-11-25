#!/usr/bin/env python3
"""Check xdg toplevel mapping order in a startup fixture's Wayland client trace."""
import re
import sys
from pathlib import Path

registry = re.compile(r"get_xdg_surface\(new id xdg_surface[#@](\d+), wl_surface[#@](\d+)\)")
role = re.compile(r"xdg_surface[#@](\d+)\.get_toplevel\(new id xdg_toplevel[#@](\d+)\)")
title = re.compile(r'xdg_toplevel[#@](\d+)\.set_title\("([^"]*)"\)')
geometry = re.compile(r"xdg_surface[#@](\d+)\.set_window_geometry\(0, 0, (\d+), (\d+)\)")
attach = re.compile(r"wl_surface[#@](\d+)\.attach\((wl_buffer[#@]\d+|nil|null),")
commit = re.compile(r"wl_surface[#@](\d+)\.commit\(")
destroy = re.compile(r"wl_surface[#@](\d+)\.destroy\(")


def check(lines):
    shells, roles, names = {}, {}, {}
    pending, mapped = {}, set()
    sizes = {}
    scene_sizes = {"StartupProbe": (480, 320), "StartupSecondary": (200, 100)}
    mappings = []
    app_show = False
    for line in lines:
        if line.startswith("STARTUP_PROBE_SHOW "):
            elapsed = int(line.split("=")[1])
            if elapsed < 1200:
                raise ValueError(f"Stage.show called early at {elapsed} ms")
            app_show = True
        elif match := registry.search(line):
            shell, surface = match.groups()
            shells[shell] = surface
            names[surface] = ""
            sizes.pop(surface, None)
        elif match := role.search(line):
            shell, toplevel = match.groups()
            roles[toplevel] = shells[shell]
        elif match := title.search(line):
            toplevel, value = match.groups()
            if toplevel in roles:
                names[roles[toplevel]] = value.removesuffix(" (DEBUG)")
        elif match := geometry.search(line):
            shell, width, height = match.groups()
            if shell in shells:
                sizes[shells[shell]] = (int(width), int(height))
        elif match := attach.search(line):
            surface, buffer = match.groups()
            if surface in names:
                pending[surface] = buffer.startswith("wl_buffer")
        elif match := commit.search(line):
            surface = match[1]
            if surface not in pending:
                continue
            if not pending.pop(surface):
                mapped.discard(surface)
            elif surface not in mapped:
                name = names[surface]
                if not app_show or name not in ("StartupProbe", "StartupSecondary"):
                    raise ValueError(f"Unexpected first buffer commit for {name!r} (app_show={app_show})")
                if sizes.get(surface) != scene_sizes[name]:
                    raise ValueError(f"{name} mapped at {sizes.get(surface)} logical units, expected {scene_sizes[name]}")
                mapped.add(surface)
                mappings.append(name)
        elif match := destroy.search(line):
            surface = match[1]
            mapped.discard(surface)
            pending.pop(surface, None)
            names.pop(surface, None)
    if mappings.count("StartupProbe") < 2 or "StartupSecondary" not in mappings:
        raise ValueError(f"Missing primary remap or secondary mapping: {mappings}")
    print("WAYLAND_STARTUP_MAPPINGS", *mappings)


if __name__ == "__main__":
    try:
        with Path(sys.argv[1]).open(errors="replace") as stream:
            check(stream)
    except (OSError, KeyError, ValueError) as exc:
        sys.exit(str(exc))
