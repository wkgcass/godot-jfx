# macOS arm64 source builds

This page covers the macOS arm64 port. The Windows x64 configuration remains
documented in [build-windows.md](build-windows.md); this page does not change
it. Run all commands from the repository root in a shell.

## Toolchain

| Tool | Location | Notes |
| --- | --- | --- |
| JDK 25 | `.tools/jdk-25` (Temurin 25.0.5 aarch64) | Scripts read `JAVA_HOME`; when unset they fall back to this in-repository JDK (`$PWD/.tools/jdk-25/Contents/Home`) |
| SCons | `.tools/pyenv` (Python 3.13 venv with SCons 4.11, zstandard, Pillow) | Invoke as `.tools/pyenv/bin/scons` |
| Xcode + Metal toolchain | System | Install the Metal component once with `xcodebuild -downloadComponent MetalToolchain` |

The validated architecture is Apple silicon arm64. No prebuilt Godot or
JavaFX SDK substitutes for these source builds, and the JVM is the installed
JDK — it is not rebuilt.

## Resource editor

The test fixtures use the source-built editor for headless asset import and scene export.

```sh
.tools/pyenv/bin/scons -C godot platform=macos arch=arm64 target=editor vulkan=no accesskit=no angle=no -j8
```

Renderer mapping on macOS: `mobile` renders through Metal 4.0 and
`gl_compatibility` through OpenGL 4.1. Vulkan is not built (`vulkan=no`;
MoltenVK is not installed).

## JavaFX SDK

```sh
(cd jfx && JAVA_HOME="$PWD/../.tools/jdk-25/Contents/Home" GRADLE_USER_HOME="$PWD/../.gradle-cache" \
    ./gradlew sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false --no-daemon)
```

A single Gradle invocation builds the SDK with Media enabled and WebKit
disabled; on macOS the Media backend is AVFoundation (`libjfxmedia_avf.dylib`),
so there is no separate Media build step like `build-jfx-media.ps1`.
Products are in `jfx/build/sdk`; native libraries are `.dylib` files under
`lib/` (not `bin/` as on Windows). The platform classifiers package the dylibs for Java to load.

## Build the VFX Demo JAR

```sh
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
.tools/pyenv/bin/scons -C godot platform=macos arch=arm64 target=template_release library_type=shared_library extra_suffix=library disable_path_overrides=no vulkan=no accesskit=no angle=no custom_modules="$PWD/native/godot_modules" -j8
sh scripts/build-vfx.sh
```

This packages the local Media-enabled SDK, Godot dylib, VFX resources and Intro
pages in `artifacts/vfx/libs/vfx-demo.jar`. The loose classes, resources and
dependencies under `artifacts/vfx` also serve the Java scene fixtures.

## Running the VFX Demo

```sh
java -jar artifacts/vfx/libs/vfx-demo.jar               # preferred interactive launch
scripts/run-vfx-demo.sh                                  # same JAR, logs to artifacts/logs
scripts/run-vfx-demo.sh --smoke                          # bounded startup/close check
scripts/run-vfx-demo.sh --renderer gl_compatibility      # OpenGL 4.1
scripts/run-vfx-demo.sh --disable-vsync --max-fps 60     # CPU pacing instead of swapchain vsync
```

The new JAR path needs validation on macOS arm64, including Metal, OpenGL,
AppKit thread ownership and clean window close. [Pending checks](../TESTS.md).

Use the ordinary JDK launcher. On macOS JDK 25 it runs the Java entry point
on a worker and services a Cocoa run loop on the first thread. The library
schedules the Godot window and event loop on that first thread.
[OpenJDK macOS launcher](https://github.com/openjdk/jdk25u/blob/master/src/java.base/macosx/native/libjli/java_md_macosx.m).
Test entries are the same-named `scripts/test-*.sh` runners; see
[TESTS.md](../TESTS.md) for the macOS section, prerequisites and the
Windows-only entries that do not apply.

## Known platform limits

- Temurin 25.0.5 aarch64 crashes the JVM (C2-related: `compiledIC` stub /
  `ChunkPool` corruption) shortly after FFM downcalls, reproducible
  standalone outside Godot. The churn/soak probes therefore sample process
  RSS via `ps` and count `/dev/fd` entries instead of FFM downcalls; pass
  criteria are unchanged.
- A few runner modes are not ported and the scripts reject them explicitly
  (exit 2), for example Media `--runtime`/`--native-d3d`/`--handle-types`/
  `--providers`. `make-media-fixture.ps1` (the 1080p60 benchmark fixture) is
  Windows-only.
- macOS has no per-window icon (the Dock icon belongs to NSApplication) and
  no Windows-style touch keyboard; the host reports both explicitly instead
  of silently ignoring requests.
- Run the packaged-engine Robot fixtures serially on an idle desktop with user authorization. Record arm64 results in the cross-platform checklist in TESTS.md.
