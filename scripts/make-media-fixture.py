#!/usr/bin/env python3
"""Generate the macOS H.264 motion fixture and verify its encoded frame count."""
import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "agentdir/media"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    MEDIA.mkdir(parents=True, exist_ok=True)
    log = ROOT / "agentdir/logs/media-fixture-1080p60.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=MEDIA) as directory:
        video = Path(directory) / "media-1080p60.mp4"
        with log.open("wb") as out:
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-f", "lavfi", "-i",
                            "testsrc2=size=1920x1080:rate=60:duration=16", "-c:v", "libx264", "-preset", "fast",
                            "-b:v", "8M", "-pix_fmt", "yuv420p", "-movflags", "+faststart", video],
                           stdout=out, stderr=subprocess.STDOUT, check=True)
        info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-count_frames", "-select_streams",
            "v:0", "-show_entries", "stream=width,height,r_frame_rate,nb_read_frames,codec_name,duration",
            "-of", "json", video]))["streams"][0]
        if (info["width"], info["height"], info["r_frame_rate"], int(info["nb_read_frames"]),
                info["codec_name"], float(info["duration"])) != (1920, 1080, "60/1", 960, "h264", 16):
            raise ValueError(f"Unexpected encoded stream {info}")
        manifest = video.with_suffix(".json")
        manifest.write_text(json.dumps(dict(width=1920, height=1080, fps=60, frames=960, seconds=16, codec="H264",
                                            sha256=sha(video), source_sha256=sha(Path(__file__))), indent=2) + "\n")
        video.replace(MEDIA / video.name)
        manifest.replace(MEDIA / manifest.name)
    print("MEDIA_FIXTURE_PASS width=1920 height=1080 fps=60/1 frames=960 seconds=16 codec=H264")


if __name__ == "__main__":
    main()
