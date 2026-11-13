# JVM host and batch bridge (M2 foundation)

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


## Viewport-only host contract

Rebuild the source host and JFX SDK together: the obsolete
`GodotBridge.isRDDirectCompiled()` JNI method and its GDScript capability query
were removed. Frame opcodes and packet layouts are unchanged. Targets use
Viewport rendering only. JVM startup rejects separate rendering before creating
the JVM; renderer selection (mobile or gl_compatibility) remains independent.

## Compact media planes (operations 27/28)

The source SDK and Editor/Runtime must be rebuilt together for these operations;
older hosts reject them. Operation 27 is ALPHA_TEXTURE_PATCH: little-endian
uint64 handle, uint32 x/y/width/height (24-byte payload header), then exactly
width*height bytes. Java copies the decoder's visible rows directly into an
owned command buffer, preserving caller position/limit and padded stride.
Ordinary BYTE_ALPHA textures retain RGBA storage; the host expands their
single-channel payload to replicated RGBA. Operation 28 is VIDEO_PLANE_ALLOCATE:
uint64 handle and uint32 width/height (16-byte payload), with R8 GPU storage.
Only media-plane allocation selects this format. The YV12 stock shader reads
the red channel for these planes; ordinary glyph texture semantics are unchanged.

The projected resource ledger charges one byte/pixel for R8, including referenced
retired versions. R8 accepts only operation 27 updates. Targets, scene textures
and floating-point textures reject operation 27. Bounds, generation, source
length, the 4-MiB batch bound, three-batch queue and 1-GiB projected resource budget remain
enforced. Invalid transactions neither consume a sequence nor mutate resources.
Native protocol tests cover format mismatch, malformed payload, region bounds,
valid retry after rejection and concurrent queue draining.

Whole-texture patches construct the new CPU shadow directly from owned incoming
pixels, avoiding a clone/blit of the previous full image. Existing RID reuse and
retirement rules still preserve previously submitted draws. Decoded planes are
uploaded to GPU textures; this is not decoder/GPU zero-copy or full-scene bitmap
rendering.

## Window icon payloads

`GodotBridge.windowIcon(long id, int width, int height, byte[] bgra)` returns the
acknowledgement sequence from the destination queue. ID zero targets the primary
host command queue (operation 25); positive IDs use native-window operation 5,
ordered with creation/configuration/destruction and rejected for closed IDs.
Dimensions 0x0 plus an empty array clear the icon; otherwise both dimensions
must be 1..256 and the BGRA_PRE length must equal width*height*4. Each queue caps
pending icon bytes at 1 MiB in addition to its existing command-count bound.
Rejected commands do not consume a sequence. JNI copies the payload before
queuing; only the Godot main thread converts channel order and calls
DisplayServer.window_set_icon. Native Godot owns replacement/destruction of the
HICON resources. The image retains premultiplied RGB for the Windows icon bitmap
and is never uploaded as a scene texture. No render-packet opcode changed.

## Independent-window JNI transport

GodotBridge.nativeWindowCommand accepts a positive monotonically increasing ID,
owner ID (zero for independent, -1 for the root Stage), operation, screen x/y, width/height, flags,
visibility and UTF-16 title. Operation 1 creates hidden, 2 changes geometry and
visibility, and 3 destroys an owner tree. Creation flags are 1 borderless,
2 transparent, 4 popup. The bounded queue admits at most 256 requests and 64 live
windows; dimensions are 1..8192 and titles at most 4096 UTF-16 units. Validation
uses the projected owner tree, so a child can reference an earlier queued create
and cannot target a child of an already queued destruction. Rejection does not
consume a sequence or mutate the projection. IDs cannot be reused.

Operation 4 changes one window property. Its flags field identifies the property,
x/y carry integer arguments, and title carries text: 1 title, 4 focus request,
6 Godot Window mode (0..4), 7 resizable, 9 always-on-top, 12 minimum size,
13 maximum size, 15 borderless, 16 IME enabled, 17 IME candidate position,
18 finish composition, 19 input enabled, 20 focusable, 22 lower window, 23 raise
window (both require zero x/y).
Boolean arguments must be 0/1; limits must be
0..8192 (zero removes a limit). Unsupported properties and unknown/closed IDs
are rejected before admission. Contradictory min/max pairs fail explicitly during
main-thread application. These operations never target the root or another window.
The legacy root host queue also accepts operations 19/20/22/23 and 24 (transparent
Stage, boolean x and zero y). Operation 24 controls both the native window flag
and viewport alpha; RGB-only background commands cannot add an opaque backing
when transparency is enabled. Operation 21 in that
queue is reserved for the separately validated custom-cursor command. Lowering
uses Windows SetWindowPos(HWND_BOTTOM), and raising uses HWND_TOP on the Godot main
thread without moving, resizing or activating the window. is_window_above reads
actual HWND ordering for integration probes. Enabled state uses
Windows EnableWindow; focusability uses Godot's NO_FOCUS flag. Secondary enabled
state is retained while hidden and reapplied after the HWND is recreated. Glass's
existing nested disable counter decides when to send the final enable command.
is_window_input_enabled reads the actual HWND state for native integration probes.
IME candidate coordinates are window-local and bounded to +/-1,000,000; completion
requires zero arguments and pumps Windows commits before acknowledgement. IME
preedit records carry the originating window ID like other input records.

Only the Godot main thread applies these requests, using the same thread as
Godot rendering. nativeWindowInfo returns an empty array until an ID
has a published snapshot or after its destruction; otherwise it returns 11 longs:
ID, owner, native window ID, x, y, width, height, visible, focused, mode, ack.
nativeWindowAck provides the latest applied sequence even after all windows close.
Snapshots and ack are published together. This queue is independently ordered from
the legacy host/render queues; Glass must await creation before using native state.
Normal JVM return closes admission but preserves accepted requests for consumption;
explicit stop/failure cancels remaining requests. No Java thread accesses Godot Nodes.

Earlier test-native-window-bridge.ps1 runs passed GL and the retired Vulkan
separate-thread mode with
two native windows, Unicode titles, independent resize/visibility, 12 hide/show
cycles, invalid requests, owner-tree destruction and clean native-window counts.
Protocol tests cover rejection atomicity, FIFO draining and finish admission.
The pre-fix Vulkan swap-chain failure is preserved in
artifacts/logs/native-window-bridge-before-window-sync.log. The existing encoded
host-stop regression passes. Secondary standard Stage creation/properties/snapshots
and GPU publication now use these APIs. Per-window input/focus/close use the input
queue described next; IME properties and window-addressed preedit are implemented,
while physical IME/DPI acceptance remains pending. Native GPU publication
uses opcode 26, described below.

## Window-addressed input

`pollWindowInputV2` drains records of twelve doubles: the existing nine input
fields, the source Glass window ID at index 9 (zero means the primary/root Stage),
and unsigned Windows wheel lines/chars at indices 10/11. Wheel records leave the
button field unused. Each UINT32 value is exactly represented as a double and
converted to Java's signed int bit pattern; 0xffffffff therefore remains -1.
The decoder rejects nonintegral, nonfinite and out-of-range settings. Other event
kinds leave the two extra fields zero. The renamed JNI entry rejects a mismatched
old SDK/host instead of silently parsing different record lengths.
Window callbacks supply local pointer coordinates and screen coordinates from
that window's origin. Kinds 15/16 indicate native focus gain/loss; kind 9 is a
close request, allowing JavaFX close handlers to consume it before destruction.
Kind 20 reports completion of an OLE drag/drop gesture and carries the
performed drop effect instead of a button in the second field.
The 4096-record bound and overflow failure apply across all windows. Legacy
pollInput drains the same queue with only nine fields for low-level probes; it
must not be used concurrently with the Glass consumer. Glass ignores events for
closed peers and keeps pointer/touch capture ownership across dispatch callbacks.
No Java event thread reads Godot Nodes or calls Windows window APIs directly.

`JavaFXHost` is a native Godot Node2D subclass owning a rendering surface.
`start_jvm(jdk, sdk, classpath, main_class)` loads the installed JDK's
`bin/server/jvm.dll` and invokes JNI_CreateJavaVM on a dedicated worker.
The SDK is the locally built OpenJFX SDK. No JVM source is rebuilt.
JNI RegisterNatives binds `com.sun.javafx.tk.godot.GodotBridge` inside the
source-built javafx.graphics module, without a separate GDExtension DLL.

The host requires the implemented `glass.platform=Godot` and `prism.order=godot`
backends. Failure to load them must not silently select Windows Glass or another
renderer. The low-level bridge probe alone does not exercise JavaFX controls.

## Ownership and scheduling

- Godot main thread alone consumes rendering commands and calls the surface /
  RenderingServer. Queue capacity is three batches; consumption can exceed three
  as producers refill it. The default process budget is 16 batches / 4 ms, checked
  between batches (see pass completion below).
- Java threads call submit once per batch. Native code copies the direct
  buffer and validates the entire snapshot before enqueueing decoded data.
  Java may reuse its buffer when submit returns; concurrent writes during
  submit are not allowed by the caller contract.
- The queue accepts at most three frames. A full queue returns false and
  leaves sequence ownership with the caller for retry. Accepted sequences
  must strictly increase; duplicates fail explicitly.
- Godot pulses increment a monotonic counter and wake `awaitTick`. Waiting
  callers see the latest tick (coalescing), not a growing queue of pulses.
- Stop drops pending commands, rejects new submissions and wakes waiters
  with -1. A Java daemon watcher calls Platform.exit. DestroyJavaVM runs on
  the bootstrap worker, never on the Godot main thread.
- The worker owns shared native state until VM destruction. If the node is
  removed before Java exits, the worker detaches and keeps that state alive.
  Applications must terminate their own non-daemon threads; a stuck user
  thread can delay VM destruction until process exit. This is a known
  lifecycle limitation, not a successful graceful shutdown.
- One JVM lifecycle per Godot process; HotSpot restart is rejected. The JVM
  DLL stays mapped until process exit to preserve TLS/callback safety.

## Version 1 wire format

All integers/floats are little endian, with no implicit padding. Header:

| Offset | Type | Meaning |
|---|---|---|
| 0 | u32 | magic 0x31465847 (GXF1) |
| 4 | u32 | version 1 |
| 8 | u32 | total byte length, including header |
| 12 | u32 | command count |
| 16 | u64 | positive sequence, at most INT64_MAX |

Each command starts with u32 opcode and u32 payload byte length.

| Opcode | Payload | Behavior |
|---|---|---|
| 1 | empty | clear the surface command list |
| 2 | 8 f32: x, y, width, height, r, g, b, a | append a rectangle |
| 3 | 2 u32: width, height | resize the surface |
| 4 | u64 geometry handle (0 = uncached), u32 vertex count, 32 bytes per vertex, then 6 f32 draw transform and 1 f32 draw modulation | append Prism quad mesh |
| 5 | u64 handle, u32 width/height, RGBA8 premultiplied pixels | create texture |
| 6 | same as 5 | replace texture contents, preserving previous draw revisions |
| 7 | u64 handle | dispose logical texture |
| 8 | u64 texture handle, then opcode 4 payload (including the geometry handle) | append textured Prism quads |
| 29 | u64 geometry handle, u64 texture handle (0 = untextured), 6 f32 draw transform, 1 f32 draw modulation | redraw registered geometry without resending vertices |
| 30 | u64 geometry handle | retire one registered geometry |
| 9 | u64 handle, u32 width/height | allocate transparent RGBA8 texture |
| 10 | u64 handle, u32 x/y/width/height, RGBA8 premultiplied pixels | update texture region |

Limits: 4 MiB per batch, 65,536 commands, surface dimensions 1..8192.
Rectangle values must be finite, dimensions nonnegative, colors in 0..1.
Unknown opcodes/versions, truncated input, trailing data and stale sequence
numbers are errors. This table lists the base commands and geometry extensions; later sections
describe shader state, targets, scene textures and window publication. Together
they form the current implemented vocabulary, not a pending M3 work list.

Quad vertices preserve Prism VertexBuffer's seven f32 attributes: x/y/z,
UV0.x/y and UV1.x/y, followed by four RGBA8 premultiplied color bytes.
Vertex order is top-left, bottom-left, top-right, bottom-right, with indices
0/1/2 and 2/1/3 for each quad. Counts must be positive, divisible by four,
and at most 65,536. All floats must be finite. Nonzero z is rejected until
3D projection is implemented. UV1 travels in the mesh's CUSTOM0 attribute;
it is not discarded by canvas_item_add_triangle_array. A 24-byte trailer of
six finite f32 values carries the 2D affine (mxx, mxy, mxt, myx, myy, myt)
applied to the whole batch at draw time: vertices stay in local space, so a
batch redrawn under a translating parent arrives byte-identical and the host
reuses its content-hashed mesh instead of rebuilding one per frame. Decoding
is atomic and validates all records before enqueueing. Meshes live in a
per-surface/target content-addressed cache (48 MiB LRU budget each); the
cache is released when its owner is, never on per-frame clears.

**Geometry deduplication (opcodes 29/30).** The Java encoder keeps a
bounded (default 1024 entries and 32 MiB array payload, per encoder) content-hash cache of emitted
quad batches; `GODOT_JFX_GEOMETRY_CACHE=0` disables it. A repeat batch is
redrawn through opcode 29 without reserializing or re-decoding its
vertices; the host resolves the handle to its resident mesh. Each fresh
batch may tag itself with a new unique handle, which the host registers
when applying the command. Handles retire through opcode 30 only after 64
idle submissions — far beyond the three queued frames — so a reference can
never outlive its registration. A `GeometryLedger` projected alongside the
texture ledger at admission enforces the handshake per queued frame: a
reference must name a live handle, a handle registers at most once, and a
retirement removes exactly one. The mesh store is cleared with the JVM.
Opt out entirely with `GODOT_JFX_MESH_CACHE=0` / `GODOT_JFX_SLOT_REUSE=0`
for content-cache and draw-slot diagnostics. The host counts applied
uploads and references as `quads_uploaded` / `quads_referenced` in
`get_render_stats()`.

**Draw modulation (opcodes 4/8/29 trailer).** Every quad draw carries one
f32 after its transform: the batch's uniform modulation in 0..1. The Java
pipeline stops baking the graphics extra alpha (node opacity) into vertex
colors — `BaseShaderContext.vertexColorModulation` returns 1 and the
modulation rides the wire instead (opt out with `GODOT_JFX_DRAW_MODULATE=0`
to restore the baked behavior). Because one flush batch must then carry
exactly one modulation value, the context flushes the vertex buffer whenever
the value changes before more quads are appended. The host applies the value
as the per-command modulate of its mesh draw (premultiplied scaling), which
multiplies vertex colors exactly like the bake did; the only difference is
one rounding step (colors quantize before rather than after the alpha
multiply, within the 1/255 tolerance the D3D comparison fixtures accept).
This keeps batch content byte-identical across opacity animation frames —
fades hit the geometry cache instead of re-uploading every vertex.

The Java geometry cache retains immutable coordinate/color snapshots and compares
complete content after a hash lookup. Admission is bounded by the configured
`GODOT_JFX_GEOMETRY_CACHE_MAX` entry count (default 1024) and 32 MiB of array
payload per encoder; object/map overhead is additional. Recently used entries
are not force-freed to satisfy these limits. When capacity is unavailable, or
a hash slot holds different content, the draw sends ordinary inline geometry
with registration handle zero. Idle retirement retains the existing 64-submission
margin. Budgeting does not change command formats or native handle lifetimes.

Texture handles encode slot in the low 32 bits and generation in the high
32 bits. Slots are 1..4096; generations start at 1 and increase by exactly one
when a disposed slot is reused, without wrapping. The admission queue checks
a projected ledger including all earlier accepted batches. A stale handle,
duplicate allocation, dimension-changing update, use-after-dispose, or memory
limit violation rejects the entire batch without consuming its sequence or
generations. Full updates retain dimensions; region updates are checked
against the projected live dimensions without overflow-prone addition.
Empty allocation allows images larger than one batch to be populated in
bounded regions. Prism performs supported pixel-format conversion and expresses filtering/wrap
behavior through its texture/shader paths; see prism-godot.md for their limits.

Native draws capture immutable RID revisions. Updates retain old RIDs only
if an existing draw references them; otherwise the current RID is updated.
Disposal similarly frees unreferenced resources immediately. CLEAR removes
Canvas draw references after ordered Viewport pass completion. Live plus retired image
bytes are bounded to 1 GiB in the projected ledger; CLEAR reclaims retired
budget. This is owner-level accounting, not a measurement of GPU driver
allocations or completion fences. Complete image payloads must also fit the
4 MiB batch limit; empty allocations have no pixel payload. Region patches
use a CPU image shadow to preserve untouched source-image pixels, and this
initial Godot adapter uploads the resulting image through texture_2d_update
or creates a new RID for a referenced revision. Native partial GPU transfers
remain a performance follow-up; this does not rasterize the JavaFX scene on
the CPU. Native allocation failure becomes Java OutOfMemoryError;
queue admission commits ledger/sequence only after its queue storage succeeds.

## Java render command producer

GodotRenderCommands owns a reusable little-endian direct buffer on its
creating thread. It accepts the arrays produced by Prism VertexBuffer,
validates each command before appending, grows from 4 KiB up to the 4 MiB
batch limit, and resets storage only after JNI confirms an owned copy.
It serializes native admission across contexts so retries preserve global
sequence order. Full-queue retries wait for Godot ticks; shutdown, thread
interruption or a ten-second stalled submission fails the context explicitly.
A returned sequence proves queue admission, not GPU completion. This producer
is used by the implemented GODOTPipeline, GodotResourceFactory and GodotContext;
its low-level bridge probe alone does not exercise that whole stack.

The encoded bridge probe submits 32 batches of 1024 vertices, forces buffer
growth, rejects invalid attributes without corrupting pending commands,
overwrites caller/encoder memory after admission, and checks rendered pixels.
The Godot fixture withholds host processing until the native queue reports an
actual FULL rejection, then resumes consumption. The host-stop variant also
requires a later encoder submission to fail. Run test-bridge.ps1 -Encoded,
optionally with -StopFromHost. Raw-byte protocol probes remain available.

## Host input boundary

The host metadata snapshot contains 16 ints. Indices 0..11 retain their original
meaning; 12..15 append the current host monitor's usable desktop x/y/width/height
from DisplayServer.screen_get_usable_rect. Glass uses these as Screen's visible
bounds, distinct from the full monitor rectangle at 5..8. The Prism pipeline
requires the expanded snapshot.

screenInfo() returns a separate immutable main-thread snapshot with 10 ints per
monitor: Godot index + 1, full x/y/width/height, usable x/y/width/height, and DPI.
The primary monitor is first; remaining monitors retain Godot index order. Glass
detects metadata changes on its event thread and invokes Screen.notifySettingsChanged,
then re-associates each window using greatest platform-coordinate intersection
(nearest monitor for entirely off-screen windows). Enumeration/metadata are live;
platform and output scales use DPI / 96 when HiDPI scaling is enabled, or 1
when disabled. GodotScreenLayout converts platform rectangles into anchored
logical screen bounds; window/input and Prism output paths use these scales. Monitor hotplug and cross-monitor movement
require hardware validation beyond the current single-monitor probe.

Godot's normal Node input callback enqueues mouse and key events on its main
thread. Glass drains them with `pollWindowInputV2()` on its event thread, including
before timer callbacks. A daemon input receiver also waits on `awaitInputTick`
and coalesces immediate drain tasks, so input need not wait for the next frame
pulse. View callbacks run on the JavaFX Application Thread.
The FIFO is bounded to 4096 events; overflow fails the runtime explicitly
rather than silently losing a button/key release. Ordinary View callbacks do not run on the Godot main thread; synchronous OLE
bridge upcalls are a separate path described below.

The first nine fields (also exposed by legacy `pollInput`) are: kind,
button/key, x/Unicode scalar, y, screen x, screen y, modifiers, wheel x/echo,
wheel y. Kinds 1..4 are motion, button press, button release, wheel; 5/6 are
key press/release; 7/8 are mouse enter/exit and 9 is a close request.
Window notifications share the FIFO, so closing a window can prevent later
events in the same drain from reaching its destroyed View. Mouse records retain their source window and its local/platform coordinates;
Glass converts through that window's scale before dispatch. GodotView separately
transforms input into its embedded viewport. Mixed-DPI movement and hardware
input still require the corresponding physical validation. Modifiers use
Glass's bit layout. Key symbols use Godot logical key codes and are translated
in Java independently from Unicode text; non-BMP text becomes a surrogate
pair. Echo events retain repeated press/typed delivery.

## Tests

```powershell
cmd /d /c scripts\test-protocol.cmd
.\scripts\build-windows.ps1 -Target jfx
.\scripts\build-windows.ps1 -Target godot-editor -WithJavaFXModule
.\scripts\test-bridge.ps1
.\scripts\test-bridge.ps1 -StopFromHost
```

The standalone native test checks malformed/truncated commands, atomic
decode, bounded backpressure/retry, duplicate sequence rejection, stop and
10,000 concurrent FIFO frames. BridgeProbe checks actual JNI argument
validation, buffer ownership, Godot ticks, rendered pixels and normal JVM
completion. The host-stop variant checks wake-up and VM shutdown. Actual
GPU capture is in artifacts/reference/godot-bridge.png; logs must contain
both Java and Godot PASS markers. These tests do not prove Glass input,
FX Application Thread semantics, Prism rendering, effects or VFX support.
# Shader state command (11)

The payload contains u32 sourceLength, ASCII source bytes, u32 constantCount,
then constants. Each constant has u32 nameLength, ASCII identifier bytes,
u32 type (0=float, 1=signed int), u32 components (1..4), u32 arrayCount
(0=scalar/vector, otherwise 1..1024 vec4 registers), and little-endian 32-bit
value words. Floats must be finite. Names are unique identifiers up to 128
bytes; source is nonempty and at most 256 KiB; at most 1024 constants are
accepted. Exact payload consumption is required. Shader syntax itself is
compiled by Godot on consumption. After constants, u32 samplerCount (0..16)
precedes sampler records: u32 nameLength, identifier bytes, u64 texture handle.
Sampler names cannot duplicate constants or other sampler names. Queue admission
validates all handles against the projected texture ledger and marks their
current revisions referenced. Later updates/disposals retain those revisions
until clear, even when the material is replaced before drawing.

The command replaces the draw shader state. Already recorded geometry keeps
its previous native CanvasItem/material state. Clear releases retained state
revisions and removes current parameter/sampler bindings before freeing retired
textures. Subsequent rendering must rebind state after clear. Java snapshots
are copied into the batch before native submission.

## Clip command (12)

Payload is 20 bytes: u32 enabled (0/1), i32 x/y, i32 width/height. Dimensions
must be nonnegative; a disabled clip requires all coordinates/dimensions zero.
Negative origins and empty clips are valid. The native surface maps this state
to CanvasItem custom bounds plus clipping. A state change after geometry starts
a new ordered segment, preserving old scissor bounds. Clear disables clipping.
GodotContext snapshots the Prism device-space Rectangle and emits it for every
vertex batch; vertex transforms do not transform the device-space clip.

## Presentation boundaries (13 and 14)

BEGIN_PRESENT (13) and PRESENT (14) have empty payloads; PRESENT must be the
last command in its batch. Queue admission tracks begin/end state across
batches and rejects nested begins, unpaired presents and drawing outside an
open frame once presentation mode is active. Texture transfers may occur
between frames. Present resets projected retained-version accounting because
the host stops consuming at that boundary until post-draw cleanup completes.

The native Viewport keeps prior pixels and remains disabled while a frame is
being assembled. PRESENT requests UPDATE_ONCE. frame_post_draw releases the
completed frame's geometry, materials and retired texture versions. Full CLEAR
requests clear-on-next-frame; clipped clear remains GPU replacement geometry.
Window background is outside the persistent framebuffer, behind presentation,
so it does not overwrite preserved pixels on dirty updates. Legacy standalone
surface/command probes without presentation boundaries retain their existing
recorded-canvas behavior. No CPU image snapshot is used for persistence.

## Render-target allocation (15)

TARGET_ALLOCATE uses the same 16-byte payload as texture allocation: u64 handle,
u32 width, u32 height. It reserves the same slot/generation and RGBA byte budget,
but records render-target kind. CPU image/region updates to that kind are rejected
transactionally. Ordinary shader/textured-quad sampling and disposal use the same
handle operations. Native ownership is a RefCounted JavaFXRenderTarget. Its
viewport texture is borrowed (see native-module.md). Referenced targets remain retained after
logical disposal until draw commands are cleared. Initial contents are transparent.
Target drawing/selection uses commands 16/17 below.

## Target selection and pass completion (16/17)

TARGET_SELECT (16) contains one u64 handle; zero selects the host surface.
Nonzero handles must be live render targets. END_PASS (17) is empty and may be
followed by another pass in the same batch. An unfinished drawing pass must end before selecting a
new target. Direct sampling from the active target is rejected. Pass completion
resets projected retained-version accounting; transient materials/meshes remain
alive until the pass's ordered draw completes before consumption continues.

On the default main-thread rendering server, the host can complete END_PASS
with RenderingServer.draw(false, 0) inside its process callback. This retains
the post-draw lifetime boundary without swapping the window for each LCD-text
or effect intermediate. Consumption is limited to 16 batches and a 4 ms elapsed
budget (checked after each batch; a single draw can exceed it). PRESENT still
uses the normal window presentation path.
END_PASS completes within the bounded main-thread batch loop, without waiting
for another display frame. Final presentations
and native-window compositions retain their normal completion path.
Queue admission stays bounded to three batches;
capacity wakeups allow the Java render thread to refill between passes.

The retained switches below default to enabled. Set an individual switch to `0`
to disable it for diagnosis; unset or `1` enables it. These defaults apply to
the Godot backend only; native JavaFX D3D scheduling is unchanged.

The `GODOT_JFX_BATCH_PASSES` encoder keeps target transitions in
one bounded transfer until publication/readback or the 4 MiB transfer limit.
The native consumer completes each END_PASS in command order, including within
a batch. Final PRESENT/window publication must still end its batch. The batch
is indivisible for the host process budget. `GODOT_JFX_DIRECT_OFFSCREEN=1`
selects the experimental single-viewport draw path, preserving its ordered CPU
fence and normal sampler/retired-resource cleanup without submitting an entire
GPU frame for every target transition.
`GODOT_JFX_DIRECT_PRESENT=1` additionally draws the final target directly and
queues window composition before returning to the host's normal draw. It retains
the CPU fence and only counts completion after window composition. Independent
native Stage routing is unchanged. Use `scripts/benchmark-vfx-frames.ps1` for
the same original VFX animation on D3D and Vulkan; pulse rates and completed
Godot presentations are distinct metrics, and the benchmark performs no readback.
Direct offscreen draws now execute synchronously on the Godot main thread.
A completed-pass batch fence remains for GPU pacing and resource ordering;
it is not a cross-thread callback. `GODOT_JFX_PASS_SYNC_INTERVAL` optionally
adds per-pass pacing. Java command-queue bounds and completion notifications
remain necessary because JavaFX still has its own application/render threads.
`GODOT_JFX_SHADER_SOURCE_CACHE=1` enables bounded CPU source-conversion and
ASCII-encoding caches; uniforms and sampler bindings are never cached with source.
`GODOT_JFX_FRAME_PULSE=1` selects a separate `awaitFrameTick(after, timeout)` JNI
clock. Exactly one `pulse_frame()` is issued after each host process iteration;
it also wakes generic capacity waiters, while capacity-only `pulse()` never
advances the frame clock. Both waits coalesce ticks and return -1 on stop/finish.
Quantum uses the Glass zero-period host timer in this mode, avoiding a second
16-ms filter over the host cadence. Regular millisecond Glass timers retain their
period semantics. The Demo launcher inherits these backend defaults and respects
explicit environment overrides instead of forcing the switches on.

`scripts/profile-vfx-gpu.ps1` combines the host command counters with the
engine `--gpu-profile` report in an isolated 8192-query fixture; instrumented
results are diagnostic, not acceptance FPS. Engine pass timings are engine-side
GPU work, not per-command or shader-attributed costs.

get_render_stats() exposes main-thread counters for host ticks, offscreen passes,
immediately fenced passes, completed presentations, applied sequence and queue
backpressure. It also reports accumulated process_us, encode_us, metadata_us,
host_commands_us and draw_sync_us, with draw_sync_calls and max_draw_sync_us.
Times are main-thread wall-clock intervals; draw_sync_us covers the synchronous
draw and offscreen render calls, and several intervals overlap. They must not be
summed as disjoint CPU/GPU costs. These are diagnostics, not GPU timings or a fixed-frame benchmark.

`GODOT_JFX_PROFILE_COMMANDS=1` additionally times texture commands, render-target
allocation, quad/mesh encoding and shader-state translation. These wall counters
are disabled by default. `profile_shader_creations` counts target shader-cache
misses during quad encoding, not driver shader compilations. The benchmark's
optional `-Trace` switch enables these counters and buffers per-frame samples.

Patch diagnostics additionally split image duplication (`profile_patch_copy_us`),
patch construction/blit, and submission wall time. Region requests, full updates
and immutable replacements have separate counts. `profile_patch_input_bytes`
counts patch payload bytes; `profile_patch_full_bytes` counts corresponding full
CPU shadow sizes, not measured GPU traffic. Backend fallback can still upload
the complete image for unsupported region formats.

`GODOT_JFX_REUSE_SHADOW` (enabled unless explicitly `0`) reuses a CPU Image only when the surface
holds its sole Image reference. Queued uploads/caches retain their references,
so they force the existing clone path. Shared pixel buffers also retain Godot's
copy-on-write protection. This avoids manufacturing a shared image immediately
before every blit. `profile_patch_reuse_count`/`profile_patch_clone_count` show
which branch runs. GPU texture revision ownership is unchanged. Texture-version,
effect, churn, pending-readback stop and GPU-motion validation pass.

By default, partial updates upload dirty rectangles synchronously on the
main/render thread in safe mode for ordinary textures not retained by encoded draws.
Vulkan uses the existing RenderingDevice staging/transfer/dependency path with
rectangle offsets; OpenGL uses glTexSubImage2D. Only uncompressed, non-mipmapped
2D RGBA8/RGBAF images qualify; storage backends retain a full-update fallback.
Referenced textures still receive a new complete immutable GPU revision. The
upload uses the packed patch directly in command order, without a queued
callback or retaining the entire CPU shadow. Subsequent patches can reuse the private
shadow instead of repeatedly copying its full pixel buffer. CPU shadows retained
by full uploads/new texture revisions still use the reference-count/COW protection
above. The internal storage API accepts a packed patch; the unused full-shadow
input branch has been removed. Vulkan/OpenGL validate the destination bounds and input
size/format, and upload the patch directly for supported textures. An unsupported
storage layout reconstructs a full update from the existing texture; the host
continues using its original full-image path for formats other than RGBA8/RGBAF.
Set `GODOT_JFX_REGION_UPLOAD=0` to compare against complete uploads. Full-image
updates and updates to referenced textures retain their existing paths.

`completed_render_sequence` exposes the existing main-thread completion watermark
used by readback/shutdown. Unlike `applied_sequence`, it advances only when the
pending target and window compositions have drained. A test can queue a render
job after its FX pulse, read the encoder's last submitted sequence, and wait for
this watermark before checking screen pixels. A host title notification alone
is not a rendering barrier, because window commands can overtake render packets.

The viewport path of JavaFXRenderTarget caches up to 64 immutable shader RIDs
by exact shader code. Materials preserve each draw's uniform/sampler state;
compatible immutable bindings may be reused through a bounded material cache. Cache-full misses remain pass-owned; no in-use shader is
evicted during a pass. Cached shaders count toward owned resources and are freed
when the render target is destroyed. get_cached_shader_count() and
get_shader_creation_count() expose this policy for the shader-cache GPU probe.

JavaFXHost.get_completed_presentations() counts completed PRESENT compositions,
excluding END_PASS intermediates. Mixed-scene tests use it to wait for an actual
JavaFX presentation before inspecting pixels; raw post-draw notification counts
do not establish that a JavaFX frame has completed.

Prism draws and clears route to the selected RT. Target uniforms and clip state
are applied per draw. Presenting an RT finishes its pass, then copies its GPU
texture into the host surface in a separate pass, keeping unfinished LCD/cache
work out of the visible framebuffer. Presentable uses a permanent sampleable
RT backbuffer; no CPU bitmap copy is involved. Explicit synchronized GPU readback is available through a separate JNI request,
not a render opcode or normal frame transport. Arbitrary feedback loops remain
unsupported; sampling requires a completed source pass.

## Floating-point image textures (18/19)

FLOAT_TEXTURE_ALLOCATE (18) has the same handle/width/height payload as command
9, but reserves 16 bytes per pixel and creates an Image::FORMAT_RGBAF texture.
FLOAT_TEXTURE_PATCH (19) has the same region header as command 10, followed by
four little-endian IEEE float32 values per pixel. Values may be signed and
outside 0..1; NaN/infinity, truncated data and mismatched image kinds are rejected.
There is no premultiplication or color conversion for these data textures.

The projected ledger counts live and retained float revisions at 16 bytes per
pixel, checks patch bounds and preserves atomic rollback on rejection. Native
patches keep the image format; sampling/disposal use existing texture handles.
Java validates the complete source region before emitting bounded row chunks.
This supports the FloatMap input of GPU DisplacementMap, including wrapped UVs.

## Live scene texture allocation (20)

SCENE_TEXTURE_ALLOCATE contains u64 handle, u32 width/height, u32 UTF-8 path byte
length, then the path bytes. Paths must start with res://, contain no NUL and
fit in 4096 bytes. Dimensions are 1..8192. The projected ledger reserves the
shared texture slot/generation and four bytes per output pixel; it rejects CPU
uploads and Prism target selection for this kind. Scene-owned resources beyond
the output texture are managed by Godot, not included in this output-byte budget.

The host validates UTF-8, loads the PackedScene and creates JavaFXSceneView on
the Godot main thread. Failure stops the command queue and marks the runtime
failed with the resource path; normal JVM completion cannot overwrite that
failure. The scene viewport's texture RID is borrowed. Shader and textured-quad
sampling retain the scene owner; disposal invalidates the logical handle but
keeps already referenced scene nodes alive until pass cleanup/clear. The RID is
never freed as an ordinary uploaded image. Resize uses command 21 below; JavaFX
input forwarding is implemented by command 22. Command 20 establishes loading,
sampling and lifetime.

## State-preserving scene resize (21)

SCENE_TEXTURE_RESIZE contains u64 new handle, u64 source handle and u32 width/
height (24 bytes). The source must be a live scene texture with no outstanding
sampling reference; the destination must be a fresh generation in an available
slot. Admission atomically consumes the source handle, replaces its output-byte
charge and creates the new handle. The host resizes the existing SubViewport and
transfers its owner, without reloading the PackedScene or resetting node state.

GodotResourceFactory ends the current GPU pass before encoding this operation,
then resumes the same target. Native consumption waits for post-draw cleanup at
that boundary. The new Prism wrapper has the new immutable physical dimensions;
the old wrapper and its aliases are invalidated without a duplicate disposal
command. Java pool allocation is conservative and may temporarily require room
for both wrappers; allocation failure leaves the original wrapper live.

## Scene-local input (22)

Payload is 40 bytes: u64 scene handle; u32 kind, flags, code, Unicode; then four
float32 values for x, y, relative x, relative y. Kinds are motion (0), mouse
button/wheel (1), key (2), touch (3), touch drag (4), focus (5). Flags contain
pressed, Shift, Control, Alt, Meta and double-click in bits 0..5. Mouse codes
are Godot button indices 1..9; key codes are JavaFX/Windows virtual keys; touch
codes are point IDs. Unicode must be a valid scalar and coordinates finite.
For wheel buttons 4..7, relative x carries the wheel factor instead of a delta.
Input admission requires a live scene texture, including generation validation.

NGGodotView queues render jobs, resolving the current texture handle after any
resize. Coordinates are normalized from JavaFX content coordinates and converted
to viewport pixels. Native construction and push_input happen on the Godot main
thread. Pending input before initial texture creation is bounded to 256 events;
overflow raises a reported RenderJob error instead of silently dropping input.
Focus loss releases GUI focus first, clears modifiers, and sends releases for
held keys/buttons/touches (mouse/touch releases are canceled). Pressed-key repeats
receive Godot echo state. These are viewport-scoped events, not a replacement for
Godot's global Input singleton semantics.

## Retained logical-window output (23–24)

WINDOW_PRESENT (23) ends a presentation and must be the final command in its
batch. Its 32-byte payload is u64 positive window ID, float32 x/y/width/height,
signed i32 z, and float32 opacity. Geometry is host-local; values must be finite,
dimensions in (0,8192], opacity in [0,1]. The selected target must be a live GPU
render target and BEGIN_PRESENT must be open. The host finishes that target's
pass before publishing it and composing all retained layers. Equal z values are
ordered by window ID. There are at most 64 retained windows.

WINDOW_REMOVE (24) contains the u64 window ID and also ends its batch. It is
allowed outside a presentation with no unfinished drawing. Removal is idempotent
and triggers composition of the remaining layers. Queue consumption pauses until
the ordered composition cleanup completes.

Published targets stay live in the resource ledger. TEXTURE_DISPOSE is rejected
while any retained window references the handle. Remove every referencing layer
or publish replacement content before disposal; this keeps retained output within
the native 1 GiB texture budget. These commands are exercised by an encoder
integration probe and standard Prism Presentable primary-window rendering.
Presentable publishes its captured Glass window ID. Resize retains the previous
target until replacement publication; disposal/Glass close remove the layer before
disposal. This is also the historical embedded-window path. Current secondary Stages
use independent native windows and opcode 26 below; popup/modal verification
and remaining physical limitations are tracked in glass-godot.md.

## Native GPU publication (26)

NATIVE_WINDOW_PRESENT uses the same 32-byte payload and terminal validation as
WINDOW_PRESENT. Its ID selects a JavaFXNativeWindow from the native host registry.
The source render target is composed at local origin into that window's GPU
surface. Native geometry and OS visibility come from the separate acknowledged
native-window command queue; publication does not move, show or create a window.
Callers must await creation acknowledgement before publishing. A frame arriving
after destruction is discarded without recreating a native window or embedded layer.

The texture ledger retains published native targets just like opcode 23 targets.
WINDOW_REMOVE releases publication and clears a surviving window's content;
WINDOW_CONFIGURE changes content opacity/visibility only for these IDs, leaving OS
geometry and visibility to native-window commands. Queue consumption waits for
composition completion. Secondary Glass/Prism Stages now use opcode 26; the primary
Stage maps to the root HWND and retains opcode 23. NativeWindowPixelsProbe exercises
the encoder directly; NativeStageProbe exercises standard Stage creation/rendering.

## Metadata lifecycle and shutdown

On Java main failure, the bridge first requests Platform.exit while queues remain
open and joins the render worker (10-second bound). It then waits up to 10 seconds
for isShutdownDrained: the main-thread completed render sequence must cover the
last admitted batch, and native-window/root-host acknowledgements must cover their
submitted commands. The render completion sequence advances only when neither
presentation nor composition is pending. Once drained, the original Throwable is
re-thrown to JNI and failure is reported. A cleanup exception is suppressed onto
that Throwable, never substituted for it. Explicit host stop/protocol failure
retain their cancellation semantics and are not equivalent to this graceful path.

Stage.showAndWait clears its in-loop state whenever enterNestedEventLoop returns
or throws, including toolkit-wide loop exit. This avoids a second loop-exit attempt
when shutdown subsequently hides still-visible Stages. FailureShutdownProbe and
FailureApplicationProbe exercise two nested windows and both failure entry paths;
test-failure-shutdown.ps1 supports -Runtime for the source-built release executable.

On normal Java main return, GodotBridge waits for the registered Quantum render
thread to finish (including its queued disposal jobs) before native code stops
JNI queue admission. Direct non-Quantum encoder probes have no registered worker.
Explicit host stop still cancels the queue and wakes waiters as specified above.
Normal JVM completion instead seals admission with FrameQueue.finish: waiters wake
and late submissions are rejected, but accepted frames remain available to the
Godot consumer. Calling stop on failure or host teardown still discards them.
This preserves final WINDOW_REMOVE/disposal commands when the last Stage closes
and implicit exit follows immediately. JVM FINISHED is not a GPU drain fence:
host-lifetime tests wait a bounded number of render frames for zero logical layers.

## Independent window metadata (25)

WINDOW_CONFIGURE has the same first 32 payload bytes as WINDOW_PRESENT followed
by u32 visibility (0 or 1), for 36 bytes total. It must end its batch and name an
already-published window. It changes rectangle, z, opacity and visibility while
retaining that window's GPU target, then recomposes the host. Hidden targets stay
live and charged to the texture budget. Metadata cannot create/resurrect a removed
window. Configuration/removal reject open presentations, unfinished draws, and
selected open offscreen passes, including passes with no draws yet.

These commands use the same ordered render queue as publication; the consumer
waits for composition completion before consuming the next batch. The command
alone is not a visibility revision/tombstone mechanism. Glass now shares a lifecycle
token with Presentable and queues metadata updates on the render thread. Publication
reads that token after callback registration: hidden/closed frames use zero opacity,
and closed publication is removed before disposal. Native queue ordering still
applies to commands admitted before the lifecycle change.

### Windows rich clipboard transport

`clipboardWriteFormats(String, byte[], byte[])` publishes optional Unicode text,
CF_HTML and RTF in one clipboard-open interval. Rich arrays include a trailing NUL,
reject interior NULs and are capped at 16 MiB each. All allocations and validation
precede EmptyClipboard; successful SetClipboardData transfers ownership to Windows.
OS publication failure can leave partial content. `clipboardReadRich(0/1)` returns
bounded NUL-terminated HTML/RTF bytes; `clipboardFormats()` exposes text/HTML/RTF
bits 1/2/4. Reads always query Windows. These calls use the existing Godot HWND and
never touch scene Nodes or RenderingServer.

`clipboardWriteFull(text, html, rtf, url, files, image, width, height,
customNames, customData)` extends the same single-interval publication to the
remaining formats. `files` publishes CF_HDROP as a UTF-16 `DROPFILES` list with
path count/length caps; `clipboardReadFiles()` returns the paths or null.
`image` publishes CF_DIB (BITMAPINFO header followed by BGRA pixels, no file
header) from an ARGB pixel array; `clipboardReadImage()` returns
`{width, height, ARGB...}` or null, and the Java side converts through
PixelReader/WritableImage. `clipboardReadUrl()` reads UniformResourceLocatorW
and falls back to the ANSI UniformResourceLocator with ACP conversion when the
Unicode variant is absent — the same fallback the OLE drag-in extractor uses.
Custom formats share the `application/x-godot-custom-*` convention with
drag/drop (`windows_custom_format.h`): each MIME suffix becomes a
`RegisterClipboardFormatW` name, data stays NUL-terminated under the 16 MiB
cap, `clipboardReadCustom(name)` returns one format's bytes and
`clipboardCustomFormats()` lists the convention names currently present.
QuantumClipboard serializes Serializable values (including Strings) before
Glass receives them, so the Glass layer unwraps a serialized String back to
its UTF-8 bytes; non-String byte payloads pass through unchanged and the
reader always sees the payload without its trailing NUL.

### Windows OLE drag/drop transport

Cross-application gestures use Windows OLE. Godot's `DropTargetWindows` keeps
its `RegisterDragDrop` ownership on every hosted HWND; the module injects a
delegate (`DisplayServerWindows::window_set_drag_delegate`) that runs inside
the existing IDropTarget callbacks instead of registering a second target.
When the entering payload has no supported format the delegate declines and
Godot's file-drop fallback still runs.

Outbound, `dragStartExternal(text, html, rtf, url, files, customNames,
customData, dragImage, dragImageOffset, effects, buttons, sourceWindow)`
snapshots the Glass drag clipboard on the FX thread. Native code
validates bounds (16 MiB text, NUL-terminated rich data, path count/length
caps) and runs `DoDragDrop` on the Godot main thread, which owns every hosted
HWND. The OLE `IDataObject` exposes CF_UNICODETEXT, HTML Format, Rich Text
Format, UniformResourceLocator(W), CF_HDROP (UTF-16 `DROPFILES`) and one
registered format per `application/x-godot-custom-*` name. The optional drag
view buffers carry the Quantum `application/x-java-drag-image` envelope
(big-endian width/height, then w*h*4 BGRA bytes) and its big-endian offset
pair; when present, the host registers a shell drag image through
`IDragSourceHelper::InitializeFromBitmap` before `DoDragDrop`, and the
IDataObject accepts the formats the helper writes back via `SetData`
(DragImageBits/DragContext, HGLOBAL only). The modal
OLE loop freezes host pulses; completion reaches Java as an input record with
kind 20 carrying the performed effect, which finishes the Glass drag session
exactly once.

Inbound, DragEnter/DragOver/DragLeave/Drop become synchronous
`GodotBridge.dragTargetCallback` upcalls (kinds 1/2/3/4) that re-dispatch to
the FX event thread with a bounded 1500 ms wait; a stalled FX loop degrades to
DROPEFFECT_NONE instead of deadlocking the host. Extracted text/URL/file lists
are published through the application-local drag clipboard; the Quantum layer
stores file lists as `String[]` paths. The upcall queries the callback thread's JVM attachment and attaches only if
needed; it detaches only the attachment it created. A shared lifetime mutex
protects the entire callback, including attachment and cleanup. Shutdown closes
that gate before DestroyJavaVM, so later callbacks cannot enter a destroyed VM.
JNI allocation failure stops marshalling, releases temporary references and
rejects the drop without invoking Java with a partial payload. Inbound extraction also enumerates registered formats inside
the `application/x-godot-custom-*` convention (bounded count/name length,
NUL-terminated data under 16 MiB) and publishes them alongside the standard
formats. Custom discovery works by enumerating the source IDataObject's
FORMATETC list: sources must implement `EnumFormatEtc` for their custom
payloads to be seen, which the standard .NET/OLE data objects and the test
endpoint do. `test-drag-drop-ole-inject.ps1` exercises this path without
physical input: the host's `simulate_external_drop` test entry loads the
module's own source DataObject and calls the inbound delegate directly, and
the probe asserts the Dragboard content, so the OLE payload formats stay
covered by a background-friendly fixture while the Robot fixture remains the
cross-process end-to-end proof. Drag preview images ride the outbound OLE
transport as described above; a preview inside the local (in-window) portion
of a gesture is not drawn, and non-Windows OLE endpoints remain unsupported.

## 四边形批次容量检查（2026-11-10）

Java 编码器负责完整绘制、缓存引用及几何淘汰的容量检查，调用端不重复预估长度。
完整未带纹理 QUADS 含命令头共 `48 + 32 × 顶点数` 字节，QUADS_REF 为 52 字节，
GEOMETRY_FREE 为 16 字节；剩余空间不足或命令数量已到 65536 时先提交当前批次。
本次修复未改变线上格式、4 MiB 批次限制或资源预算。
