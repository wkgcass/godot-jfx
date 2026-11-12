# GodotView integration

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


The public `javafx.scene.layout.GodotView` is a resizable Region:

```java
GodotView view = new GodotView();
view.setPrefSize(320, 200);
view.loadScene("res://scenes/effect.tscn");
root.getChildren().add(view);
```

Use normal JavaFX layout, transforms, opacity, clipping and sibling order.
Region insets define the scene content rectangle. Its peer samples a live
SubViewport texture through Prism-Godot; there is no CPU readback. Scene output
pixels use the content's logical dimensions rounded up to integers. Higher DPI
render resolution remains logical. A combined scale/shear/translation fixture is
verified; arbitrary transform stress remains unverified.

The peer pins its scene texture against ordinary pool eviction so resource
pressure cannot silently reload scene state. Resizing ends the current GPU pass
and uses protocol command 21 to transfer the existing scene owner to a new
Prism texture wrapper. The Godot node instance, script variables and processing
continue. Each live view uses a JavaFX AnimationTimer to invalidate its content
while the containing window is showing; the handler checks tree visibility.
Godot itself continues processing the embedded scene on its main thread.

`close()` unloads the scene and stops its redraw timer. Removing the view from
its JavaFX Scene also releases its native scene through a queued RenderJob;
reattachment can load it again. A window being hidden pauses redraw, but does
not by itself destroy the retained embedded scene. Godot scene popups are
embedded inside the SubViewport rather than opening extra native windows.

Current verification:

```powershell
.\scripts\test-godot-view.ps1
.\scripts\test-godot-view.ps1 -Renderer mobile
.\scripts\test-godot-view.ps1 -Renderer mobile -Transform
.\scripts\test-godot-view.ps1 -Renderer mobile -Transform -Runtime
.\scripts\test-scene-textures.ps1 -Resize
.\scripts\test-scene-textures.ps1 -Resize -Renderer mobile
```

The mixed Stage contains two GodotViews, Chinese Label text and an ordinary
Button. Both backends pass native scene changes becoming visible without other
JavaFX mutations, alpha and parent clip/opacity pixels, button-driven layout
resize preserving the scene ObjectID/state, old-position clearing, one native
window, close/removal cleanup and zero host resources at teardown. Observed
host resource peak is 30; this is not a complete driver-memory measurement.

The transformed fixture passes GL/safe, Vulkan/safe, Vulkan/separate and packaged
Vulkan/safe. It verifies transformed GPU sample positions, parent clip/opacity,
mouse/wheel/touch inverse coordinates, sibling isolation, focus cancellation,
button resize retaining native scene identity/state, and final resource cleanup.
Its resource peak is 56 because the transformed clip uses offscreen targets.
The script also runs a stock D3D `TransformClipReference`: upstream NGNode applies
opacity to both the content pass and final non-axis-aligned clip blend. For 50%
opacity, the red-over-white sample is approximately (1,.753,.753), matching Godot.
This documents native compatibility rather than changing upstream clip behavior.
Touch samples use coordinates representable by Glass's integer touch transport;
subpixel input precision is not asserted. Images are GPU/snapshot evidence.

GodotView now forwards JavaFX mouse motion/buttons, wheel, logical key/text,
TouchEvent press/move/release and focus changes through render jobs and command
22. Pointer coordinates account for Region insets and viewport dimensions;
synthesized mouse events from touch are excluded to avoid duplicate input. Tab
remains available to JavaFX focus traversal. Text is taken from key press events;
the duplicate Glass KEY_TYPED event is consumed. IME composition is not yet
implemented. Events are scoped to the selected SubViewport; Godot's global Input
singleton remains global, as in ordinary Godot SubViewport applications.

Both backends pass mouse coordinates, wheel factor, Space key/Unicode, JavaFX
touch coordinates/drag, sibling event isolation, and focus loss canceling a held
touch and releasing a held key. Mouse/key/wheel/touch enter through Godot input
and Glass. Glass promotes the first touch to synthesized mouse events for
ordinary controls; the probe checks one mouse and one touch Button action with
no duplicate action. The events are injected through Input.parse_input_event,
so this is not physical touch acceptance. Sustained resize/DPI/transform stress and real VFX integration remain
pending. PNGs are GPU captures, not final OS screenshots or physical-input
acceptance. GodotView requires the Godot pipeline explicitly.
