# Logical windows in the single Godot host

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


**Historical implementation, superseded 2026-11-02:** the user now requires each
Stage to be an independent native OS window. That migration is now implemented
with Godot-owned native windows. The embedded Stage model below is retained as
historical diagnostics, not current Stage behavior or final acceptance evidence.
See architecture.md and glass-godot.md for the current implementation.

The `JavaFXWindowSurface` texture-layer compositor itself is still used: the
primary Stage publishes through it, and each native secondary window owns its
own compositor. Only the old mapping of secondary Stages to layers in one OS
window is superseded. Its live rendering and resource-lifetime code is retained.

The VFX Demo uses additional Stages for dialogs and loading windows. ComboBox,
ContextMenu and tooltips also require popup windows. They must be logical layers
inside the existing native host; creating another HWND would violate this runtime's
architecture. Glass-Godot now creates secondary untitled/transparent logical
windows; decorated secondary windows still reject explicitly. The basic owned
Stage path is verified below. Basic ComboBox/ContextMenu popup interaction is now
verified as well. Nested popup/grab edge cases, complete modality, window
decorations and broader focus/capture stress remain incomplete.

## Host lifetime with independent Stages

Native visibility now follows the set of visible logical windows, including the
requested visibility inside Glass callbacks before Window.isVisible is updated.
Hiding/closing the primary Stage does not hide the sole HWND while an independent
Stage remains visible. Input routing continues without a live primary; coordinates
then use the native host snapshot. New windows remain secondary layers while any
existing logical window survives, preventing accidental host resizing/replacement.
The host retains its geometry/background and other native properties. A native
close request targets the primary when it accepts input, otherwise the focused
surviving window; veto/owner/modal corner cases for this fallback remain unverified.

`test-host-lifetime.ps1` passes OpenGL and Vulkan separate-thread mode with normal
JavaFX implicit-exit enabled. It closes the main Stage, activates the independent
Stage by mouse then Space, creates another unowned Stage, and closes both survivors.
Pixel checks verify both surviving layers and the original 360x230 host dimensions;
one native window is preserved, final logical layers reach zero, and tree removal
releases all owned GPU resources. The GPU capture was inspected. Reopening a titled
Stage while only secondary layers survive still depends on decorated logical-window
support; this test uses UNDECORATED secondary Stages.

The isolated scene directory is exercised by `test-host-lifetime.ps1 -Runtime -Renderer mobile`.

This probe exposed lost final disposal commands at normal probe return. FrameQueue
now distinguishes finish (reject new submissions, wake waiters, retain accepted
commands for consumption) from stop (cancel pending commands). Normal probe return
uses finish after the Java renderer joins. Failure/explicit host stop still cancels.
Native protocol tests cover ordered draining and rejected late submission; the
encoded host-stop regression passes. A bounded post-JVM drain checks final layer
removal, rather than assuming JVM completion is a GPU fence.

## Held-input cancellation

Glass tracks pressed keys/buttons and active touches per View, with physical-key
owners and pointer/touch capture in GodotApplication. Focus transfer releases keys
on the old window. Disable/hide, detach and native focus loss cancel held input;
capture and touch ownership are cleared before release callbacks can reenter.
Pointer cancellation sends exit and out-of-bounds release, without a synthetic drag
that could change a Slider value. Touch cancellation balances the touch set and its
promoted mouse press. Key cancellation follows focus-loss notification.

Late physical key/button releases cannot activate a newly focused window. Repeated
key-down from a canceled hold is suppressed, but a fresh non-echo down starts a new
gesture even when native focus loss swallowed the old key-up.

`test-input-cancel.ps1` passes OpenGL and Vulkan separate-thread mode. A standard
Button opens a WINDOW_MODAL Stage while held by mouse, touch and Space in turn.
Each cancellation disarms without an action or drag; late pointer/touch release
and key echo are harmless. After modal close, fresh input (including reuse of the
touch ID and a key press without the old key-up) produces exactly one action.
One native window and resource teardown are checked. Source SDK, popup, modal and
Vulkan separate-thread GodotView regressions pass. This is injected modal-disable
coverage. `test-input-lifecycle.ps1` additionally passes both configurations for
six hide/close cases: a secondary Stage hides or closes while its Button is held
by mouse, touch or Space. Its Scene is reused after the late release and an owner
button restores the Stage. Each canceled control is disarmed, no action/drag is
generated, and a fresh gesture produces exactly one action. The probe checks one
native window and zero resources after teardown. Physical native focus loss,
multi-touch across windows, owner closure while held and cancellation of other
drag controls remain to be exercised.

## Modality and window levels

The existing Quantum disable counters and Godot nested event loop now have actual
Stage validation. `test-modals.ps1` passes OpenGL and Vulkan separate-thread mode:
an owned WINDOW_MODAL Stage enters showAndWait, then opens a nested WINDOW_MODAL
child. Blocked parent/outer buttons receive no actions; closing the inner window
does not enable the main window prematurely. An independent Stage remains usable
during window modality but is blocked during APPLICATION_MODAL. Both showAndWait
calls return, owner focus is restored, and input becomes usable again after close.
The nested-modal GPU capture was inspected; teardown releases owned resources.

Logical stacking now uses stable window-level order subject to ownership: owned
windows stay above their owners and inherit at least their owner's logical level.
The primary surface stays the base layer; its topmost setting affects the native
host. Secondary toFront/toBack reorder within the applicable level; bringing a
normal window forward cannot cover a floating/topmost window. toFront can also
raise an unfocusable popup without requiring a focus transfer.

`test-window-order.ps1` passes both renderer configurations across ten pixel-checked
states: normal stacking, always-on-top, front/back within levels, clearing topmost,
and raising an owner while its child stays above it. Surface size, layer ownership,
one native window and cleanup are checked; the owner/child capture was inspected.
The source SDK builds and popup regression passes. Broader modal/focus/capture and
primary-host lifetime cases still require acceptance.

## Standard popup controls

Popup placement now queries an optional Glass logical work area through Toolkit.
The default remains the monitor work area; Godot returns the sole host's screen
origin and viewport dimensions, using pending primary geometry when available.
Monitor enumeration and the public Screen API are unchanged. Both PopupWindow's
autoFix and Utils.pointRelativeTo use this area, so standard control popups can
flip to the opposite side of their anchor before clamping. Explicit autoFix=false
still permits off-host placement. Controls and their skins remain unchanged.

`test-popup-edge.ps1` passes OpenGL and Vulkan separate-thread mode. A ComboBox near
the bottom-right corner opens within the host and selects Two. An edge ContextMenu
opens a submenu to the left, with actual ListView/menu layout bounds and target
labels checked against the host. The leaf action is clicked, then plain Popup
checks verify autoFix=true repositions an off-host anchor and autoFix=false preserves
it. One native window and GPU teardown are checked; the edge-menu capture was
inspected. Source SDK, basic popup and Vulkan nested-menu regressions pass.
Godot now detects changed popup work-area geometry on its FX-thread frame callback
and notifies registered listeners through Glass/Toolkit. PopupWindow registers
only while showing with autoFix enabled and removes the listener when hidden or
autoFix is disabled. Dispatch uses an ordered snapshot and skips listeners removed
by an earlier callback, allowing reentrant hide/geometry changes. Unchanged geometry
does not notify; no monitor-list mutation or independent polling timer is introduced.

`test-popup-bounds.ps1` passes OpenGL and Vulkan separate-thread mode across eight
stable states. A shown Popup follows host shrink/move/grow through autoFix, retains
its screen coordinates with autoFix disabled, repositions when re-enabled, remains
unchanged while hidden through another move/resize, and is correctly placed on
reshow. Owner closure hides it and removes its layer. Assertions cover screen-space
content bounds, GPU pixels, layer counts, one native window and resource teardown;
the reshow capture was inspected. The source SDK and edge-popup regression pass.
This covers Stage API geometry changes for a plain Popup. Physical host dragging,
nested-menu reanchoring while moving, oversized content, RTL and mixed-DPI placement
still require coverage and any necessary fixes.

`test-nested-menu.ps1` passes OpenGL and Vulkan separate-thread mode with a standard
ContextMenu containing two nested Menu levels and a leaf MenuItem. Keyboard tests
enter both submenus, return one level with Left, reopen with Right and activate by
Enter. Pointer tests hover across both submenu levels and activate the leaf. A
third opening reaches the leaf and an outside click dismisses the entire hierarchy
without an action. Layer counts track 1/2/3/4 and return to one between openings;
exactly two actions occur, one native window remains, and teardown releases all
owned GPU resources. The nested-menu GPU capture was inspected. No additional
runtime change was needed. This covers central placement with injected events,
not host-edge placement, arbitrary nesting, physical input or OS screenshots.

Glass focus grabs now belong to a logical window. Moving focus to another eligible
window, hiding the grab owner or losing native host focus clears the grab before
notifying FOCUS_UNGRAB, avoiding recursive ungrab during popup auto-hide. Pointer
presses outside the grabbed owner subtree also break the grab; presses inside it
continue through JavaFX's existing PopupWindow event redirection.

GodotView now sends the distinct Glass menu notification on right-button release,
the context-menu key and Shift+F10. MouseEvent.popupTrigger alone does not dispatch
JavaFX CONTEXT_MENU_REQUESTED. Keyboard menu coordinates preserve the window's
screen origin and let Scene place the menu at its focus owner.

`test-popups.ps1` passes OpenGL and Vulkan separate-thread mode with unmodified
ComboBox and ContextMenu controls: selecting the second option by pointer, outside
click auto-hide, Escape dismissal, menu opening by right click/menu key/Shift+F10,
and action dispatch from each menu. Tests locate targets through control layout,
check popup layer creation/removal, preserve exactly one native window and verify
resource teardown. ComboBox and ContextMenu GPU captures were inspected. The
source SDK builds, and secondary Stage plus IME regressions pass. These checks do
not cover nested menus, monitor-edge placement, physical native focus loss, or all
grab/capture/modality interactions.

## Standard secondary Stage and input

GodotApplication maintains logical stacking, focused/hovered windows, mouse-button
capture and per-touch target routing. Pointer coordinates are converted from host
to target-local coordinates while screen coordinates remain unchanged. Key and
IME records go to the logical focus window. Primary native focus notifications
no longer override a secondary logical focus. Candidate positioning uses the
primary host origin. Geometry snapshots translate Glass screen bounds to host
coordinates, including updates when the host moves.

Secondary window operations do not resize, hide, retitle or restyle the native
HWND. Visibility, opacity and positioning update retained layers; focus raises an
eligible secondary window. Disabled windows block hit-testing from reaching lower
windows. Owner closure closes its children. Secondary minimize/maximize/fullscreen,
decorated windows and lowering the native host remain explicit unsupported operations;
nested popup grab/auto-hide, focus-loss cancellation and modal corner cases
still need implementation/acceptance.

`test-logical-windows.ps1` passes OpenGL and Vulkan separate-thread runs with two
standard Stages (the owned child uses StageStyle.UNDECORATED). It checks independent
surface size, child mouse activation, child keyboard Space activation, main-button
activation after focus switches, child movement/half opacity, hide/show and owner
close. All run in one native display-server window and teardown releases owned GPU
resources. The initial GPU capture was visually inspected. The test injects Godot
events; it is not physical input or an OS screenshot.

## Implemented GPU composition

JavaFXWindowSurface extends JavaFXRenderSurface with up to 64 named layers:

- configure_window(id, rect, z, visible, opacity) updates metadata while retaining
  previously published GPU content. Positive IDs and finite valid dimensions /
  opacity are checked before insertion.
- set_window_content(id, JavaFXRenderTarget) retains a GPU render target.
- remove_window(id) drops the logical owner; submitted draws still retain their
  own references through composition completion.
- compose_windows() draws visible targets in z order (ID breaks equal-z ties),
  using premultiplied opacity, into the single surface viewport. That viewport
  clips content outside the host. No CPU readback is used for composition.
- is_composition_pending() prevents overlapping writes to the same destination;
  get_window_count() exposes retained metadata. On exit, metadata/content refs and
  surface resources are released. The inherited resource counter covers surface
  resources; tests also check target ObjectIDs to establish retained-content life.

Changing layout, visibility or ordering does not require republishing a texture.
Composition finishes at the render boundary. Separate-thread mode orders an
explicit draw and synchronizes the render queue before releasing sampled content,
avoiding stale deferred post-draw notifications. JavaFXHost now derives from this
class and consumes WINDOW_PRESENT / WINDOW_REMOVE commands from the Java encoder.
The standard Prism Presentable now publishes the primary window through this
path, using PresentableState's captured Glass window identity. Only the primary
Glass window is currently enabled; its layer is at host-local (0,0), z=0, with
native-host alpha still handled by Glass.

## Encoder and host publication

GodotRenderCommands.presentWindow publishes the selected GPU render target with
window ID, host-local rectangle, z order and opacity. removeWindow removes that
logical layer and recomposes the remaining output. Both are terminal batch
boundaries, and the host pauses queue consumption through GPU cleanup. Published
targets remain charged in the texture ledger and cannot be disposed while any
window references them. Protocol details are in bridge-protocol.md.

The production-encoder probe (`scripts/test-window-commands.ps1`) passes OpenGL,
Vulkan, and Vulkan with `-RenderThread separate`. It publishes two overlapping
targets, updates only the lower layer, removes the upper layer, then removes and
disposes both targets. Pixel checks cover preserved content and half-opacity
composition; teardown checks zero owned resources and one native window. Captures
are `artifacts/reference/window-commands-<renderer>-<thread>-<stage>.png`; the
OpenGL overlap capture was visually inspected. The C++ protocol suite also covers
invalid geometry/identity, the 64-layer limit, transactional rejection, and shared
target retention through the last removal.

## Standard Presentable ownership and resize

Independent metadata updates are now available through encoder WINDOW_CONFIGURE
(25). It updates an existing published layer's rectangle, z, visibility and opacity
without republishing its target. The extended window-command probe passes OpenGL
and Vulkan separate-thread mode across eight pixel-checked states: initial overlap,
independent lower-layer update, hide, restore, move/resize, lower z, full opacity,
and removal. Presentation count remains three throughout metadata updates; hidden
content stays retained and charged. The moved-layer OpenGL capture was inspected.
Protocol tests reject malformed visibility, removed IDs, open presentations and
even empty open offscreen passes. Glass
visibility now emits these updates through the lifecycle bridge below;
logical-window positioning and popup input routing remain to be connected.

## Glass lifecycle synchronization

Composition snapshots now also contain host-local x/y, signed z and opacity as
one immutable value. A lifecycle token distinguishes the primary native-host
window from logical layers. Only primary Presentable allocation resizes the host
surface; secondary targets preserve its size. Metadata callbacks and publication
both consume the same composition snapshot. Primary composition is fixed at
(0,0), z=0, opacity=1 because native host geometry/alpha are owned by Glass.
Invalid/non-finite composition updates reject before mutation; closed tokens keep
their final geometry.

`test-window-composition.ps1` passes OpenGL and Vulkan separate-thread mode using
a standard primary Stage and a second production Prism Presentable with a synthetic
PresentableState. Six pixel-checked states cover alpha overlap, move, lower z,
hide, restore and close, while the host surface remains 240x160 despite the second
target being 80x60. Closure leaves zero layers and teardown zero owned resources,
with one native window. The overlap GPU capture was inspected. This exercises
the production rendering/lifecycle path; it does not instantiate a second Glass
Window and does not validate popup input or modality. The source SDK builds.

GodotWindowLifecycle gives Glass and Presentable a shared token with a volatile
immutable visible/closed snapshot. Close permanently marks that token and removes
the registry entry; queued Presentables keep the closed token. Glass changes enqueue
render jobs, which read the latest state and current published dimensions rather
than stale callback values. Hidden layers retain their targets and are configured
invisible. Show restores their visibility. Closed layers are removed before target
disposal. Resize retention uses the same lifecycle callback.

Publication registers its callback before reading the state, so changes before
registration are observed and later changes schedule an update. A prepared frame
whose token is hidden/closed is published with zero opacity to complete its GPU
pass without visibly restoring the window; a closed publication is then removed.
Already admitted frames still obey queue ordering, so state changes are asynchronous,
not an instantaneous cancellation of GPU work.

`test-window-lifecycle.ps1` passes OpenGL and Vulkan separate-thread mode: eight
hide/change-content/show cycles cover 16 stable states and 320/341 checked frames,
peak owned resources is 14, and close leaves zero layers. The test also verifies
that a retained closed token cannot become visible and cannot be looked up again.
This validates the primary Stage lifecycle, not popup focus/modality or every
possible cross-thread interleaving. The source SDK and resize regression pass.

GodotContext retains the published backbuffer independently of its Presentable.
When lockResources requests replacement after a render-size/scale change, disposal
leaves the last published target live and charged to the Prism pool. Successful
replacement publication swaps the ledger reference before disposing the old
texture. This avoids removing the layer between resize allocations. Ordinary
Presentable disposal removes its layer before texture disposal. Glass close also
queues a render-thread cleanup, covering an old retained buffer when replacement
allocation or painting never completes. Cleanup is idempotent.

`scripts/test-window-resize.ps1` passes OpenGL and Vulkan separate-thread runs:
40 changes cover six sizes, each captured active frame retains the red content
pixel and exactly one logical layer (454 and 717 samples respectively), peak owned
resources is 19, and close leaves zero layers with one native window. Tree removal
releases all owned resources. The Stage control/effect/mouse/keyboard regression
and Vulkan separate-thread GodotView regression pass with standard Presentable
using window publication. The Stage interaction GPU capture was inspected.
The OpenGL VFX Intro 35-page navigation regression passes with a fresh completed
manifest and a regenerated, visually inspected D3D comparison sheet. Random table
data and timing remain expected differences; this does not accept popup actions.

## Historical verification

The historical OpenGL/safe, mobile/safe and mobile/separate runs each passed 100 creation/composition/removal cycles. Checks cover alpha,
z ordering, hide/show, moving/resizing beyond host bounds, removal while a draw
retains the source, destruction of target ObjectIDs after completion, zero surface
resources after tree removal and exactly one native display-server window. GPU
captures are artifacts/reference/window-layers-<renderer>-<thread>.png; the GL
capture was inspected. Existing render-target
regression pass. These are compositor checks, not modal/input or OS screenshots.

## Remaining integration

Complete nested popup auto-hide/grabs and edge placement, broader modal owner/blocked-window behavior,
decorated-window interactions and focus-loss cancellation. Extend stress coverage
of queued paints, pointer/touch capture during hide/close, and owner closure.
Then exercise VFX dialogs and standard JavaFX dropdowns end-to-end.

Current compositor diagnostics use `./scripts/test-window-layers.ps1` with
`-Renderer mobile` or `-Renderer gl_compatibility`, both in safe mode. They do
not restore the old embedded-Stage model. See [TESTS.md](../TESTS.md).
