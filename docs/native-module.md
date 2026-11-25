# JavaFX custom module — foundation and current integration

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


This document explains the original M1 primitive and the module built on it.
Native Stage creation, Glass event signal binding and window lookup share an implementation across Windows, macOS and Linux. Linux uses
Godot transients to identify each Stage's owner. With a Wayland connection the
Linux library creates native Wayland windows. The compositor places toplevels
and controls their stacking order. The GTK 3 file chooser
uses the common Unix dialog request queue and associates the dialog with its
owner through an exported Wayland parent.
See the [Linux window results](acceptance-status.md#linux-x64-on-wsl2).
The current runtime also implements Prism rendering, fonts, effects, independent
native Stages and GodotView; see prism-godot.md, glass-godot.md and godot-view.md.

The external module is under `native/godot_modules/javafx`. Godot's official
`custom_modules` SCons option compiles and registers it inside the engine.
It uses neither GDExtension nor godot-cpp. M1 itself needs no Godot core patch;
the current runtime also has targeted Windows window/IME and render-thread shutdown
fixes in Godot core, recorded in the [implementation history](../agentdir/docs/progress.md).

Build the source engine with this module (a separate stock build is not a
prerequisite; do not run SCons concurrently in the same checkout):

```powershell
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\stage-godot-library.ps1
.\scripts\test-m1.ps1
.\scripts\test-m1.ps1 -Driver d3d12
```

`JavaFXRenderSurface` is a main-thread resource owner with an offscreen
RenderingServer viewport and canvas. A child CanvasItem of its Node2D
composites the viewport's borrowed GPU texture, preserving the Node2D
transform. An owned image texture can be uploaded once and reused by draw
commands. CanvasItem shader code applies to the presentation item. Resizing
updates the viewport and presentation geometry without a CPU readback.

Every mutator checks Godot main-thread ownership. Leaving the scene tree
releases dependent RIDs before their backing resources. The viewport texture
is borrowed and must never be freed separately. Reentering allocates fresh
resources; draw contents must be resubmitted. The resource counter
checks this owner's handle lifetime only, not total driver/GPU allocations.

`JavaFXRenderTarget` has a fixed size for its lifetime. By default it renders
through a viewport and caches that viewport's borrowed texture RID after
initialization, so repeated sampling does not synchronize RenderingServer merely
to retrieve the same RID. This borrowed handle is never freed separately.
The host uses only Viewport targets in safe mode. `get_texture` rejects access
from another thread or during an open pass. The former RD-direct target and
asynchronous texture-proxy initialization have been removed.
`scripts/test-texture-lookup.ps1` checks identity across rendered passes and pixel
content, and prints isolated getter timings; it is not a frame-rate benchmark.

The M1 fixture checks textured and solid pixels after a CanvasItem shader,
surface resizing, exit-tree disposal, and 100 create/remove/free cycles.
Its readback is for verification only. It writes
`artifacts/reference/godot-m1.png`; a successful run must print
`M1_RESULT PASS` and return zero without renderer errors.

The M1 surface fixture alone does not prove Prism or per-node shader integration.
JavaFXHost registers the JNI bridge in the application JVM and consumes its command queue (see bridge-protocol.md), with
Glass scheduling/input and Prism graphics/font/effect integration described in
their subsystem documents.
The original M1 upload_rgba helper still allows one image; the host command
protocol now separately supports many generation-tagged texture resources,
projected transaction validation and retained draw revisions. See
bridge-protocol.md for limits and the remaining Prism resource work.

M1 verification passed on 2026-10-30 during primitive bring-up:
OpenGL 3.3 Compatibility and Vulkan 1.4.330 Mobile on Intel Arc B390.
Both output images were inspected; sampled RGB values are (51,102,204)
and (0,204,0), matching the 0.8 shader multiplier. Both runs completed
100 resource cycles with PASS and no renderer errors. This validates the
small M1 fixture only; prolonged driver/GPU-memory leak testing remains.

Prism vertex bring-up now uses ArrayMesh with 2D positions, UV0, premultiplied
RGBA8 vertex colors and UV1 in CUSTOM0's x/y components. Both GL and Vulkan
fixtures independently sample UV0, UV1 and vertex color in a shader, and
check half-transparent premultiplied red composited over the host background.
Default draw and presentation shaders both use blend_premul_alpha. The M1
straight RGBA image upload is converted once on upload; texture modulation
colors are converted before submission. Quad colors are
already premultiplied and remain unchanged. Custom shaders must choose the
appropriate blend mode themselves.

Each surface now owns eight baseline RIDs (viewport, canvas, draw item,
presentation item, and two shader/material pairs), plus an optional image,
background item and one mesh per quad batch. Clear releases meshes; exit
releases all owned resources. The existing 100-cycle test now includes mesh
creation and disposal. GPU captures are godot-prism-vertices-<driver>.png.
This validates vertex transport, not stock Prism shaders or JavaFX controls.

Source textures additionally support transparent allocation and region
updates. CPU Image shadows preserve unaffected source-image pixels. Updates
reuse unreferenced RIDs and create retained revisions when earlier draws still
refer to the old contents. Completed Viewport passes release their retained draw
resources before retirement. This prevents uploads from changing the revision
that an already-recorded draw still needs. The texture fixture covers a 1024x1024 allocation,
a patch at the final pixel, transparency of the old revision, neighboring
unchanged pixels and final resource disposal on GL and Vulkan.

The module alone enables C++ exception unwinding so native transaction
allocation failures can be translated at the JNI boundary. Other Godot modules
retain the engine's default exception setting.

## Embedded scene resource for GodotView

`JavaFXSceneView` owns a real scene-tree SubViewport through checked ObjectIDs.
It loads a PackedScene from `res://`, instantiates it below an isolated World2D,
uses a transparent continuously updated viewport, and exposes its borrowed GPU
texture. The main-thread API resizes that viewport and forwards InputEvents in
viewport-local coordinates. Windows created inside this embedded scene stay embedded in its SubViewport;
this restriction does not apply to JavaFX Stages, which use independent native
windows. JavaFXRenderSurface can directly sample and retain the
owner until its recorded draw commands are cleared. The owner deletes the
SubViewport and scene on release, and tolerates the parent having already
destroyed that tree.

`scripts/test-scene-views.ps1` exercises 100 real scene load/resize/process/input/
retain/release cycles, tests alpha pixels and GPU texture updates, checks the
owner/viewport/root ObjectIDs are gone after release, verifies an embedded Window
does not create another native window, and covers parent-first destruction.
The surface RID count does not claim to enumerate every internal RID owned by
the scene nodes; their destruction is checked separately via ObjectIDs.

This native resource layer is connected to the public JavaFX GodotView through
Prism allocation/resize commands and its resizable Region/peer. Continuous redraw
and mouse/key/touch/focus forwarding are implemented. Tests now include parent
scale/shear/translation, clipping, opacity and retained scene state after resize;
see godot-view.md. GPU captures do not establish physical-input acceptance.
## Independent native window migration (2026-11-02)

The current user requirement is an independent native window per JavaFX Stage.
JavaFXNativeWindow now provides the Godot-side presentation primitive. It derives
from Window, hides before setting force_native, and owns an independent GPU surface.
present_content retains a JavaFXRenderTarget; the process callback serializes
composition against its pending GPU work. Resize changes only this viewport and
keeps the last published output size until replacement; output size can differ
from texture resolution. Tree exit disables viewport updates and synchronizes
pending rendering before the base Window destroys its native swapchain. It also
clears retained content, while the child surface releases its resources.

Earlier runs of `scripts/test-native-windows.ps1` (including the retired separate
configuration) validated two
additional OS windows with distinct IDs, one outside the original host, independent
GPU colors, replacement-target lifetime, independent resize, hide/show and deletion.
Their viewport captures were inspected. This is a native primitive test, not JavaFX
Stage integration or physical/OS screenshot acceptance by itself. The subsequent
Glass-Godot migration routes ordinary secondary Stages through these independent
native windows; the primary Stage uses the root window. See glass-godot.md and
the [implementation history](../agentdir/docs/progress.md) for the integration and lifecycle evidence.

## OLE drag/drop delegate (2026-11-04)

Cross-application drag/drop reuses Godot's own `DropTargetWindows`
registration: `DisplayServerWindows::window_set_drag_delegate` installs a
module delegate inside the existing IDropTarget instead of a second
`RegisterDragDrop` (which Windows rejects with DRAGDROP_E_ALREADYREGISTERED).
`refresh_drag_delegates()` installs/clears delegates as hosted windows come and
go, and window destruction clears the delegate before the map entry. A delegate
that finds no supported payload format returns false so Godot's original
file-drop behavior still runs. Outbound gestures run `DoDragDrop` on the Godot
main thread with a validated snapshot of the Glass drag clipboard. See
bridge-protocol.md for the wire/upcall contract and glass-godot.md for the
Glass-side session handling.

## VSync pacing fallback (2026-11-05)

`JavaFXHost::check_vsync_pacing` runs a one-shot health check while the runtime
is RUNNING. It skips two seconds of bring-up and samples two seconds of frame
intervals. A nonzero application `Engine.max_fps` disables this fallback; a
finite refresh rate of at least 55 Hz, VSync still enabled, a non-fullscreen
window and a measured interval above 1.4 times the refresh period are required.
It then tries VSync-disabled pacing at the rounded refresh rate and prints
`JAVAFX_VSYNC_FALLBACK`. This is a response to observed low cadence, not proof
that FIFO causes every slowdown or a guarantee of tear-free presentation.
Disable it with `GODOT_JFX_VSYNC_FALLBACK=0`.

On Java completion, failure notification or host stop, the host restores the
previous uncapped/VSync-enabled state only where the current setting still
matches its installed fallback value. Later differing application settings are
preserved; value comparison cannot detect another writer choosing the same
value. See frame-benchmark.md and test-pacing-cap.ps1 for evidence and limits.

The host also applies queued window commands a second time per frame from the
RenderingServer `frame_pre_draw` signal (`pre_draw_host_commands`, main thread
in both render-thread modes), so commands produced in response to the current
frame's input still affect that frame's presentation; see glass-godot.md for
the input-side wake-up path.

## Loading the Godot library from Java

The Linux x64 JavaFX host uses native Wayland windows. It selects `mobile` for Vulkan and `gl_compatibility` for OpenGL.

The Linux shared library links dynamically to the system's `libstdc++` so the engine and GPU driver in the JVM use the same C++ runtime. On WSL2, if Mesa has loaded D3D12Core, the host keeps it loaded until process exit. Threads that exit after Godot stops can then call the cleanup functions registered by the driver.

On Windows, `scripts/build-windows.ps1 -Target godot-library` compiles the module into the shared library. On macOS, SCons builds the dylib with `library_type=shared_library`. After Java loads the platform library, the engine runs on a dedicated thread on Windows and on the AppKit main thread on macOS. The library entry point creates and starts `GodotInstance`, attaches `JavaFXHost` to the `SceneTree` root window, registers native methods with the existing JVM and runs the engine loop. The resource filesystem starts empty. An application can mount a scene pack from its JAR in memory and load its resources by path through GodotView. Godot runs its project startup sequence only when the application explicitly selects an external project or a main PCK. [Single-JAR specification](godot-library-spec.md)

On macOS arm64 the shared library schedules startup and shutdown on the AppKit main thread, which processes native window events each frame. `./scripts/build-vfx.sh` packages the locally built dylib in the VFX Demo JAR. [macOS build guide](build-macos.md)
