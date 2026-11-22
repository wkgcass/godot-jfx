# macOS arm64 source builds

This page covers the macOS arm64 port. The Windows x64 configuration remains
documented in [build-windows.md](build-windows.md); this page does not change
it. Run all commands from the repository root in a shell.

## Toolchain

After cloning on Apple silicon, run `./scripts/setup-env.py`. It initializes
missing source submodules using Git and the URLs in `.gitmodules` (GitHub SSH by default). For a
new virtual environment, make Python 3.13 available on PATH before running setup. Setup prepares the following local tools and reuses
installed components on subsequent runs. Install Xcode and its Metal toolchain
separately.

Setup downloads `media-oracle-sample.mp4` and `Lk.mp4` into `agentdir/media/`.
It reuses each video when its SHA-256 matches and downloads a replacement if needed.
Use `./scripts/setup-env.py --sample-path oracle` (or `lk`) to verify an installed sample and print its path.

| Tool | Location | Notes |
| --- | --- | --- |
| JDK 25 | `.tools/jdk-25` (Temurin 25.0.5 aarch64) | Scripts read `JAVA_HOME`; when unset they fall back to this in-repository JDK (`$PWD/.tools/jdk-25/Contents/Home`) |
| SCons | `.tools/pyenv` (Python 3.13 venv with SCons 4.11, zstandard, Pillow) | Invoke as `.tools/pyenv/bin/scons` |
| Apache Maven 3.9.9 | `.tools/apache-maven-3.9.9` | Used by Maven consumers when `mvn` is unavailable on PATH |
| Apache Ant for JFX | `.tools/apache-ant-1.10.15` | Run `./scripts/setup-env.py` once or set `ANT_HOME` to an existing installation |
| Xcode + Metal toolchain | System | Install the Metal component once with `xcodebuild -downloadComponent MetalToolchain` |

The validated architecture is Apple silicon arm64. No prebuilt Godot or
JavaFX SDK substitutes for these source builds, and the JVM is the installed
JDK — it is not rebuilt.

## Build from source

```sh
./scripts/build-macos.sh --target godot-editor
./scripts/build-macos.sh --target godot-library
./scripts/build-macos.sh --target jfx
./scripts/build-vfx.sh
```

The test fixtures use the source-built editor for headless asset import and scene export.
The shared library includes the JavaFX host module.
Metal is the default driver for the `mobile` renderer. Ordinary JavaFX applications
and the VFX Demo can also request it explicitly, for example
`java -Djavafx.godot.driver=metal -jar artifacts/vfx/libs/vfx-demo.jar`.
A successful explicit launch logs `GODOT_LIBRARY_DRIVER metal`. Use `opengl` for
OpenGL 4.1 with `gl_compatibility`. Vulkan is not built (`vulkan=no`; MoltenVK is not installed).

The `jfx` target builds the SDK in one Gradle invocation with Media enabled and WebKit
disabled. On macOS the Media backend is AVFoundation (`libjfxmedia_avf.dylib`).
Products are in `jfx/build/sdk`; native libraries are `.dylib` files under
`lib/` (not `bin/` as on Windows). The platform classifiers package the dylibs for Java to load.

`build-vfx.sh` packages the local Media-enabled SDK, Godot dylib, VFX resources and Intro
pages in `artifacts/vfx/libs/vfx-demo.jar`. The loose classes, resources and
dependencies under `artifacts/vfx` also serve the Java scene fixtures.

After building the Godot dylib and Media-enabled SDK, run `./scripts/maven_local.py install`
to package the macOS arm64 modules and install them in this checkout's `.m2/repository`.
To stage a separate copy for a consumer, run
`./scripts/stage-godot-library.sh --destination <directory>`. Relative
destinations resolve from the caller's working directory.

The scene fixtures and the scroll-settings, screen-layout and render-command-validation probes
use those JARs. To reuse artifacts already staged by `build-vfx.sh`, pass `--runtime artifacts/godot-library`.

## Running the VFX Demo

```sh
java -jar artifacts/vfx/libs/vfx-demo.jar               # preferred interactive launch
scripts/run-vfx-demo.sh                                  # same JAR, logs to agentdir/logs
scripts/run-vfx-demo.sh --smoke                          # bounded startup/close check
scripts/run-vfx-demo.sh --driver opengl      # OpenGL 4.1
scripts/run-vfx-demo.sh --disable-vsync --max-fps 60     # CPU pacing instead of swapchain vsync
```

The distribution tests exercise the module path, standalone Shadow consumers,
and the VFX Demo in a directory containing only its JAR. The module-path
consumer uses Maven (`mvn` on PATH or `.tools/apache-maven-3.9.9/bin/mvn`).

Use the ordinary JDK launcher. On macOS JDK 25 it runs the Java entry point
on a worker and services a Cocoa run loop on the first thread. The library
schedules the Godot window and event loop on that first thread.
[OpenJDK macOS launcher](https://github.com/openjdk/jdk25u/blob/master/src/java.base/macosx/native/libjli/java_md_macosx.m).
Test entries are the same-named `scripts/test-*.sh` runners; see
[TESTS.md](../TESTS.md) for the macOS section, prerequisites and the
platform-specific native tests and performance commands.

## Known platform limits

- Temurin 25.0.5 aarch64 crashes the JVM (C2-related: `compiledIC` stub /
  `ChunkPool` corruption) shortly after FFM downcalls, reproducible
  standalone outside Godot. The churn/soak probes therefore sample process
  RSS via `ps` and count `/dev/fd` entries instead of FFM downcalls; pass
  criteria are unchanged.
- Media supports isolated fixture projects (`--runtime`). D3D and Windows handle/provider diagnostics require Windows. For the 1080p60 benchmark, generate the video with `./scripts/make-media-fixture.py` (ffmpeg and ffprobe on PATH).
- macOS has no per-window icon (the Dock icon belongs to NSApplication) and
  no Windows-style touch keyboard; the host reports both explicitly instead
  of silently ignoring requests.
- Run `./scripts/run-macos-tests.py --group NonRobot` for the scene and
  distribution tests, then `--group Robot` on an idle desktop with Accessibility
  and Screen Recording permission. Both groups and individual rendering tests
  default to Metal. Pass `--driver opengl` to a group to test OpenGL, or
  `--driver all` to exercise both drivers.
  Use `--list` to inspect the commands. Each invocation writes its own CSV and logs
  beneath `agentdir/logs`.
