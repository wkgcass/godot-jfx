# Windows x64 source builds

Run from the repository root in PowerShell. No prebuilt Godot or JavaFX SDK
is used. Current M0 OpenJFX command builds upstream's default SDK: native
graphics/fonts/Glass, Java modules; upstream defaults do not compile native
WebKit or media. The latest user clarification requires Media support and excludes
WebKit. The default SDK alone therefore does not finish the Media build requirement.

```powershell
python -m venv .tools/python
.\.tools\python\Scripts\python.exe -m pip install scons==4.10.1

# The upstream installers use LOCALAPPDATA. Isolate their downloads in this
# checkout; the build script passes explicit SDK paths to SCons.
$previousLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = Join-Path $PWD '.tools/localappdata'
    .\.tools\python\Scripts\python.exe godot/misc/scripts/install_accesskit.py
    if ($LASTEXITCODE -ne 0) { throw 'AccessKit installation failed' }
    .\.tools\python\Scripts\python.exe godot/misc/scripts/install_d3d12_sdk_windows.py
    if ($LASTEXITCODE -ne 0) { throw 'D3D12 dependency installation failed' }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
}

.\scripts\build-windows.ps1 -Target godot-editor
.\scripts\build-windows.ps1 -Target godot-runtime
.\scripts\build-windows.ps1 -Target jfx -Jdk 'D:\jdk-25.0.3+9'
```

Scripts are repeatable/incremental and propagate build failures. Logs and
exit codes are under `artifacts/logs`. Current verified output locations:
`godot/bin/godot.windows.editor.x86_64.exe`,
`godot/bin/godot.windows.template_release.x86_64.exe`, `jfx/build/sdk`.
The runtime is Godot's export template target, not a prebuilt download.
The current integrated Editor and Runtime, and the default OpenJFX SDK, have
built successfully; their latest recorded exit codes are zero. Godot currently
reports `4.8.beta.custom_build.420dfdc1c` (Editor `--version`, checked 2026-11-04). Build the integrated binaries with:

```powershell
.\scripts\build-windows.ps1 -Target godot-editor -WithJavaFXModule
.\scripts\build-windows.ps1 -Target godot-runtime -WithJavaFXModule
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-jfx-media.ps1
.\scripts\build-vfx.ps1
.\scripts\write-delivery-inventory.ps1
```

The javafx custom module and JNI bridge are compiled into these Godot executables;
there is no separate bridge DLL or godot-cpp runtime dependency. OpenJFX SDK native
graphics libraries include glass.dll, prism_d3d.dll, javafx_font.dll and
javafx_iio.dll. The SDK also includes Java modules such as javafx.fxml.jar.
Presence is not feature acceptance. The Media-enabled SDK build provides jfxmedia.dll and its
three supporting libraries. jfxwebkit.dll remains absent because WebKit is excluded.
The graphics/Glass native libraries are built from source. The generated
artifacts/change-inventory.json records current repository revisions, all modified
or untracked paths and selected artifact hashes; regenerate it after changes.

## Reference scene

```powershell
& 'D:\jdk-25.0.3+9\bin\javac.exe' --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing -encoding UTF-8 -d artifacts/reference tests/reference/ReferenceSmoke.java
& 'D:\jdk-25.0.3+9\bin\java.exe' --enable-native-access=javafx.graphics --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing '-Dprism.verbose=true' '-Dreference.snapshot=artifacts/reference/stock-d3d.png' -cp artifacts/reference ReferenceSmoke
```

This creates an actual JavaFX window, captures the scene using JavaFX's
snapshot API and exits. It is a stock D3D reference, not proof of Godot
integration or OS input correctness. The inspected image contains Chinese
and English text, controls, a gradient, shadow, rotated clip and opacity.

Native Media uses existing MSYS2 make/cygpath/sh and UCRT64 GCC at `D:\msys64`.
`build-jfx-media.ps1` calls `build-makedepend.ps1`, which downloads checksum-pinned
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
Silent PCM and local MP4 MediaView playback pass on GL/Vulkan Editor and packaged
Vulkan Runtime; extended Media stability remains open (see media-godot.md). Do not equate library
compilation with complete playback acceptance. An earlier
Cygwin installer attempt was rejected and has not been retried.
# Transparent native windows

The host project must enable `display/window/per_pixel_transparency/allowed=true`
before Godot starts. The test project now includes this setting. Standard JavaFX
`StageStyle.TRANSPARENT` plus a transparent Scene fill can then preserve empty
pixels; an explicitly opaque Scene fill still draws an opaque background.

## Running the VFX Demo

After building the local Godot module, JavaFX SDK and VFX classes, run
`./scripts/run-vfx-demo.ps1`. This opens the original interactive Demo using
Vulkan/safe and ordinary VSync. Secondary Stages use independent native windows.
`-RenderThread separate` selects the separately threaded renderer.

Host-frame pulses, batched passes, direct offscreen/final-target draws, early
composition fences, asynchronous separate-thread pass fences and bounded shader
source caches are backend defaults. The launcher does not force performance
environment variables. For diagnostics, set the corresponding `GODOT_JFX_*`
switch to `0` as documented in bridge-protocol.md; unset it to restore the default.

CPU shadow images also reuse exclusive ownership by default; set
`GODOT_JFX_REUSE_SHADOW=0` to disable this diagnostic comparison. Experimental
GPU region uploads remain opt-in via `GODOT_JFX_REGION_UPLOAD=1`.
