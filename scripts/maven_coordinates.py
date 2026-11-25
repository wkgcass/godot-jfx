#!/usr/bin/env python3
"""Maven coordinates shared by the publisher and the local scene fixtures."""
from configparser import ConfigParser
from pathlib import Path
import re


GROUP_ID = "io.vproxy"
GROUP_PATH = Path(*GROUP_ID.split("."))
CLASSIFIER_HASH_KEYS = {
    "win": "windowsClassifierSha256",
    "mac-aarch64": "macArm64ClassifierSha256",
    "linux": "linuxX64ClassifierSha256",
}


def artifact_id(module):
    return f"godot-jfx-{module}"


def release_version():
    path = Path(__file__).resolve().parents[1] / "release.properties"
    config = ConfigParser(interpolation=None)
    config.read_string("[release]\n" + path.read_text(encoding="utf-8"), source=str(path))
    release = config["release"]
    port = release["port.version"]
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]*", port):
        raise ValueError(f"{path}: invalid port.version {port!r}")
    parts = [port]
    for key in ("godot.upstream.commit", "jfx.upstream.commit"):
        commit = release[key]
        if not re.fullmatch(r"[0-9a-fA-F]{40}", commit):
            raise ValueError(f"{path}: expected a full Git commit hash for {key}")
        parts.append(commit[:8].lower())
    return "-".join(parts)
