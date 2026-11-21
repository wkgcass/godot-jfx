# Windows x64 source builds

For the macOS arm64 port see [build-macos.md](build-macos.md).

## PowerShell

Windows builds, packaging, tests and Demo scripts require PowerShell **7.4.1 or later**.
We recommend installing [PowerShell from the Microsoft Store](https://apps.microsoft.com/detail/9mz1snwt0n5d).
Open a terminal at the repository root, check the version and start PowerShell.

```text
pwsh --version
pwsh
```

Run the commands below in that `pwsh` session. Windows setup checks the version
available on `PATH` before preparing dependencies. Each PowerShell script also
checks its minimum version when invoked directly.

## Java-launched library

After preparing the Windows toolchain, run these builds sequentially from the checkout.

```powershell
.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\build-windows.ps1 -Target jfx
.\scripts\stage-godot-library.ps1 -Destination 'D:\Godot JavaFX'
```

Staging publishes six Java modules and the Windows x64 graphics and Media classifiers to `repository/`. Use this Maven repository when building the application. The graphics classifier includes the engine DLL from the library target. Applications deliver the resulting Shadow JAR. The Editor is needed for exporting custom scenes and running the full regression suite.

For local development tests, run `python scripts/maven_local.py install` after building the Godot shared library and Media-enabled SDK. It packages the six modules from those outputs and installs them in this checkout's `.m2/repository`. To install the exact artifacts from the staging example above, use `python scripts/maven_local.py install --runtime 'D:\Godot JavaFX'`.

The example below builds the repository's sample consumer and launches it. Set the manifest main class to an ordinary Java launcher that calls `Application.launch`. See the [consumer build](../tests/library/shadow/build.gradle) for the dependencies and manifest.

```powershell
$fxVersion = (Get-Content -Raw -LiteralPath 'D:\Godot JavaFX\version.txt').Trim()
.\jfx\gradlew.bat -p tests/library/shadow shadowJar '-Prepository=D:\Godot JavaFX\repository' "-PjavafxVersion=$fxVersion"
& "$env:JAVA_HOME/bin/java.exe" -jar tests/library/shadow/build/libs/stage-app-all.jar
```

For a module-path development run, resolve one JAR for each module. Use the Windows classifiers for graphics and Media.

```powershell
& "$env:JAVA_HOME/bin/java.exe" --module-path 'D:\myapp\target\modules' --add-modules javafx.controls,javafx.media --enable-native-access=javafx.graphics,javafx.media -cp 'D:\myapp\classes' example.MyApplication
```

The default host starts with an empty scene tree, uses `mobile` with Direct3D 12 and hides the window until its first presentation. An application using GodotView can include `META-INF/godot-jfx/scenes.pck` as a resource. An explicit imported directory or PCK remains available for applications that intend to launch an existing Godot project. [Library specification](godot-library-spec.md).

For example, select a project and show the startup logo with ordinary JavaFX startup:

```powershell
java "-Djavafx.godot.project=D:\myapp\scenes.pck" "-Djavafx.godot.startupWindow=logo" -jar app.jar
```

An application module requires `javafx.controls` and exports its Application package to `javafx.graphics`. Resolve `javafx.media` when using Media. `-Dprism.order=d3d` selects the stock Windows backend for control runs. Supply its Windows native directory using `-Djava.library.path` when consuming Maven jars outside the SDK.

## JDK selection

PowerShell build, run and test scripts default `-Jdk` to `$env:JAVA_HOME`;
JNI-based `.cmd` tests also use `JAVA_HOME`. Set it to a complete JDK 25 before
invoking scripts, or pass `-Jdk` explicitly to a PowerShell script.
The repository's `.java-version` selects 25 only when a configured Java version
manager handles that file; the scripts themselves do not read it. In the local
jdkman setup, `java -version` also updates `JAVA_HOME`. Check both before building:

```powershell
java -version
$env:JAVA_HOME
& "$env:JAVA_HOME/bin/javac.exe" -version
```

Build and test scripts need this directory even when
`java` is a shell function. Scripts that temporarily set `JAVA_HOME` restore it
on exit. A new shell must have the desired environment initialized again.

## Tool installation paths

After cloning, run `python scripts/setup-env.py`. It initializes missing source
submodules using Git and the URLs in `.gitmodules` (GitHub SSH by default).
It installs Ant 1.10.15, Maven 3.9.9, SCons 4.10.1 in `.tools/python`,
and the x64 MSVC packages for Mesa NIR, WinPixEventRuntime and the
Agility SDK in `.tools/localappdata/Godot/build_deps`. It also prepares
makedepend for Media using the MSYS2 installation below. Repeating setup
reuses the installed components. Supply JDK 25, Visual Studio with the Windows
SDK, and MSYS2 with UCRT64 GCC separately.

Both the Godot Editor and the shared library are built with `accesskit=no`.
Godot screen-reader support is disabled in both binaries, even if a previous
setup installed the AccessKit SDK in this checkout.

Setup downloads `media-oracle-sample.mp4` and `Lk.mp4` into `agentdir/media/`.
It reuses each video when its SHA-256 matches and downloads a replacement if needed.
Use `python scripts/setup-env.py --sample-path oracle` (or `lk`) to verify an installed sample and print its path.

| Tool | Environment variable | Default when unset | PowerShell override |
| --- | --- | --- | --- |
| JDK 25 | `JAVA_HOME` | None; initialize your Java environment | `-Jdk` |
| Apache Ant for JFX | `ANT_HOME` | `.tools/apache-ant-1.10.15` | Set `$env:ANT_HOME` |
| MSYS2 with UCRT64 GCC | `MSYS2_ROOT` | `D:\msys64` | `-Msys` |
| Visual Studio for JFX and native test helpers | `VSINSTALLDIR` | `%ProgramFiles%\Microsoft Visual Studio\2022\Community` | `-VisualStudio` |

Explicit parameters take precedence over environment variables. `-VisualStudio`
is accepted by `build-windows.ps1` and
`test-drag-drop-external.ps1`. Native `.cmd` tests read `VSINSTALLDIR` directly. The selected directory is
normalized before invoking Visual Studio tools, including the trailing
separator required by their environment setup; callers may omit that separator.
Godot's native build continues to use SCons MSVC 14.3 discovery; the
`build-windows.ps1 -VisualStudio` parameter configures the JFX build.
The JFX build obtains the x64 compiler path from the selected installation's
`vcvars64.bat` before invoking Gradle.

Set these variables in your shell/profile to match your installations, then run
the normal build commands without repeating path arguments. For example, set
`$env:MSYS2_ROOT` to your existing MSYS2 installation directory. Environment
overrides apply to the build process.
Relative repository paths for tools, caches and generated files remain relative
to this checkout. Clipboard/drag test file names are synthetic payloads and do
not require corresponding files to exist.

## Rendering configuration

The JavaFX module now builds only the Viewport host, with safe rendering.
There is no `-JavaFXRDDirect`/`javafx_rd_direct` build option or backend capability
JNI query. Build logs are `godot-editor.log` and `godot-library.log`.
Rebuild both the host and local JFX SDK after this removal. Godot's RenderingDevice
and D3D12, Vulkan and OpenGL renderer implementations remain enabled; the host still targets
Windows x64 as the reference platform, with macOS arm64 now ported separately
(see [build-macos.md](build-macos.md)); Linux remains unvalidated.

Run from the repository root in `pwsh` to build Godot and the JavaFX SDK from source.
The `jfx` target builds the Java modules, native graphics, fonts, Glass
and Media in one Gradle SDK invocation with WebKit disabled.

```powershell
python scripts/setup-env.py

.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target jfx
```

Build logs and exit codes are under `agentdir/logs`. The source editor imports test assets and exports custom scene packs. The shared engine is built at `godot/bin/godot.windows.template_release.x86_64.library.dll`. Build the platform classifiers and VFX Demo with:

```powershell
.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-vfx.ps1
```

The javafx custom module and JNI bridge are compiled into the shared Godot library;
there is no separate bridge DLL or godot-cpp runtime dependency. OpenJFX SDK native
graphics libraries include glass.dll, prism_d3d.dll, javafx_font.dll and
javafx_iio.dll. The SDK also includes Java modules such as javafx.fxml.jar.
Presence is not feature acceptance. The Media-enabled SDK build provides jfxmedia.dll and its
three supporting libraries. jfxwebkit.dll remains absent because WebKit is excluded.
The graphics/Glass native libraries are built from source.

## Reference scene

```powershell
& "$env:JAVA_HOME/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing -encoding UTF-8 -d artifacts/reference tests/reference/ReferenceSmoke.java
& "$env:JAVA_HOME/bin/java.exe" --enable-native-access=javafx.graphics --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing '-Dprism.order=d3d' '-Dprism.verbose=true' '-Dreference.snapshot=artifacts/reference/stock-d3d.png' -cp artifacts/reference ReferenceSmoke
```

This creates an actual JavaFX window, captures the scene using JavaFX's
snapshot API and exits. It is a stock D3D reference, not proof of Godot
integration or OS input correctness. The inspected image contains Chinese
and English text, controls, a gradient, shadow, rotated clip and opacity.

Native Media uses existing MSYS2 make/cygpath/sh and UCRT64 GCC under
`MSYS2_ROOT` (default `D:\msys64`).
`setup-env.py` reuses a verified makedepend installation.
`build-windows.ps1 -Target jfx` calls `build-makedepend.ps1`, which downloads checksum-pinned
X.Org makedepend 1.0.10 source, builds it under `.tools/makedepend`, and checks a
header dependency fixture. Source: https://xorg.freedesktop.org/releases/individual/util/.
A small MinGW compatibility header supplies existing-file canonicalization;
upstream source/license files are retained. No system package installation is used.

The Media script passes the MSVC/tool PATH to Gradle's native subprocesses,
keeps MSVC link.exe ahead of the unrelated MSYS utility, and disables redundant
MSYS argument rewriting for MSVC (Makefiles already use cygpath). The dependency
scanner wrapper enables conversion for its own native executable. The script
runs `sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false`, checks all four Media DLLs
in the SDK, and rejects an empty dependency scan. A failed upstream scan's marker-only
file is removed before retrying. Overrides are process-local and restored.

GLib, GStreamer, FX plugins and jfxmedia now compile and stage into the SDK.
Silent PCM and local MP4 MediaView playback pass with the GL and Vulkan renderers; extended Media stability remains open (see media-godot.md). Do not equate library
compilation with complete playback acceptance. An earlier
Cygwin installer attempt was rejected and has not been retried.
# Transparent native windows

Applications that explicitly load a project must enable `display/window/per_pixel_transparency/allowed=true`
before Godot starts. Projectless startup enables it internally. The test project includes this setting. Standard JavaFX
`StageStyle.TRANSPARENT` plus a transparent Scene fill can then preserve empty
pixels; an explicitly opaque Scene fill still draws an opaque background.

## Running the VFX Demo

Build the `godot-library` target and the Media-enabled JavaFX SDK, then run
`.\scripts\build-vfx.ps1`. It stages the platform libraries and builds the
complete Intro Demo. Launch it with `java -jar artifacts/vfx/libs/vfx-demo.jar`.
`.\scripts\run-vfx-demo.ps1` starts the same JAR and records a log.
The default launch uses
D3D12/safe and ordinary VSync. To select a driver for a single JVM, run
`java "-Djavafx.godot.driver=vulkan" -jar app.jar`. Valid values are
`d3d12`, `vulkan` and `opengl`. The property also works for the VFX Demo
and takes precedence over project settings. An explicit driver in GodotRuntime.Options takes priority over the JVM property.
The Java host also applies the selected driver to applications that load a custom project.
Secondary Stages use independent native windows.
Only `safe` is supported by the JavaFX host.

Host-frame pulses, batched passes, direct offscreen/final-target draws and
bounded shader source caches are backend defaults. Completed-pass synchronization
is retained for resource ordering. The launcher does not force performance
environment variables. For diagnostics, set the corresponding `GODOT_JFX_*`
switch to `0` as documented in bridge-protocol.md; unset it to restore the default.

CPU shadow images also reuse exclusive ownership by default; set
`GODOT_JFX_REUSE_SHADOW=0` to disable this diagnostic comparison. GPU region uploads are enabled by default; set `GODOT_JFX_REGION_UPLOAD=0` for a full-upload diagnostic comparison.
