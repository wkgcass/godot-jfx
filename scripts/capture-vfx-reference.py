#!/usr/bin/env python3
"""Capture VFX page reference images with the host platform's native JavaFX pipeline."""
import argparse

from jdk_home import add_jdk_argument, configure_jdk
from macos_probe import LOGS, NATIVE_PRISM, compile_probe, native_probe, require

parser = argparse.ArgumentParser(description=__doc__)
add_jdk_argument(parser)
parser.add_argument("--page-limit", type=int, default=1000)
parser.add_argument("--freeze-fusion", action="store_true")
parser.add_argument("--content-size", type=int, nargs=2, metavar=("WIDTH", "HEIGHT"),
                    help="resize the reference window to match the Godot scene in logical pixels")
args = parser.parse_args()
configure_jdk(args.jdk)
if not 1 <= args.page_limit <= 1000:
    parser.error("--page-limit must be between 1 and 1000")
size = []
if args.content_size:
    width, height = args.content_size
    if min(width, height) <= 0:
        parser.error("--content-size requires positive dimensions")
    size = [f"-Dvfx.reference.width={width}", f"-Dvfx.reference.height={height}"]
modules = "javafx.controls,javafx.swing"
compile_probe("VfxReference", modules=modules)
log = LOGS / ("vfx-reference-" + NATIVE_PRISM + ("-frozen" if args.freeze_fusion else "") + ".log")
require(native_probe("VfxReference", log, modules, [*size, f"-Dvfx.reference.backend={NATIVE_PRISM}",
                     f"-Dvfx.reference.pages={args.page_limit}", f"-Dvfx.freeze.fusion={str(args.freeze_fusion).lower()}"]),
        "VFX_REFERENCE_PASS")
