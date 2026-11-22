#!/usr/bin/env python3
"""Visual triage, not a pass/fail oracle (Demo data includes time and randomness)."""
from godot_driver import DEFAULT_DRIVER, add_driver_argument
import argparse
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops, ImageStat

parser = argparse.ArgumentParser()
add_driver_argument(parser)
parser.add_argument("--frozen", action="store_true", help="Compare diagnostic captures with FusionButton animation disabled")
args = parser.parse_args()
driver = args.driver or DEFAULT_DRIVER
root = Path(__file__).resolve().parents[1] / "artifacts/reference"
actual = root / ("vfx-pages-" + ("frozen-" if args.frozen else "") + "godot-" + driver)
native = "mtl" if driver == "metal" or (driver == "opengl" and sys.platform == "darwin") else "d3d"
reference = root / ("vfx-pages-" + native + ("-frozen" if args.frozen else ""))
suffix = driver + ("-frozen" if args.frozen else "")
records = []
manifest = json.loads((actual / "run.json").read_text(encoding="utf-8"))
if manifest["status"] != "passed":
    raise SystemExit("Navigation run is incomplete; refuse stale or partial captures")
baseline = json.loads((reference / "run.json").read_text(encoding="utf-8"))
if baseline.get("status") != "passed" or baseline.get("pages") != manifest["pages"]:
    raise SystemExit("Reference run is incomplete or has a different page count")
scale = manifest.get("system_scale", 1)
if baseline.get("system_scale", 1) != scale:
    raise SystemExit("Reference and actual system scales differ")
sheet = Image.new("RGB", (960, ((manifest["pages"] + 4) // 5) * 220), "white")
draw = ImageDraw.Draw(sheet)
for index in range(manifest["pages"]):
    path = actual / f"{index:02d}.png"
    other = reference / path.name
    if not other.exists():
        raise SystemExit(f"Missing reference: {other}")
    with Image.open(path) as source, Image.open(other) as expected:
        a, b = source.convert("RGB"), expected.convert("RGB")
        if a.size != b.size:
            records.append({"page": int(path.stem), "size_mismatch": [a.size, b.size]})
            continue
        # Exclude observer title and navigation controls, which differ by design.
        area = (0, round(35*scale), min(a.width,round(1280*scale)), min(a.height,round(710*scale)))
        diff = ImageChops.difference(a.crop(area), b.crop(area))
        mean = sum(ImageStat.Stat(diff).mean) / (3 * 255)
        records.append({"page": int(path.stem), "mean_absolute_rgb_error": mean})
        x, y = index % 5 * 192, index // 5 * 220
        draw.text((x+4,y+2), f"Page {path.stem} Godot / {native.upper()}", fill="black")
        a.thumbnail((192, 100))
        b.thumbnail((192, 100))
        sheet.paste(a, (x,y+18))
        sheet.paste(b, (x,y+119))
sheet.save(root / ("vfx-comparison-" + suffix + ".png"))
report = root / ("vfx-comparison-" + suffix + ".json")
report.write_text(json.dumps(records, indent=2), encoding="utf-8")
print(json.dumps(records, indent=2))
