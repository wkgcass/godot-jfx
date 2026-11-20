#!/usr/bin/env python3
"""Print the repository-relative paths to the requested audio fixtures, in order."""
import argparse
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import wave


ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "agentdir/media"
LOGS = ROOT / "agentdir/logs"
FILES = {"wav": "media-silence.wav", "churn": "media-churn-silence.wav",
         "mp3": "media-tone.mp3", "aiff": "media-tone.aiff"}


def write_wav(path, *, tone=False):
    frames = bytes(44100 * 2 * 2)
    if tone:
        frames = b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 440 * i / 44100)))
                          for i in range(44100 * 2))
    with wave.open(str(path), "wb") as wav:
        wav.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
        wav.writeframes(frames)


def build_windows_encoder(work):
    properties = (ROOT / "jfx/build/windows_tools.properties").read_text(encoding="utf-8")
    config = dict(line.split("=", 1) for line in properties.splitlines() if "=" in line)
    env = os.environ.copy()
    for name in ("PATH", "INCLUDE", "LIB"):
        env[name] = config["WINDOWS_VS_" + name]
    compiler = shutil.which("cl.exe", path=env["PATH"])
    if not compiler:
        raise FileNotFoundError("cl.exe missing from the JFX build toolchain")
    exe = work / "make_audio_fixture.exe"
    with (LOGS / "audio-fixture-build.log").open("wb") as log:
        subprocess.run([compiler, "/nologo", "/std:c++17", "/EHsc", "/O2", "/W4",
                        ROOT / "tests/native/make_audio_fixture.cpp", f"/Fe:{exe}",
                        f"/Fo:{work / 'make_audio_fixture.obj'}", "/link",
                        "mfplat.lib", "mfreadwrite.lib", "mfuuid.lib", "ole32.lib"],
                       stdout=log, stderr=subprocess.STDOUT, env=env, check=True)
    return exe


def encode_tone(kind, staged, encoder):
    with (LOGS / f"audio-fixture-{kind}.log").open("wb") as log:
        if encoder:
            result = subprocess.run([encoder, kind, staged], stdout=subprocess.PIPE, stderr=log, check=True)
            log.write(result.stdout)
            if f"MAKE_AUDIO_FIXTURE_PASS codec={kind} rate=44100 seconds=2".encode() not in result.stdout:
                raise ValueError(f"Incomplete {kind} fixture")
            return
        if kind == "mp3":
            command = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                       "sine=frequency=440:sample_rate=44100:duration=2", "-ac", "1", "-c:a", "libmp3lame", staged]
        else:
            source = staged.parent / "tone.wav"
            write_wav(source, tone=True)
            command = ["afconvert", "-f", "AIFF", "-d", "BEI16@44100", "-c", "1", source, staged]
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        rate = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "a:0",
                                        "-show_entries", "stream=sample_rate", "-of", "csv=p=0", staged], stderr=log)
        if rate.strip() != b"44100":
            raise ValueError(f"Incorrect sample rate for {kind}: {rate!r}")
        log.write(f"MAKE_AUDIO_FIXTURE_PASS codec={kind} rate=44100 seconds=2\n".encode())


def prepare(kinds):
    outputs = [MEDIA / FILES[kind] for kind in kinds]
    missing = [(kind, path) for kind, path in zip(kinds, outputs) if not path.is_file()]
    if missing:
        MEDIA.mkdir(parents=True, exist_ok=True)
        LOGS.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=MEDIA) as temporary:
            work = Path(temporary)
            encoder = None
            for kind, path in missing:
                if path.is_file():
                    continue
                staged = work / path.name
                if path.suffix == ".wav":
                    write_wav(staged)
                else:
                    if os.name == "nt" and encoder is None:
                        encoder = build_windows_encoder(work)
                    encode_tone(kind, staged, encoder)
                if not path.is_file():
                    staged.replace(path)
    return outputs


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kinds", nargs="+", choices=FILES)
    for output in prepare(parser.parse_args().kinds):
        print(output.relative_to(ROOT).as_posix())
