"""Measure the composited drag image over the GTK target on a scale-one output."""
import io
import os
from pathlib import Path
import subprocess
import sys
from PIL import Image, ImageChops

x, y = map(int, sys.argv[1:3])
env = os.environ.copy()
root = env.get("GODOT_JFX_LABWC_ROOT")
grim = "grim"
if root:
    grim = str(Path(root) / "usr/bin/grim")
    env["LD_LIBRARY_PATH"] = str(Path(root) / "usr/lib/x86_64-linux-gnu") + ":" + env.get("LD_LIBRARY_PATH", "")
with_cursor = env.get("GODOT_JFX_WAYLAND_MEASURE_DRAG_WITH_CURSOR") == "1"
radius = 32 if with_cursor else 20
crop = f"{x-radius},{y-radius} {2*radius+1}x{2*radius+1}"
command = [grim, "-s", "1", "-g", crop, "-t", "ppm"]
if with_cursor:
    command.append("-c")
shot = subprocess.run([*command, "-"], env=env, check=True, capture_output=True, timeout=3)
image = Image.open(io.BytesIO(shot.stdout)).convert("RGB")
if with_cursor:
    # Check the four visible ticks in the same exposure as the application icon.
    for dx, dy in ((-27, 0), (27, 0), (0, -27), (0, 27)):
        if image.getpixel((radius + dx, radius + dy)) != (255, 0, 255):
            sys.exit(1)
    image.save("artifacts/reference/wayland-drag-image-with-pointer.png")
    image = image.crop((12, 12, 53, 53))
background = image.getpixel((0, 0))
delta = ImageChops.difference(image, Image.new("RGB", image.size, background))
box = delta.getbbox()
if box is None:
    sys.exit(1)
left, top, right, bottom = box
if not (0 < left <= 20 < right < image.width and 0 < top <= 20 < bottom < image.height):
    sys.exit(1)
# Verify a uniformly filled rectangle against the known translucent gray
# source color. A focus border, pointer glyph or decoration cannot qualify.
tile = image.crop(box)
if len(tile.getcolors(2) or ()) != 1:
    sys.exit(1)
if any(abs(channel - (128 * 128 + base * 127) / 255) > 3
       for channel, base in zip(tile.getpixel((0, 0)), background)):
    sys.exit(1)
tile.save("artifacts/reference/wayland-drag-image.png")
print(tile.width, tile.height, len(tile.tobytes()))
