# Per-node Godot CanvasItem shaders

The VFX Intro menu includes a concrete subtree example: **Blackhole Effect**
attaches this API to the Demo content VSceneGroup and updates numeric uniforms from
mouse events. Its CanvasItem source is a Java 11-compatible string constant in `BlackholeEffectControl`, and works
through either Viewport or RD when supported by the host. See
[VFX Demo](vfx-demo.md#blackhole-effect-in-the-intro-menu) for operation and tests.

`javafx.scene.effect.GodotShaderEffect` is an additive public extension in
`javafx.graphics`. Existing controls and their skin/CSS code are unchanged:

```java
GodotShaderEffect tint = new GodotShaderEffect("""
    shader_type canvas_item;
    uniform vec3 tint = vec3(1.0);
    void fragment() {
        vec4 color = texture(TEXTURE, UV);
        COLOR = vec4(color.rgb * tint, color.a);
    }
    """);
tint.setFloat("tint", 0.8f, 1.0f, 0.6f);
button.setEffect(tint);
```

Assigning the effect to a Group applies it to that subtree. An optional
`inputProperty()` chains another standard Effect. JavaFX handles dirty propagation,
input-cycle rejection, bounds, parent transforms, opacity and clipping. Parameters
must be changed on the FX thread for attached live nodes, as with other JavaFX
scene properties. `setFloat` and `setInt` accept one to four components and check
the declared type/shape. Caller arrays and render snapshots are copied. Source is
immutable; replace the effect to change the shader program.

The internal FilterEffect requests the complete input in user space. It gets a
pooled GPU texture, draws a separate CanvasItem shader pass into another pooled
target, then returns ImageData to the normal effect/composition path. No CPU
readback or complete-UI bitmap upload is used. Each draw receives immutable
uniform/sampler state, so different nodes can use the same source with different
values. Transient Java Shader descriptors are flushed before disposal; native
draw materials/meshes retire at the completed pass boundary.

`UV` is normalized over the complete input bounds, and `TEXTURE_PIXEL_SIZE`
describes that input. Sampling `texture(TEXTURE, uv)` is adapted to the correct
region of the pooled source texture. Fragment-entry `COLOR` includes the node
input, matching the usual implicit CanvasItem texture modulation. Node images
and output `COLOR` use premultiplied alpha. The adapter requires unshaded,
premultiplied blending and preserves input bounds; geometry outside those bounds
is not an expansion of the effect bounds.

Current limits are explicit: this effect requires the Godot pipeline; additional
sampler uniforms and other blend modes are rejected by the Java adapter. Only the
two-argument `texture(TEXTURE, coordinates)` form is supported for input sampling;
unsupported forms may fail later in Godot shader compilation rather than in the
Java constructor. Numeric parameter setters support scalar/vec2/vec3/vec4
float/int declarations, optionally with defaults, but not uniform hints or arrays.
GPU shader compilation errors currently appear in Godot diagnostics, without a
Java-visible compilation acknowledgement. These limitations remain relevant to
broader shader compatibility and are not hidden by a software fallback.

Validation command:

```powershell
.\scripts\test-node-shaders.ps1
.\scripts\test-node-shaders.ps1 -Renderer mobile
```

The runner preserves existing rendering environment variables. To explicitly
exercise RD on Vulkan without changing later commands:

```powershell
$savedRd = $env:GODOT_JFX_RD_DIRECT
try {
    $env:GODOT_JFX_RD_DIRECT = '1'
    .\scripts\test-node-shaders.ps1 -Renderer mobile
} finally { $env:GODOT_JFX_RD_DIRECT = $savedRd }
```

Use `'0'` for the corresponding forced non-RD run. Record the selected value with
the log: the standard filename includes renderer and thread mode, but not RD state,
so copy it before another run overwrites it.

The probe exercises separate parameter instances, 80 parameter changes, a
GaussianBlur input chain, subtree shading, scaled clip/opacity, normalized UVs,
an unaffected sibling, a shader on an ordinary Button with Chinese text, mouse
action updating a second shader, and zero native resources after teardown.
Its PNGs are GPU framebuffer captures, not OS screenshots or physical-input
acceptance of the final VFX demo.

RD-direct mode (`GODOT_JFX_RD_DIRECT=1`) runs the same effect through the
translated raw-GLSL pipeline: every fragment `COLOR` reference (including the
adapter's compound `COLOR *=` modulation) maps to a local initialized from the
vertex-color varying, one-line sources with several uniform declarations and
default values translate, and historical acceptance runs passed in both RD states. These results describe
the tested shader subset, not arbitrary CanvasItem source compatibility.

The 2026-11-09 review found that translating a default declaration was not enough:
the production RD uniform buffer still started at zero. Defaults are now evaluated
by Godot's canvas parser and copied into the buffer before explicit overrides.
`test-rd-regressions.ps1` checks omitted defaults and explicit overrides in the
production draw path; the existing node-shader suite passes with RD on/off and
OpenGL. Earlier translation-only results did not prove default-value behavior.

## Animated input and dirty-region handling

`GodotShaderEffect` always renders its complete input and invalidates its complete
output bounds when input content changes. Arbitrary shaders can sample any input
pixel, so the original dirty rectangle cannot describe the affected output.
Cropping the input also changes normalized node UVs and can leave unwarped or
stale copies beside the correct shader output during child animations.
This follows the same conservative policy as JavaFX `DisplacementMap`; dirty
region optimization remains enabled elsewhere. Effects on a whole Scene root
therefore redraw that root when its descendants animate, which can cost more GPU
work than local repainting. Shader syntax and public API are unchanged.

After rebuilding JFX, run the independent regression (no VFX dependency):

```powershell
.\scripts\test-node-shader-dirty.ps1 -Renderer mobile
.\scripts\test-node-shader-dirty.ps1 -Renderer mobile -RD
.\scripts\test-node-shader-dirty.ps1 -Renderer gl_compatibility
```

A fixed horizontal-mirror shader receives a rectangle whose opacity animates and
whose position changes. The host samples actual presented GPU frames, rather than
requesting full JavaFX node snapshots: the mirrored rectangle must update, its
unwarped location must stay empty, and its former location must clear. Both phases
require repeated samples and teardown requires zero owned host resources. Logs
and captures use `node-shader-dirty-<renderer>-<thread>-rd<0/1>` names under
`artifacts/logs` and `artifacts/reference`. No real mouse or keyboard input is used.

2026-11-12: the regression reproduced the unwarped duplicate before the fix.
The source JFX SDK build, this regression and the existing node-shader suite pass
on Windows Editor mobile/safe with RD off/on and OpenGL/safe. These bounded checks
do not establish Runtime, cross-platform or performance acceptance.
