# Prism-Godot implementation status

This document combines implementation contracts with dated development evidence.
Historical performance diagnoses describe the build and workload measured then;
they are not current limits or proof for later binaries. The optional RD backend
is implemented (`GODOT_JFX_RD_DIRECT=1`); the default remains the viewport path.
See frame-benchmark.md for later near-60 measurements and their scope.

The SCons option `javafx_rd_direct=no` excludes `javafx_rd_pass.cpp`,
`javafx_rd_direct.cpp` and `javafx_shader_translate.cpp`, including their
call sites and RD-only resource members. The default is `yes`, which retains
the runtime choice; it does not select RD rendering automatically. The option
does not disable Godot's RenderingDevice or Vulkan/Metal renderers.
Viewport-only builds reject `GODOT_JFX_RD_DIRECT=1` at JVM startup and normal
target initialization. Explicit `force_viewport` reference targets still work.
RD probes return an error dictionary and log the unsupported build; cleanup
remains safe. `JavaFXHost.is_rd_direct_compiled()` and the JNI method
`GodotBridge.isRDDirectCompiled()` report build capability, not the active
backend. Rebuild the SDK with the host after adding this JNI method; thereafter
the same SDK supports both host configurations.

GodotTexture is an actual Prism BaseTexture backed by a generation-tagged
native texture. GodotTexturePool uses BaseResourcePool accounting and
DisposerManagedResource lifecycle handling. The pool is created on the Prism
render thread and belongs to the single Godot rendering device. All contexts
for that device must share this pool and its command encoder; separate pools
must not independently allocate the same native slot namespace.

Implemented source formats are INT_ARGB_PRE, BYTE_BGRA_PRE, BYTE_RGB,
BYTE_GRAY, BYTE_ALPHA and FLOAT_XYZW. Uploads validate destination bounds, source offsets,
byte stride, buffer type and remaining elements using overflow-safe arithmetic.
They read without changing the caller's position/limit, including read-only
and direct buffers. Alpha masks become premultiplied white RGBA; premultiplied
ARGB/BGRA components are reordered without multiplying alpha again.
FLOAT_XYZW preserves four signed float32 channels in native RGBAF textures,
rejects non-finite input before emission, and supports padded/read-only buffers.

Uploads call the context's vertex-flush callback unless skipFlush is requested,
then encode bounded row chunks. RGBA/float uploads use approximately 256 KiB
chunks; BYTE_ALPHA uses compact single-channel chunks bounded by the 4 MiB
batch limit, with native RGBA expansion for ordinary alpha masks and R8 storage
for media planes. Full command batches are
submitted before further chunks are appended, allowing a 1024x1024 upload to
span the 4 MiB transport limit. Native texture revision tracking preserves
earlier draws. Upload admission itself is not a presentation fence; the current
presentation/pass completion protocol is described in bridge-protocol.md.

The pool accounts 16 GPU image bytes per pixel for FLOAT_XYZW, one for R8 media
planes, and four for ordinary byte/integer textures,
with a 512 MiB reclamation target and 1 GiB hard maximum. Native admission
separately bounds live and retired image revisions to 1 GiB. The reclamation
target is not a second allocation limit. These numbers do not measure
driver allocations or CPU image-shadow memory. Shared texture wrappers use
the same managed resource and lock count. Disposal flushes pending vertices,
queues release and recycles the slot with an incremented generation. Disposal
requested from another thread is drained by the normal resource-pool cleanup.

GodotSampler binds wrap/filter state per draw using level-zero texelFetch helpers.
It implements transparent border, edge clamp, repeat, nearest and bilinear sampling;
filter changes flush pending vertices. The generated Prism and Decora shaders
use this path. RTTexture, GraphicsPipeline, ResourceFactory and Presentable now
connect standard Stage/Scene rendering to offscreen native passes. Mipmaps remain
unsupported. Planar YCbCr video uses MultiTexture and the stock GPU YV12 shader;
see media-godot.md for plane and real MediaView coverage. Explicit RT readback is implemented
as described below. All five Prism
CompositeMode values now have GPU implementations (see below).
The packed MediaFrame update path holds/releases its frame. Media coverage is
tracked separately from JavaFX controls and VFX rendering acceptance.

Validation:

```powershell
.\scripts\test-bridge.ps1 -PrismTextures
.\scripts\test-bridge.ps1 -PrismTextures -Renderer mobile
```

PrismTextureProbe constructs the production Prism Texture classes, uploads
the five byte/integer formats with source padding/offsets, checks shared locks and slot
generations, rejects invalid/unlocked uploads, exercises deferred disposal,
and uploads a 1024x1024 direct buffer across two batches. Float coverage checks
stride/position, finite validation without partial patches, filter flushing,
16-byte accounting and release. The Godot fixture
checks six GPU-rendered colors and resource release. Both GL and Vulkan pass;
godot-prism-textures-<renderer>.png captures were inspected. Logs are
m2-bridge-prism-textures.log and m2-bridge-prism-textures-mobile.log.

## Generated Godot shaders

JSLC now supports the -godot target, implemented as a JSL AST backend using
the existing GLSL type/function mapping. It emits CanvasItem shader code
with premultiplied blending, UV0, CUSTOM0 UV1 and premultiplied vertex-color
varyings. Pixel coordinates use SCREEN_UV / SCREEN_PIXEL_SIZE. The local
Lighting variable E is renamed because Godot reserves that constant; other
backends keep their original declaration names.

Prism and Decora build generation now packages .gdshader resources into the
source SDK. Generator tasks track compiler outputs, so compiler changes
invalidate generated resources even when JSL timestamps are unchanged.
The Windows variant sets match existing D3D generation: 212 Prism and
50 Decora shaders. test-shaders.ps1 verifies variant names, exact packaged
contents, and Godot parser acceptance for all 262 on both GL and Vulkan.
It additionally renders generated FillPgram_Color and checks interior,
exterior and fractional-edge coverage. GPU readbacks are
godot-generated-shader-<renderer>.png. This is parser coverage for all shaders
and actual GPU pixel coverage for one mask, not full effect/rendering coverage.
Sampler/uniform binding, material state and effect render targets are now
connected through GodotContext; the sections below describe that integration. Stock D3D ReferenceSmoke still passes.

## Shader descriptor state

GodotShader implements Prism Shader with render-thread ownership, generated
resource loading, typed scalar constants, vec4/ivec4 arrays and immutable
draw snapshots. Float inputs must be finite; setters validate before changing
state. Array offsets/counts use D3D's vec4 register units and preserve buffer
position. Prefix updates retain the remaining declared array values. Snapshots
own defensive copies and remain usable after the descriptor is changed or
disposed. The selection callback is connected to GodotContext.

`scripts/test-shader-state.ps1` invokes all 212 actual generated Prism loader
classes through ShaderFactory and checks their sampler/parameter declarations
against the packaged Godot sources. It also checks snapshot isolation, partial
arrays, source offsets, type/range rejection, thread ownership and disposal.
The source SDK build and this probe pass. This validates Java descriptor state;
isValid currently reports descriptor lifetime, not native GPU compilation.
Sampler filtering/wrapping is implemented by GodotSampler; arbitrary application
compatibility is broader than this descriptor-state fixture.

The native surface now preserves material state revisions: changing draw
shader code or replacing the parameter dictionary after recording geometry
starts a new CanvasItem/material/shader segment. Sibling draw indices preserve
submission order. Unchanged state keeps appending to the same item. Clear frees
retained segments before releasing meshes and retired texture revisions; tree
removal frees all segments. This surface path duplicates shaders per state change. The offscreen
JavaFXRenderTarget viewport path has a bounded 64-entry shader cache; the
optional RD path has a separate shared bounded pipeline cache described below. Do not
interpret this surface limitation as absence of all native shader caching.

The generated-shader fixture checks real overlapping red/green/blue GPU pixels
after changes to both uniforms and shader source. It repeats 100 clear/draw
cycles and verifies resource counts return to eight after clear and zero after
removal on GL and Vulkan. `godot-shader-states-<renderer>.png` records the GPU
readback. The M1 vertex fixture now sets its shader before recording geometry,
matching the new snapshot semantics. Native dictionary parameters work through
RenderingServer; standard scene rendering is connected through GodotContext.

Shader snapshot transport is now implemented as command 11 in
GodotRenderCommands and the native decoder/host consumer. It carries complete
source plus typed scalar/vector/vec4-array constants. The host converts values
to Godot Variants and applies them to the revision-owned draw material. Sampler
names map via Java texture units to versioned native texture handles. Source is currently restricted to nonempty
ASCII up to 256 KiB; this includes the generated shaders. Native shader syntax
compilation still happens on consumption, not during queue admission.

`test-bridge.ps1 -ShaderStates [-Renderer mobile]` exercises actual Java
GodotShader snapshots through JNI, using vec4-array colors and an integer index.
Two meshes keep their original purple/green output after the Java parameters
are changed and the Shader disposed. Both backends pass pixel and resource
checks; the Vulkan GPU readback was inspected. Protocol tests reject truncated
constants, unknown types, oversized arrays and non-finite floats without
changing the previously decoded frame. Other scalar/vector types are decoded
and converted but do not yet have individual GPU pixel coverage.

The probe additionally binds a sampler at unit 1, updates its texture from
white to green between draws and disposes the logical texture before native
consumption. Both GL and Vulkan retain correct old/new GPU revisions. Shader
samplers participate in transactional queue resource validation and the same
retired-memory budget as ordinary textured quads. Clear removes parameter and
sampler bindings before releasing retired textures; the context must rebind
state afterward. Current GodotSampler helpers explicitly map Prism filtering
and wrap modes rather than relying on Godot defaults. SDK, editor and runtime builds pass with this change.

## Prism context and Graphics integration

GodotContext extends the upstream BaseShaderContext and consumes VertexBuffer
batches with stock shader selection, texture units and copied 2D transforms.
GodotResourceFactory supplies generated stock shaders and the existing texture
pool; texture compatibility checks pool identity. GodotGraphics inherits
BaseShaderGraphics geometry/paint handling, submits commands on sync and clears
the host surface using premultiplied GPU geometry. No scene bitmap is generated.

test-bridge.ps1 -PrismContext invokes production Graphics.fillRect with two
paints, translation and scaling. GL and Vulkan pass the existing expected-pixel
checks and host resource release check. Captures are godot-prism-context-<renderer>.png.
This fixture supplies a test RenderTarget; the separate Stage test below covers
initial Presentable and GraphicsPipeline integration. Blend modes other than SRC_OVER/SRC, RTTexture,
blit, perspective/depth and 3D were explicit unsupported operations at this stage
(RT allocation and GPU blit are implemented in the later sections below). Their
2D support was subsequently implemented; perspective/depth and 3D remain outside
the supported 2D path. The current pipeline supplies one device factory/pool,
so independent factories must not allocate in the shared host texture namespace. Media texture creation was not integration
tested at this historical stage; current coverage is documented in media-godot.md.

Device-space scissor is implemented through command 12. GodotContext copies
the Rectangle and rebinds it with each batch. Native CanvasItem custom bounds
and clip state are retained per draw segment, so later clip changes cannot
change older geometry. The context probe checks a clipped blue rectangle,
empty clip, and an unclipped red rectangle after reset on GL and Vulkan.
The Vulkan GPU image was inspected. Graphics.clear with a non-null clip draws
replacement geometry in device coordinates. clearQuad transforms its geometry
in user space, retaining the device-space clip. Both bypass blending, including
when writing transparent pixels, and conservatively update target opacity.

SRC mode uses a generated Prism shader variant with blend_disabled in place of
blend_premul_alpha. SRC_OVER retains premultiplied source-over blending. The
context probe distinguishes these using half-alpha red over opaque blue and
checks half-alpha blue clipped clear plus translated/scaled clearQuad. Both
GL and Vulkan pass. CLEAR, DST_OUT and ADD are also implemented by the
premultiplied compositing adapter described below; direct use of Godot's additive
blend alone would multiply source alpha again.

## Initial standard Stage presentation

GODOTPipeline supplies one device resource factory. GodotPresentable maps the
captured Glass window ID to a retained host layer, maintains render dimensions/scales, and submits
prepared commands asynchronously. A successful present means queue admission,
not GPU completion. The initial single-Stage test reuses the root native window;
current secondary Stages receive independent Godot-owned native windows through Glass.

The initial retained-layer path used WINDOW_PRESENT rather than anonymous
PRESENT. Current independent native windows use NATIVE_WINDOW_PRESENT; see
logical-windows.md and bridge-protocol.md.
GodotContext owns the published GPU target across Presentable replacement during
resize; new publication releases the previous target, while disposal/Glass close
remove the layer before texture disposal. OpenGL and Vulkan separate-thread tests
cover 40 size changes, six sizes, per-frame content retention and cleanup. Additional
native Glass windows and render-scale fixtures are implemented; physical
mixed-monitor/DPI transitions remain unverified;
see glass-godot.md and acceptance-status.md for current evidence and limitations;
logical-windows.md describes the superseded embedded-window model.

test-stage.ps1 [-Renderer mobile] runs an ordinary Platform/Stage/Scene with
two Rectangle nodes. Both GL and Vulkan pass pixel checks, single-native-window
ownership and final host-resource release. godot-stage-<renderer>.png captures
the GPU result; Vulkan was visually inspected. No alternate Prism backend is
selected. Standard Stage icons now support replacement, clearing and hide/reshow;
see glass-godot.md for native-pixel verification.

The initial retained-history implementation grew to 638 resources after 79
dynamic batches. Presentation boundaries now preserve GPU framebuffer pixels,
disable viewport redraw while assembling a frame, request one update on commit,
and release completed command resources after rendering. Consumption stops at
commit until that cleanup. The 120-move Stage test passes on GL and Vulkan with
observed peak/final resource counts of 9 and correct old/new/stationary pixels.
No CPU snapshot or full-scene bitmap is used. Window background is composed
behind the persistent surface so it cannot erase dirty-frame contents.

Controls, effects, RTTexture, resize/render-scale and embedded Godot scenes now
have integration coverage. Physical mixed-DPI behavior and wider visual stress
remain unverified. GLSL capability identifies the generated shader family;
arbitrary ES2 shader streams remain unsupported. Decora integration is implemented
through the generated GPU effect shaders.

## Offscreen target groundwork

Adding unmodified Label/Button to StageProbe exposes missing RTTexture support
through BaseShaderGraphics.initLCDSampleRT. This initial failure is now resolved
through GPU target routing and a sampleable backbuffer; LCD text was not disabled.

The default viewport path of JavaFXRenderTarget starts with five owned
RenderingServer RIDs: viewport, canvas, commands, shader and material. Its
optional asynchronous texture proxy adds another owned handle; the optional RD
path delegates texture/framebuffer ownership to OffscreenPass instead. It records GPU rectangle passes
and target-to-target texture copies, preserving sampled targets with strong
references. Cyclic/self sampling is rejected; the first pass clears to avoid
uninitialized pixels. The default viewport texture remains borrowed, never freed
as an independently owned texture; an explicitly allocated proxy has its own
release responsibility. A surface can retain and compose such a
target directly, with no CPU readback in the rendering path.

test-render-targets.ps1 [-Renderer mobile] passes 100 two-target copies on both
backends, checks premultiplied output and verifies target objects disappear after
the last drawing reference is cleared. The Vulkan GPU capture was inspected.
Java RTTexture/ledger registration, Prism shader rendering, target switching
and LCD snapshot passes are connected through commands 15/16/17.
Callers must finish/render a pass before rewriting its sampled viewport; this
low-level API does not yet provide immutable revisions of mutable RT contents.

GodotRTTexture now extends the production texture resource wrapper and allocates
through command 15. It retains RT type across shared-wrap aliases and uses the
same pool/disposal accounting. CPU updates throw, and native ledger validation
also rejects image/region writes to RT handles. Readback was unsupported at this
stage; the explicit readback implementation is described below.
The context probe verifies
real Java RT allocation and native transparent sampling on GL/Vulkan, retaining
the disposed viewport through the submitted draw and releasing it on clear.

Native offscreen passes now accept Prism quads, independent shader/material
parameters and clipping. Host/offscreen paths share prism_mesh.h for all Prism
attributes. The viewport path records draws into owned or reused CanvasItems;
the RD path records device draw commands. Ordering is preserved
between rectangles, copies and mesh batches.

Unchanged geometry is not re-encoded either: the Java render-command encoder
content-hashes each quad batch and redraws repeats through a QUADS_REF handle
(see bridge-protocol.md), so a batch under a translating parent neither
re-serializes its vertices nor re-decodes them on the host. Offscreen targets
additionally keep one persistent draw slot per batch position (CanvasItem plus
attached material reused across passes; only the command list and draw index
refresh) and share immutable (shader, parameters) materials, including validated
live texture RID bindings. A slot is recreated when a shader change or omitted
instance parameter requires resetting prior defaults. Two
Godot behaviors bound this design: `canvas_item_set_visible(false)` interacts
with pending UPDATE_ONCE viewport renders (observed blanking effect output),
so retired slots have their command list cleared instead; and
`canvas_item_clear` resets recorded clip state, so a reused slot re-applies
its custom rect and clip together with the mesh command. Diagnostic switches:
`GODOT_JFX_GEOMETRY_CACHE`, `GODOT_JFX_SLOT_REUSE`, `GODOT_JFX_MESH_CACHE`.
Measured on the 68-page transition benchmark the host's geometry command
application halves (11.1 s -> 5.2 s per 35 s run); overall page-flip rate is
unchanged in that historical run. Its proposed attribution to re-encoding and
pass count was investigated further below; it is not a current architecture-wide
performance limit. The updated 100-cycle fixture
checks a clipped half-alpha shader pass copied to a second target on GL/Vulkan,
including transparent pixels outside the clip. Its Vulkan GPU capture was
inspected. The Java target-switching layer ends each current pass, waits for
native post-draw completion through queue scheduling, then selects the next RT.
Presentable owns an RT backbuffer that LCD shaders can sample. Final presentation
copies that completed backbuffer to the host, preserving the visible previous
frame while intermediate offscreen passes execute.

StageProbe now renders Label/Button and Chinese/English text on GL/Vulkan.
It performs 120 rectangle moves (observed resource peak/final 28), then injects
mouse click and Space through Godot Input. Both Action callbacks run on the FX
thread. Pixel checks and separate waits verify each Label update is rendered;
the final Vulkan capture reads "Action 2 中文" and was inspected. Texture handles
are captured at bind time, matching Prism's allowance for unlocking cached
textures before vertex-buffer flush. This is limited control coverage, not VFX,
all Effects, readback, multiple windows or complete DPI/resize acceptance.

## GPU render-target blit

`GodotContext.blit` uses a dedicated replacement shader to copy an RT rectangle
to the destination selected by upstream `BaseShaderGraphics.blit`. A null
destination means the current Graphics render target. It flushes pending vertices,
preserves the normal target-switch/pass fence ordering, and samples the GPU texture
without CPU readback. Linear filtering and physical-edge clamping do not depend on
the source's ordinary draw-time sampling preferences. Geometry supplies scale and
axis reversal; caller transforms, clip, extra alpha and external shaders do not
affect the copy. Subsequent normal quad batches re-emit their retained Prism state.

`scripts/test-blit.ps1` passes GL/safe and Vulkan/separate, checking crop/scale,
premultiplied SRC replacement, a bilinear transition, horizontal flip, normal
drawing after blit, and release of sampled RT resources. Source and destination
must be compatible Godot resources; same-storage copies (including shared-wrap
aliases) are explicitly rejected. MSAA resolve remains unsupported.

## Explicit render-target readback

`GodotRTTexture.readPixels` now supports whole-target and rectangular reads into
IntBuffer (ARGB_PRE) or ByteBuffer (BGRA_PRE, independent of byte order). Heap and
direct buffers, slices and nonzero positions are supported. Writes start at the
current position without changing the caller's position or limit. Invalid bounds,
insufficient remaining space, read-only buffers and other buffer types are
rejected before native submission. `getPixels()` remains null, as on D3D; callers
use the readPixels path. CPU uploads into RTTexture remain unsupported.

The render context flushes vertices and ends its active pass, then sends a bounded
JNI request with the last admitted sequence. The Godot main thread waits for that
sequence's render fence and performs `texture_2d_get`; JNI threads never call Godot
resource APIs. A new target's already-scheduled transparent initialization is
completed before its first read. Subsequent reads do not reopen an empty pass.
The native layer currently reads the full texture, then crops and packs the result;
this is an explicit synchronous GPU stall, not a normal per-frame presentation
path. The bridge admits one outstanding read, caps dimensions at 8192, rejects
stale/non-RT handles and unfinished source passes, and bounds waits to ten seconds.
Host stop wakes the caller with failure and leaves its output buffer untouched.

`test-readback.ps1` checks transparent initialization, premultiplied channels,
rectangle rows, heap/direct/sliced buffers, validation, stale handles and drawing
after readback. `-Snapshot` exercises standard synchronous Node/Scene snapshots
and an asynchronous Node snapshot with FX-thread callback and pixel checks.
`-StopDuringRead` withholds host processing until a request is observed pending,
then checks cancellation without partial writes. GL/safe and Vulkan/separate
direct/snapshot probes pass; Release Runtime Vulkan/separate snapshot and stop
probes pass. Raw RT resources are disposed; the application fixture drains windows
and checks all host-owned resources at teardown, including Quantum pool caches.

An adjacent 2x2 SRC rectangle experiment showed a zeroed edge row in the first
read, before any second readback. The dedicated D3D comparison below reproduces
that same behavior, resolving the suspected Godot discrepancy. The readback buffer
fixture uses SRC_OVER to isolate data transfer; the edge fixture keeps the original
SRC/AA case.

## Premultiplied compositing

`GodotComposite` adapts the final premultiplied shader output without a destination
readback or a new Godot blend mode. SRC_OVER retains `blend_premul_alpha`; SRC uses
replacement. CLEAR replaces with zero. DST_OUT outputs `(1-source_alpha)` in all
four channels with `blend_mul`, yielding destination RGBA times that factor.
For ADD, Godot's source factor is source alpha for both RGB and alpha. The adapter
outputs `(rgb/sqrt(a), sqrt(a))` (zero for zero alpha) with `blend_add`, producing
the original premultiplied addend in all four channels. Normal render-target
clamping handles saturation. This assumes valid premultiplied shader output.

Conversion runs at the end of the existing fragment body, retaining builtin scope;
comment braces and nested blocks are skipped when locating that body end. Godot
itself forbids return statements in processor functions. These additional modes
require a shader declaring the Prism premultiplied blend contract. The conversion
preserves named samplers and uniforms; mode changes use upstream vertex flushes.

`test-composite.ps1` checks 25 mode/input combinations and their excluded clip
regions against independent Porter-Duff equations. Inputs include solid alpha
0, 0.25 and 1, an RT texture, and a custom fragment with nested blocks/comments.
Tests also dispose both render targets and check final native resource release.
GL/safe and Vulkan/separate pass, and the GL viewport capture has been inspected.
Antialiased geometry edges and a wider effect/custom-shader stress suite remain
outside this fixture's pixel coverage.

`test-composite-edges.ps1` additionally runs identical Prism drawing code on the
source-built D3D and Godot pipelines. All five modes are checked with AA on/off
and integer or quarter-pixel offsets: 20 cases, 16 pixels each, compared in all
four premultiplied channels with a tolerance of two 8-bit levels. GL/safe and
Vulkan/separate pass. The adjacent SRC edge row is transparent with AA on and
retains red with AA off in both D3D and Godot. Raw results are saved under
`artifacts/reference/composite-edges-*.txt`, with comparison logs under
`artifacts/logs/composite-edges-*`. These small rectangles do not cover every
shape, transform or effect shader.

## LCD text: destination sampling through the renderer backbuffer

Prism renders subpixel-antialiased ("LCD") text with a two-step algorithm: for
every text node it first copies the pixels under the text from the current
render target into a scratch texture (the "LCDBuffer"), then draws the glyphs
with a shader that mixes glyph coverage against that background copy with
gamma correction. Each such copy is a render-target switch plus one offscreen
pass. A large table page holds ~100 text nodes per frame, and dragging it
re-renders all of them: profiling the 50-row table page measured 117 offscreen
passes per pulse, of which ~97 came from these per-node LCD round-trips
(confirmed by an A/B run with `-Dprism.lcdtext=false`, which dropped the count
to ~20).

The Godot pipeline avoids the separate LCDBuffer copy without disabling LCD
text. It still starts a new pass at each JavaFX LCD sample boundary, preserving
background changes between overlapping text nodes. The initial implementation
and its historical measurements follow; later repairs are described below.
`GodotShader.loadPrism` rewrites the generated second-pass LCD shader when it
is loaded: the `dstColor` sampler declaration becomes a
`hint_screen_texture` uniform, the destination sample becomes
`texture(SCREEN_TEXTURE, SCREEN_UV)`, and the destination coordinates are
passed from `fragment()` as `SCREEN_UV`. Godot's canvas renderer snapshots the
backbuffer at the first such draw of each render pass (once per pass, not per
text node — see `material_screen_texture_cached` in the renderer), so the
destination is still read with correct per-pixel alignment. On the pipeline
side, `BaseShaderGraphics.initLCDSampleRT` skips the copy when the new
`lcdScreenSample` capability is set (`GodotGraphics` sets it, mirroring
`GodotContext.lcdScreenSample()` for `GlyphCache`, which then no longer needs
the LCDBuffer size for the unused second coordinate set). The readback path
still creates the LCDBuffer on demand and is unchanged. Setting
`GODOT_JFX_LCD_SCREEN=0` restores the original round-trip behavior for A/B
measurement.

Measured effect on the same binary (`test-vfx-table-scroll.ps1`, 96 drag
pulses over the 50-row table, `GODOT_JFX_LCD_SCREEN=0` as the A/B control):
mobile/safe offscreen passes 11,420 → 1,900 (-83%), fps 54.6 → 59.6,
p95 25.0 → 19.4 ms; mobile/separate fps 51.1 → 55.2; gl_compatibility/safe
fps 25.9 → 47.8 with p50 32.9 → 16.8 ms (the GL canvas backbuffer copy is far
cheaper than its per-round-trip viewport renders, so compatibility mode gains
the most). In every configuration the scrolling sweeps themselves stay at or
under ~17 ms (the display refresh interval). The full-page transition
benchmark improved from 30.9 to 35.0 fps with the worst page (the same table)
from 7.5 to 11.5 fps.

Historical semantic note (superseded by the 2026-11-10 repair below): this
optimization originally reused one snapshot across text nodes. GodotGraphics
now starts a new pass at JavaFX's LCD sample boundary for each text node, so
later overlapping text samples earlier glyphs. Commands remain batched. The RD
normalized snapshot coordinate also uses framebuffer Y directly, without a
second vertical flip. The overlapping-text fixture matches the LCDBuffer path
within 2/255 in both safe and separate modes; this is not a claim for all fonts.

Remaining known costs in these scenes: rounded-corner clips (VFX scene-group
and FusionPane clips are shape groups, so Prism renders them through the
effect pipeline with a handful of offscreen passes per frame — the same work
native pipelines perform), plus the Java-side re-encoding of genuinely
changed page geometry during transitions; host-side shader-state parsing
measured only 0.16 s of a 37 s transition run, so a protocol-level
shader-state deduplication was evaluated and deliberately not implemented.

## Draw modulation: opacity as draw state, not vertex content

The implementation mechanism below remains relevant; its performance numbers
and bottleneck conclusions describe the earlier viewport-based experiments.

The retained/differential rendering design (kimi session "option C") is now
complete in its reachable form. A batch's wire identity consists of its
content (local-space vertices + colors), its draw transform, and — new — its
uniform modulation. Prism's `NGNode.renderOpacity` renders an animating
opacity by multiplying the graphics extra alpha into every vertex color, so a
fading page changed every batch's color bytes each frame and defeated the
geometry cache: each frame re-serialized all vertices and rebuilt every mesh
on the host. VFX page transitions animate translate and opacity together
(`VScene.applyAnimation` calls `setLayoutX/Y` and `setOpacity`), which made
this the dominant remaining cost of page turns.

The pipeline now separates the uniform factor from the content:
`BaseShaderContext` gained a `vertexColorModulation` hook; the Godot context
returns 1 and records the value instead, flushing the vertex buffer whenever
it changes so one flush batch always carries exactly one modulation. The
encoder appends the float to every quad draw (opcodes 4/8/29), validated to
0..1; `GODOT_JFX_DRAW_MODULATE=0` restores the baked-in behavior on both
sides of the wire for A/B measurement. The host applies it as the mesh
command's modulate (premultiplied scaling of vertex colors — the same math
the bake performed, with one fewer rounding step; within the ±2/255 D3D
comparison tolerance). Because slot commands are re-recorded each pass
anyway, the modulate rides the per-command color and needs no slot-state or
match-key changes.

With modulation separated, a fading batch is byte-identical across frames:
opacity animation reduces to QUADS_REF references plus an animated float,
like translation already did. `get_render_stats()` exposes `quads_uploaded`
vs `quads_referenced` for direct observability of the hit rate.

The flush-on-change invariant splits a frame's batches at every modulation
transition, so the encoder also gained consecutive-state suppression:
identical back-to-back SHADER_STATE (11) and CLIP (12) emissions are skipped
because the host already treats them as persistent state. Tracking survives
submissions, is invalidated at every host-side reset point (target
selection, pass completion, presentation, frame begin, clear, texture
disposal) and disables itself entirely if a second command encoder ever
exists in the process, since two streams interleave at submission time.
`GODOT_JFX_STATE_SUPPRESS=0` opts out.

Measured outcome (alternating same-binary A/B, all runs focused, mobile/
safe): the 68-page transition benchmark is neutral within run-to-run noise
(41.6 vs 42.2 fps average; p50 17.4-18.5 ms both) while the geometry hit
rate improves (44,868 references / 23,565 uploads vs 41,514 / 25,626 —
8% fewer full uploads). The table drag fixture holds 59.9 fps with p95
19.4 -> 18.5 ms and p99 42.4 -> 41.1 ms. The honest conclusion: the
retained/differential architecture is now complete and measurably less work
per frame on the wire, but page-turn frame rate is dominated by the
rounded-clip effect passes each presentation performs (about 15 offscreen
passes per presented frame on the heavy pages) — the same passes native
pipelines run — so the fps ceiling there is unchanged by encode-side work.

## Historical page-turn gap investigation (2026-11-07)

The following investigation through the tenth batch records evolving hypotheses,
including conclusions later superseded by the optional RD implementation and
subsequent correctness repairs. It does not establish a current FPS ceiling.
Preserve the measurements as history rather than treating their proposed next
steps as unimplemented requirements.

After the LCD, modulation and suppression work the 68-page transition
benchmark still runs at ~43 pulses/s against native D3D's 62 on the same
machine. The gap is now attributed with a complete data chain:

- The same benchmark binary run natively (`-Dprism.order=d3d`) records
  61.99 fps, p50 16.0 ms — while performing **70,428 render-target
  switches** (~30 per presented frame). The Godot pipeline performs only
  **27,675** (~19 per frame, fewer because the LCD work removed the
  per-text-node round-trips) yet runs at 43.1 fps. Fewer passes, slower.
- An in-process stack sampler (embedded JNI JVMs cannot be attached by
  jcmd; `VfxTransitionProbe` samples FX/render threads when
  `GODOT_JFX_STACK_SAMPLE` is set) shows QuantumRenderer parked ~88% and
  the FX Application Thread idle ~97% of the run: **the Java side is not
  the bottleneck**. The workload sits in the host process, whose main
  thread is ~71% busy (draw_offscreen 9.5 s, geometry application 5.6 s,
  texture 2.0 s, target switching 2.3 s per 37 s run).
- Per switch, the host pays ~440 us: a `draw_offscreen_2d` viewport render
  through the Godot RenderingServer (Vulkan command encoding for the
  pass's draws). Native D3D's equivalent is a SetRenderTarget pointer
  change at microsecond scale. This is the "per-redraw unit price" gap the
  original kimi analysis predicted: the same Prism work costs an order of
  magnitude more per pass through the Godot viewport machinery than
  through an immediate-mode D3D context.
- `--render-thread separate` is slower for this workload (35.2 vs 43.1
  fps): pass rendering gains nothing from a second thread here, but pays
  its synchronization. Safe remains the recommended configuration.
- The host's per-tick burst budget (`GODOT_JFX_PASS_BUDGET_US`, default
  4000, and `GODOT_JFX_BATCH_CAP`, default 16) was environment-gated for
  A/B: raising to 10 ms / 64 batches moves the benchmark within noise, so
  queue draining is not the constraint either.

`BaseShaderContext.TARGET_SWITCHES` (printed by the transition probe as
`VFX_TRANSITION_TARGET_SWITCHES`) makes the pass count comparable across
pipelines; both native and Godot runs print it. Closing the remaining gap
requires making each offscreen pass cheaper than a full viewport render —
a RenderingDevice-level render path or Godot-engine viewport lightweight
path — which is engine-architecture work beyond the current bridge.

## Real-input drag: why the wheel is smooth and the drag is not (2026-11-07)

The table-scroll fixture gained three drive modes (`GODOT_JFX_DRAG_MODE`):
`direct` (handler calls per pulse, render cost only), `real` (Godot
synthesized motion through the full input pipeline at
`GODOT_JFX_REAL_EVENTS` motions per frame) and `robot` (Glass Robot moves
the physical cursor; the window must be foreground — diagnostic only).
Measured on the 50-row table (mobile/safe, 96 pulses):

- direct: p95 18.5 ms; real 1/frame: 24.1 ms; real 8/frame: 26.0 ms;
  real 32/frame: 25.7 ms; robot (real OS events): 25.2 ms. p50 is
  unchanged everywhere — event rate is not the driver.
- The real-input runs perform ~1,500 more full quad uploads than direct:
  the moving pointer synthesizes enter/exit pairs, VFX hover highlight
  follows the pointer, and the touched batches genuinely change content.
  That re-render work is real and native performs it too — the wheel does
  not move the pointer, which is why wheel scrolling stays smooth.
- Glass-Godot input itself coalesces properly: events drain in batches
  (`drainInput` behind a queued flag) and pulses stay locked to host
  frame ticks; no per-event pulse storm exists.

## Cutting the per-pass host cost (2026-11-07, third batch)

Phase instrumentation inside Godot (`GODOT_JFX_OFFSCREEN_PROFILE` prints
cumulative update/prepare/draw splits; `GODOT_JFX_RES_PHASES` splits the
resource update) decomposed the ~500 us per offscreen pass on the
transition benchmark:

- `RSG::canvas->update()` dominated at 225 us/pass while the actual
  viewport render was 96 us (later 34 us). Inside update(),
  `_update_queued_materials` — uniform-set rebuilds of queued materials —
  accounted for essentially all of it (4.4 s per 37 s run); the dirty-item
  walk was negligible (31k items, 12 ms total).
- Two host fixes landed. Slots no longer re-issue `canvas_item_set_material`
  when the material RID is unchanged — every rebind queued the item for a
  dependency update; skipping it cut the draw phase to a third. And
  `acquire_material` now caches RID-bearing parameter sets as well: entries
  record their referenced RIDs and every hit revalidates them against a
  live-sampler set maintained at each texture retire/free site (surface
  dispose/revision swap/release, render-target and scene-view destruction).
  RID values never recycle, so a retired entry simply stops validating;
  cache misses now purge invalid entries, then capacity pressure evicts the oldest
  insertion. Previously dead entries waited for capacity pressure, retaining
  materials across repeated MediaPlayer disposal. Retirement keeps the existing
  pass lifetime so queued draws can finish. Cache removal also must not read the
  removed map-entry pointer; identity handling uses separate branches.
  This restores what the earlier "no RID materials in the cache"
  rule tried to prevent, but by construction: a hit guarantees every bound
  texture revision is still alive.
- Measured effect (after correcting an evaluation-order bug in the skip
  that initially measured 44 fps while rendering with stale slot
  materials — the bisect that found it is part of the record): the
  transition benchmark stays at 42.5 fps (within its 42-43 band; the
  fresh-path material switches there are genuine changes); the
  real-input table drag improves to p95 23.6 ms and p99 63.8 ms at 8
  events/frame (from 26.0/67.0), and the render-only floor reaches its
  best values (59.9 fps, p50 16.7 ms, p95 18.4 ms, p99 41.2 ms). The
  skip compares against the slot's PREVIOUS occupant captured before the
  local struct is overwritten — assigning the new material first made the
  comparison always false and silently dropped every rebind.
- What remains: ~44k material uniform rebuilds per run (~100 us each)
  driven by effect/clip-chain constants that genuinely change every
  animated frame (clip-region offsets of sliding pages). Those values are
  material uniforms in Prism's shader model; moving them to Godot per-
  instance parameters would require remapping the generated shaders and is
  the next architectural lever after this one. A/B experiments that did
  NOT pay off and are documented for the record: skipping the per-pass
  device sync in safe mode (39.1 vs 42.9 fps — the wait doubles as
  CPU/GPU pacing), raising the host burst budget (noise), and geometry
  cache 256 -> 1024 (uploads -7%, fps unchanged).


## Instance-uniform material migration (2026-11-07, fourth batch)

The predicted next lever was implemented: target-path shaders now compile
their value uniforms as Godot per-instance uniforms (`javafx_shader_
rewrite.cpp` rewrites `uniform <type> <name>;` to `instance uniform ...`,
memoized per source; samplers stay material-level because instance
uniforms cannot sample; shaders with more than 16 value uniforms keep the
material path). The SHADER_STATE handler splits constants into material
params and `target_instance_params`, and every slot draw pushes the
instance values through `canvas_item_set_instance_shader_parameter` — a
direct instance-buffer write, no queue, no uniform-set rebuild. The
shared-item immediate surface path deliberately keeps the original
sources: one item accumulates many draws, so per-draw instance state is
not expressible there. `GODOT_JFX_INSTANCE_UNIFORMS=0` opts out for A/B.

Measured honestly: pixel gates all green (composite-edges against D3D,
effects on both renderers, targets, shader cache) and the value-constant
share of `_update_queued_materials` is gone (5.47 -> 4.56 s per 37 s
run), but transition fps is unchanged (43.2 on vs 43.3 off vs the 42-43
band) and the table drag stays at its previous percentiles. Miss
classification and a sampler-RID trace explain why: every remaining
material rebuild is a cold miss whose key differs because the effect
chains' `inputTex` sampler names a different pooled render-target texture
on every command (RID sequence in the logs; the glyph atlas and mask
textures are perfectly stable). Stabilizing that requires frame-affine
reuse in the Prism effect image pool (Java side), which is the recorded
next lever; the per-redraw unit price of the remaining rebuilds and
viewport passes still dominates the gap to native 62 fps.


## Effect image pool frame affinity (2026-11-07, fifth batch)

Review correction (2026-11-09): forward/FIFO traversal now revisits the index
after removing a cleared or lost image. Previously the next live image shifted
into that index and was skipped, causing avoidable allocation in the opt-out
configuration. `test-image-pool-reuse.ps1` reproduces the old failure and verifies
both FIFO/LIFO reuse and tie ordering after repair; no new FPS claim is made.

The recorded lever was implemented: `ImagePool.checkOut` now scans the
unlocked pool most-recently-checked-in first (LIFO) instead of
front-first (FIFO). FIFO rotation handed equal-size images to successive
chain positions each frame, so any cache keyed on image identity could
never repeat; LIFO gives a stable per-position assignment whenever the
check-in order and the requested size classes are stable. Opt out with
`GODOT_JFX_IMAGE_POOL_LIFO=0`. Pixel gates pass (composite-edges against
D3D, effects on both renderers, render-targets, shader-cache, stage).

Honest measurement: transitions 42.7 (LIFO) vs 41.8 (FIFO) — inside the
41.8-44.4 band every configuration of the last four levers lands in —
and `queued_materials_us` did not drop (4.81 vs 4.69 s per 37 s run).
The reason is visible in the sampler-RID trace combined with pool
quantization: during a sliding page transition the effect chain's image
size classes change every frame (32 px quantum over a moving dirty
region), so images of changing sizes enter and leave the pool and the
material keys stay novel regardless of tie-break order. Combined with
the earlier findings (Java idle, pass count below native, per-pass
viewport render dominating), the remaining transition gap to native 62
fps is the per-offscreen-pass viewport render price in the Godot
RenderingServer — engine-architecture work outside the bridge — with a
secondary ~13 % constant from genuine per-frame material rebuilds.


## Pass-sync pipelining (2026-11-07, sixth batch)

The actionable slice of the "RD-level direct path": the per-pass
full-device `rs->sync()` was replaced by a configurable interval
(`GODOT_JFX_PASS_SYNC_INTERVAL`; default 0 = rely on the existing
end-of-tick batch fence). GPU-side ordering between a pass and later
sampling of its texture is the renderer's barrier responsibility; the
per-pass wait only paced CPU against GPU completion. After the earlier
material/instance fixes landed, waiting every pass measured 42.4 fps
against 42.4-45.2 across four no-per-pass-wait runs — the earlier
regression (39.1 in the third batch) no longer reproduces, and the
default now pipelines pass submission behind the batch fence.

Honest verdict: the difference is within the run-to-run band (42-45 fps
across six configurations today); all pixel gates pass with the batch
fence (composite-edges against D3D, effects x2, render-targets,
shader-cache, stage, intro -AllPages, table-scroll). The full
RenderingDevice-direct form of this lever — replacing canvas viewports
with custom RD draw lists so an effect pass costs a render-pass begin/end
plus draw rather than a viewport render cycle — is a renderer rewrite;
the bridge-level evidence (Java idle, pass count below native, per-pass
viewport render price dominating, material rebuilds at a stable ~13 %)
is complete enough to size that project, but it cannot be landed as a
bridge patch.


## Spike correction: the viewport cycle is cheap (2026-11-07, seventh batch)

`JavaFXHost.benchmark_offscreen_cycle` (exposed for reuse; the rd_spike
scene drives it) measures the bare offscreen viewport render cycle at
effect-pass resolution: 5.9-37.5 us per cycle for 0-64 draw items. The
~440 us/pass figure quoted in the gap analysis was the sync-inclusive
wall time of the old per-pass fence, not the cycle cost — consistent
with the phase instrumentation (draw_us ~30 us/pass) and with the batch
fence leaving fps unchanged. Consequence: the RD-direct rewrite's
recoverable ceiling is ~30 us/pass and cannot close the 17-20 fps
transition gap; the plan document has been corrected to "premise
falsified, do not start on the original grounds". The residual gap now
needs re-attribution against the candidates the cycle spike excludes:
the real GPU work of effect passes (blend/shader/mesh-heavy at 2x DPI),
the presentation pipeline, and the stable material-rebuild constant.


## Re-attribution with GPU timing data (2026-11-07, eighth batch)

`GODOT_JFX_GPU_TIMING=1` instruments the host window viewport
(`viewport_set_measure_render_time`, sampled per tick by the transition
harness; per-offscreen-target timestamps overflow the engine's timestamp
pool at ~18 passes/frame and return zero — recorded as a measurement
limit). Combined with fresh post-fence CPU counters:

- **Presentation pipeline is NOT the bottleneck**: the window viewport's
  GPU render averages 0.50 ms/frame (p50 0.505, max 2.8 ms over 1492
  samples) — 3 % of the frame budget.
- **Per-pass CPU submission is the dominant remaining term**: after the
  batch fence, `draw_sync_us` (now pure CPU-side encode wall, no GPU
  wait inside) is 7.72 s / 24,580 passes = **~314 us per pass**,
  decomposing as material uniform rebuilds ~120 us (4.5 s total),
  canvas dirty processing ~45 us, encode ~30 us, remainder queue/apply.
  At ~18 effect passes per presented frame that is ~5.4 ms/frame of
  submission CPU; process_us 22.6 s / 33.4 s wall (68 %) with the rest
  in composition, presentation and the Java pulse.
- **Frame math**: 5.4 ms pass submission + composition/present + Java
  pulse ≈ the observed 23 ms frames (43 fps). The material-rebuild
  "constant" previously sized at ~13 % is actually the largest single
  per-pass term; the RD spike was right to falsify the cycle-cost
  premise, and the cycle's canvas-update half is where the cost lives.

Next lever identified (not started): stop recreating effect materials
on texture-RID change — patch the cached material's texture param
(`material_set_param` queues one uniform rebuild instead of
create + N params + queue) or bind effect inputs outside material
params entirely. Expected ceiling: ~120 us x 24.5k = 3 s per run,
worth roughly 5-8 fps on transitions if the rest of the pipeline
scales.


## Material patching on texture-RID change (2026-11-07, ninth batch)

Historical experiment, removed during the 2026-11-10 review: the lookup key
includes the complete parameter hash, so differing sampler sets reach this
patch path on a hash collision. Mutating the material then changes earlier
queued draws too. Materials now remain immutable, with full parameter identity
checks and separate entries for collisions. Secondary entries are searched on
a primary miss so repeated collisions reuse their materials even after deletion
leaves a hole. `GODOT_JFX_MATERIAL_PATCH` no longer changes behavior. The
shader-cache fixture finds an actual Dictionary hash collision between live
sampler sets and checks both pixel regions plus repeated material reuse.
The following measurements describe the earlier implementation.

The lever identified by the GPU re-attribution was implemented: when a
cached material shares the shader and parameter shape with the request
and only texture RIDs differ (the steady state of an effect chain whose
input image is a fresh pooled target), the changed texture params are
patched onto the cached material (`material_set_param`) instead of
creating a new one — one queued texture-only uniform-set rebuild, a
stable material RID (so slot items also skip their rebind dependency
update), and no material object churn. `GODOT_JFX_MATERIAL_PATCH=0`
opts out. Pixel gates pass (composite-edges against D3D, effects x2,
render-targets, shader-cache, stage).

Honest verdict: transitions 44.5/44.5 on vs 44.0 off — inside the
42-45 band, far short of the estimated 5-8 fps; the rebuild counter
only dropped 4.70 -> 4.50 s. The estimate failed on one mechanism:
the ~120 us per rebuild is dominated by descriptor-set recreation
inside `update_parameters_uniform_set`, which fires whenever a texture
RID actually changes — patching removes the object create and the
uniform-buffer update but not the descriptor recreation. The table
drag reached its best real-input numbers (p50 16.6 ms, p95 22.7 ms at
59.9 fps). Removing the descriptor recreation requires binding effect
inputs outside material params entirely (per-item textures or a shared
texture array) — a protocol/render-path change, recorded as the
remaining path beyond this lever.


## Historical Canvas API limitation (2026-11-07, tenth batch)

The recorded final lever — moving effect inputs out of material
parameters (per-item texture binding or a shared texture array) — was
scoped against the engine's public rendering API and is not
implementable there:

- Per-item binding: `canvas_item_add_mesh` accepts exactly ONE texture
  (rendering_server.h:850); the canvas renderer batches items by that
  texture. Single-sampler draws already use it (our QUADS texture rides
  the item, not the material). Effect-chain shaders (Blend SRC_IN,
  Gaussian chains, LCD) bind 2-4 samplers simultaneously — there is no
  per-item mechanism for the second and beyond.
- Shared array: the canvas shader language supports `sampler2DArray`
  (shader_language.cpp:320), but the public API cannot create a render
  target that is an array layer — offscreen viewports render into 2D
  textures — so effect passes cannot populate array layers without
  RenderingDevice-level rendering, i.e. the falsified RD-direct project.
- Instance uniforms cannot carry samplers (values only), closing the
  last standard side channel.

Therefore the per-pass descriptor-set recreation on texture change
(~120 us, the dominant per-pass component) is a platform cost for
multi-texture canvas materials; removing it requires the RD-direct
backend whose premise was already measured out (cycle cost 6-38 us) or
engine-side API extensions. The then-observed ~44 fps transition rate on the viewport path was attributed
to these costs using: nine implemented levers with same-
binary A/B, the cycle-cost spike, the GPU re-attribution, and this API
survey. The remaining paths are engine work, recorded in
docs/rd-direct-backend-plan.md as "do not start on the original
grounds" plus this API-gap note.

## Native mesh cache review (2026-11-10)

The native Mesh cache uses one content hash to select a candidate and compares
complete COW-retained vertex/color bytes before reuse. An LRU list replaces the
full-map oldest-entry scan. Both 48 MiB of input payload and 4096 entries bound
cache admission; these are not total CPU/GPU memory limits. Pending draw commands
retain their own deduplicated Mesh references until clear/release, so evicting a
cache entry cannot destroy geometry still named by a CanvasItem command. Active
command references can outlive cache entries and are outside the cache budget.

The shared cache container rolls back a failed index insertion, accounts for
replacement before eviction, and checks subtraction before byte addition to
avoid overflow. `test-bounded-lru.cmd` validates bookkeeping and ownership;
`test-mesh-transform.ps1 -CachePressure` validates the actual rendering path.

### RD binding failures and temporary fallbacks (2026-11-10)

A uniform set built with a missing texture view and the white default is marked
provisional: the next acquisition resolves the views again, while the old set
remains alive until its queued draws finish. Required sampler/value-buffer
binding failures reject the draw with an error; shaders requiring no uniforms
can still draw without a set. A recorded set invalidated before submission is
skipped with an error rather than silently inheriting the previous binding.
`test-rd-missing-view.ps1` exercises an explicit empty sampler RID, verifies a
second binding is built for identical parameters while the first draw remains
queued, then checks fallback white and recovery to a valid green texture.
Safe/separate pass with exactly the expected missing-view error. This does not
cover allocation failure or device loss; those failure paths remain unverified.

Uniform bindings also record their value-buffer dependency. Evicting a uniform
buffer removes dependent sets from the lookup cache immediately, while both
sets and buffers remain on the delayed retirement queue for already recorded
draws. RD validity alone is insufficient: a still-live set can depend on a
buffer scheduled for destruction at the next batch commit. The regression
combines 129 distinct values with 17 mutable geometry batches and checks the
last visible draw after ring-driven submission.

Retiring uploaded texture revisions also drains pending RD batches before
freeing their engine RIDs. Clearing CanvasItem commands alone does not prove
that queued RD effect passes have consumed those revisions. The additional
commit is skipped when the retired-texture list is empty. RD_DEBUG adds set,
sampler-view, retirement and target-release IDs for lifecycle correlation;
these diagnostic runs are not performance measurements.

### RD pipeline creation failure cleanup (2026-11-10)

A newly compiled shader enters the shared pipeline cache only after pipeline
creation succeeds. If pipeline creation fails, its shader RID is released on
the rendering thread and the caller waits for that cleanup before reporting
failure. Successful creation adds no new synchronization. Successful pipelines now use a shared LRU cache capped at 256 entries and
16 MiB of source/translated-source/default-value payload. This budget excludes
container metadata, driver allocations and resources retained by queued draws.
Hash lookup always verifies full source content; colliding sources may replace
one another but cannot share the wrong pipeline. Oversized entries are rendered
without caching. Eight COW source memos are cleared before insertion/eviction,
so they do not keep evicted cache entries alive.

Each recorded draw separately retains its compiled pipeline owner. Eviction
therefore does not submit unrelated open passes or invalidate their bindings.
After the final draw/cache reference goes away, a render-thread call owns the
RID values and frees the pipeline followed by its shader. Cached uniform sets
invalidated by shader destruction are checked before reuse/free. Uniform binding
creation reuses the draw's already acquired pipeline, avoiding a second lookup
and avoiding duplicate compilation for uncached oversized entries.

The RD regression leaves a red draw open on one target while another renders
260 distinct sources, checks the 256-entry limit, then submits and reads the
original red image and draws the evicted source again with green parameters.
This tests cache eviction and pending ownership; it is not a driver-memory
measurement or device-loss injection.

### RD screen-snapshot ordering repair (2026-11-10)

The RD batch previously copied its destination before starting the pass, so a
screen-sampling draw could read the previous frame instead of the current clear
and preceding background. It now ends the initial draw list immediately before
the first screen-sampling draw, copies the destination, and resumes with LOAD
semantics. A clear-only pass is also completed before the copy. Subsequent
screen-sampling draws in that pass still share its first snapshot; this low-level pass alone does not create per-text-node boundaries. The later
LCD boundary repair below supplies those boundaries in the JavaFX pipeline.

The original regression seeded a prior pass red, cleared the next pass and
optionally painted blue. The old implementation returned red; see
`artifacts/logs/review-rd-screen-snapshot-before.log`.
The current fixture uses a prior magenta pass and a blue/green background,
then swaps sampled red/blue channels. It requires red/green or transparent,
so a dropped draw cannot pass by leaving the background untouched. It covers
helper calls, direct fragment sampling and a differently named screen sampler.

### LCD node boundaries and snapshot coordinates (2026-11-10)

`BaseShaderGraphics.prepareLCDScreenSample` is a no-op unless a pipeline opts
into renderer-backed LCD samples. GodotGraphics selects its current target,
flushes preceding vertices and closes/reselects the target at the existing
`lcdSampleInvalid` boundary. This retains JavaFX's per-node semantics while
keeping transfer commands batched. It adds native passes and snapshot copies;
the historical pre-repair FPS figures above cannot be reused for this change.
Later measurements are recorded in frame-benchmark.md.

RD `SCREEN_UV` uses normalized `gl_FragCoord.xy` directly because the production
NDC transform maps increasing local Y to increasing framebuffer Y. A top-blue,
bottom-green regression previously sampled green at the top; it now passes.
The later pixel-coordinate repair below applies the same orientation to the
perspective pixel-coordinate idiom.

### Pixel-coordinate orientation and corpus gate (2026-11-10)

`SCREEN_UV / SCREEN_PIXEL_SIZE` now becomes `gl_FragCoord.xy`, matching the
engine Canvas shader and the RD target's pixel mapping. The previous height-Y
formula returned 0.9686 instead of about 0.03125 for the first row in a 16-pixel
vertical ramp. The analytic production-path test checks every pixel center.
The complete generated corpus then changed from 186 strict / 76 edge-exempt
cases to 262 cases within 2/255. The edge/deferred exemptions have been removed;
`test-rd-corpus.ps1` requires every source and rejects all shader/runtime errors.
These are comparisons for the corpus fixture inputs, not every possible set of
uniforms, transforms or textures.

Blend-mode selection now uses the engine parser's `render_modes` declarations
when a nondefault mode might be present. Substrings only trigger parsing; a
helper named `blend_add`, `blend_mul` or `blend_disabled` cannot change the
pipeline mode. The same parse supplies uniform defaults when needed. This
fixes generated ADD/MULTIPLY effect helpers being mistaken for blend-mode
commands, which the fixed-input corpus did not expose under its original
sample textures. The production RD regression uses translucent helper outputs
to distinguish premultiplied alpha from accidental additive/multiply modes.

Screen samplers retain their declared names in RD GLSL. Only the Canvas hint
is removed and an explicit descriptor binding is added; the declaration stays
before helper functions. Renaming only a hard-coded SCREEN_TEXTURE reference
in the header left direct fragment references and other sampler names
undeclared. The regression failure is preserved in
`artifacts/logs/review-rd-screen-sampler-before.log`.

### RD readback ownership (2026-11-10)

After the render-thread readback job completes, the host transfers its RGBA8
vector to `Image::create_from_data` through Godot's copy-on-write storage and
clears the shared staging reference. It no longer creates a zero-filled image
and copies the full frame again, or retains the last frame in static staging
until the next request. This affects explicit GPU readbacks, not normal drawing.
The entry point requires the host main thread and a live target. An unexpected
byte count reports an error and returns no image; the existing host readback
request handler turns that into a failed request instead of a blank success.
The ownership regression keeps three images across CPU mutation, another GPU
readback, repaint and target destruction, and verifies their independent pixels.
It does not inject a GPU/device readback failure.

RD target initialization checks the color texture, framebuffer, screen snapshot
texture and RenderingServer bridge allocation separately. Failure reports the
specific resource and stops further allocation before scheduling bridge setup.
The caller drops the partial OffscreenPass, whose existing release path frees
the resources already obtained, then attempts the existing viewport fallback.
In particular, a missing screen snapshot no longer counts as successful RD
initialization. Normal regression tests do not simulate device allocation failure.

### Instance-uniform name memo budget (2026-11-10)

The Canvas path keeps a source-to-uniform-name memo separate from the RD pipeline
cache and each target's shader cache. It now uses an LRU with at most 256 entries
and 4 MiB of UTF-32 source/name payload plus name-vector storage. Container
overhead is bounded by the entry count; this is not a total process/GPU budget.
Oversized sources are processed normally without being retained. Full String
keys preserve equality across hash collisions. Returned name vectors carry
copy-on-write ownership, so later eviction does not invalidate a caller's list.
Module shutdown clears the memo. `test-shader-cache.ps1` explicitly tests the
viewport path and forces instance uniforms, restores its environment setting,
and checks both entry and byte pressure alongside the existing pixel/resource
assertions. Read-only `get_instance_uniform_cache_stats` reports this memo only.

Module shutdown cleanup is restricted to MODULE_INITIALIZATION_LEVEL_SCENE,
matching registration. Godot invokes module uninitializers for several levels;
running the same resource cleanup at EDITOR, SCENE, SERVERS and CORE previously
repeated the RD summaries and revisited cleanup after services were torn down.
The profile-enabled RD regression now requires exactly one summary per process.

### RD diagnostic descriptor retirement (2026-11-10)

The separate translation/cycle probe now queues uniform-set retirement before
freeing its screen-snapshot stand-in texture or shader. RenderingDevice frees
dependent sets when their texture is destroyed, so the previous order produced
an invalid-ID free after an otherwise successful LCD pixel comparison. Cleanup
also checks set validity in case an externally owned input already invalidated
it. `test-rd-lcd.ps1` checks the complete log as well as the exit code and pixel
marker; a PASS followed by a teardown ERROR is a failure. This repair affects
the diagnostic probe; production OffscreenPass has its own lifetime management.

### Queued vertex-upload storage (2026-11-10)

Mutable vertex-ring updates bind the existing byte vector into the render-thread
call through PackedByteArray copy-on-write ownership. PackedByteArray is Godot
Vector<uint8_t>; the bound Variant retains its storage until the job consumes
it, and a later producer write detaches shared storage. The former extra
resize/memcpy allocated and copied a whole vertex batch before every update.
This change removes that duplicate CPU copy without passing a borrowed pointer
or changing ring reuse epochs, submission order or GPU buffer retirement.
Existing multi-pass ring-pressure pixel tests cover queued geometry lifetimes;
this alone is not evidence of a particular FPS improvement.

### Stock LCD shader rewrite consistency (2026-11-10)

When LCD screen sampling is enabled, the context no longer provides the old
LCDBuffer. The generated shader loader must therefore complete its destination
sampler rewrite. If the expected source markers are absent, loading now raises
an explicit error naming the shader, rather than retaining a dstColor sampler
whose input will not be supplied. LCD_SCREEN=0 retains the original path.
`test-lcd-shader-load.ps1` checks both stock variants and changed-format resource
fixtures without starting a toolkit; pixel coverage remains in lcd-overlap.

### Lost image pool candidates (2026-11-10)

When checkout locks a candidate and then detects a lost image, it now unlocks
that candidate before removing its pool entry. The reuse probe tracks lock
counts and orders a lost candidate before a valid one in each traversal mode;
previous no-op lock methods could not detect the imbalance. This is a resource
lifecycle correction, not evidence of a measured frame-rate improvement.

### Shared target geometry budget (2026-11-11)

Viewport RenderTargets now acquire one shared geometry cache on their first cached
draw. All such targets together retain at most 4096 cache entries / 48 MiB input
payload, rather than multiplying that allowance by the target count. Exact input
comparison still protects against hash collisions. The registry holds only a weak
reference; the last target releases the cache. Draw slots independently retain
meshes used by queued draws, so eviction does not invalidate their RIDs. Surface
caches remain separate. This bounds cache ownership, not all live geometry or
GPU/driver bytes. Cross-target budget, peer destruction and original pixels pass
in the mobile pressure fixture; full-soak memory comparison is still pending.
