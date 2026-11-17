def can_build(env, platform):
    if platform == "windows":
        return env["arch"] == "x86_64"
    if platform == "macos":
        return env["arch"] in ("x86_64", "arm64")
    return False


def configure(env):
    if env["platform"] == "macos":
        env.Append(
            LINKFLAGS=[
                "-framework",
                "Cocoa",
                "-framework",
                "QuartzCore",
                "-framework",
                "CoreGraphics",
                "-framework",
                "ApplicationServices",
                "-framework",
                "UniformTypeIdentifiers",
                "-framework",
                "Carbon",
            ]
        )
