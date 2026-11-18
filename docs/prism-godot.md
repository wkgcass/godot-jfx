# Prism-Godot implementation status

## Runtime detection marker

`javafx.application.GodotRuntime.PRISM_GODOT_ENABLED` is a public static volatile
boolean, initially false. Godot Prism sets it true only after successful host
validation and render-thread registration, and clears it when disposal begins.
It reports the initialized Godot Prism backend, independently of the requested
`prism.order`. Applications should read it
after JavaFX startup and treat the field as runtime-owned, not modify it.

The class is in the exported `javafx.application` package, so reflection needs no
internal-package exports. Applications supporting ordinary JavaFX can catch a
missing class/field and treat it as unsupported. The marker itself is live and
uncached; caching a reflected result is the caller's choice.

2026-11-12 validation: the source JFX SDK builds successfully, and consumer
checks distinguish initialized Godot from native D3D. Consumer reflection and
caching changes are maintained separately from this runtime marker.

The current backend is Viewport-only and requires safe rendering. The custom
RD-direct backend, shader translator, optional build flag and capability query
were removed on 2026-11-13. Godot itself still owns the underlying RenderingDevice
used by Vulkan/mobile. Dated evidence later in this document describes older
builds and is not a supported-mode list or current acceptance claim.

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
JavaFXRenderTarget viewport path has a bounded 64-entry shader cache. Do not
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
remove the layer before texture disposal. On the host surface a resize that
arrives after uncommitted draw content was already recorded is deferred to the
next begin_present; otherwise it is applied immediately. Either way it is a
viewport swap: the retired viewport keeps presenting (stretched) until the
replacement has rendered its first frame, because Metal/RD reallocate the
viewport texture eagerly and the root window renders before the FX viewport
each frame, so in-place viewport_set_size showed one empty frame. Same-size
resizes are ignored. OpenGL and
Vulkan separate-thread tests
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

JavaFXRenderTarget starts with five owned RenderingServer RIDs: viewport,
canvas, commands, shader and material. It records GPU quad passes
and target-to-target texture copies, preserving sampled targets with strong
references. Cyclic/self sampling is rejected; the first pass clears to avoid
uninitialized pixels. The default viewport texture remains borrowed, never freed
as an independently owned texture. A surface can retain and compose such a
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
attributes. The viewport path records draws into owned or reused CanvasItems.
Ordering is preserved
between copies and mesh batches.

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
later overlapping text samples earlier glyphs. Commands remain batched. The
overlapping-text fixture compares the screen-sampling and LCDBuffer paths
within 2/255 in safe mode; this is not a claim for all fonts.

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

### Instance-uniform name memo budget (2026-11-10)

The Canvas path keeps a source-to-uniform-name memo independent of each target's
shader cache. It now uses an LRU with at most 256 entries
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
the memo is cleared once at SCENE, while the relevant services still exist.

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

Surface resize uses the immediate/deferred viewport swap described above.
A repeated size leaves the current viewport intact. When a sampler
revision is retired, its materials are removed from live targets' caches.
Materials recorded by a pending pass survive until its draw resources are
released. The Stage churn fixture checks closed-window ownership against the
same warm baseline on every cycle.
