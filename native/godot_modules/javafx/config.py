def can_build(env, platform):
    return platform == "windows" and env["arch"] == "x86_64"


def get_opts(platform):
    from SCons.Variables import BoolVariable

    return [BoolVariable("javafx_rd_direct", "Compile the JavaFX RD-direct backend and probes", True)]


def configure(env):
    if env["javafx_rd_direct"] and not env["vulkan"] and not env.get("metal", False) and not env.get("d3d12", False):
        raise RuntimeError("javafx_rd_direct=yes requires a RenderingDevice backend; use javafx_rd_direct=no")
