"""Read the JDK selected for this invocation and propagate it to child tools."""
import os
from pathlib import Path


def add_jdk_argument(parser):
    parser.add_argument("--jdk", metavar="DIRECTORY", help="JDK home for this invocation (default: JAVA_HOME)")


def configure_jdk(override=None):
    home = os.environ.get("JAVA_HOME") if override is None else override
    if not home:
        raise ValueError("Set JAVA_HOME to JDK 25 or pass --jdk DIRECTORY")
    path = Path(home).absolute()
    suffix = ".exe" if os.name == "nt" else ""
    for tool in ("java", "javac"):
        executable = path / "bin" / (tool + suffix)
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError(f"Missing JDK executable: {executable}")
    os.environ["JAVA_HOME"] = str(path)
    return path
