# Per-node Godot CanvasItem shaders

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
