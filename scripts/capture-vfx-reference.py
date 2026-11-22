#!/usr/bin/env python3
"""Capture the native Mac Glass / Prism Metal VFX page reference images."""
import argparse

from jdk_home import add_jdk_argument, configure_jdk
from macos_probe import LOGS, compile_probe, native_probe, require

parser = argparse.ArgumentParser(description=__doc__)
add_jdk_argument(parser)
parser.add_argument("--page-limit", type=int, default=1000)
parser.add_argument("--freeze-fusion", action="store_true")
args = parser.parse_args()
configure_jdk(args.jdk)
if not 1 <= args.page_limit <= 1000:
    parser.error("--page-limit must be between 1 and 1000")
modules = "javafx.controls,javafx.swing"
compile_probe("VfxReference", modules=modules)
log = LOGS / ("vfx-reference-mtl" + ("-frozen" if args.freeze_fusion else "") + ".log")
require(native_probe("VfxReference", log, modules, ["-Dvfx.reference.backend=mtl",
                     f"-Dvfx.reference.pages={args.page_limit}", f"-Dvfx.freeze.fusion={str(args.freeze_fusion).lower()}"]),
        "VFX_REFERENCE_PASS")
