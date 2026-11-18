# Glass-Godot — windows, scheduling and input

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


Recorded test results below describe their named workload and build; they are
not an automatic rerun after every subsequent change. Consult acceptance-status.md
and review-open-items.md for the current review evidence and remaining limits.

Standard `Stage.getIcons()` supports setting, replacing and clearing icons on
the primary and independent native windows, including hide/reshow. Glass copies
byte/int pixel buffers into immutable BGRA_PRE payloads; Godot applies them on
its main thread through DisplayServer.window_set_icon. Premultiplication is
preserved because the Windows icon backend copies channels into its bitmap.
No scene texture or per-frame icon upload is introduced. Each icon is bounded
to 256x256 and each queue's pending icon payloads to 1 MiB. Standard Quantum
WindowStage already selects/scales a 32x32 source on Windows.

`test-window-icon.ps1` reads the installed HWND icon using WM_GETICON/GetIconInfo:
distinct root/child colors, updates, clear, hide/reshow, transparent corners and
half-alpha premultiplied blue. Windows uses system icon metrics for Godot's
LR_DEFAULTSIZE request; the test accounts for current DPI scaling and a two-unit
channel resampling tolerance. Protocol tests cover payload bounds, queue capacity,
ordering and rejection after close. Desktop/taskbar appearance and mixed-monitor
icon scaling are not covered by this probe. On macOS there is no per-window icon
concept — the Dock icon belongs to NSApplication — so the host reports no
installed icon by design and `test-window-icon.sh` SKIPs explicitly instead of
asserting pixels.

**Current requirement correction (2026-11-02):** each Stage must have an independent
Godot-owned native window. The embedded logical Stage implementation and single-HWND
test results below are historical and do not meet the corrected target. Standard
secondary Stages now use independent Godot windows, per-ID commands/snapshots and
GPU publication. Standard decorated Stage rendering, resize, hide/reshow and close
pass GL/Vulkan separate-thread probes. Secondary input/focus and native close
callbacks now route by window ID; overlapping-window tests cover typing, wheel,
touch, held-button cancellation and close veto. Native enabled/focusable state and
nested/window/application modality now pass native-window probes. Independent
fullscreen, Escape exit and restoration of normal/maximized mode also pass GL and
Vulkan separate-thread probes. Per-window IME routing passes composition/commit/
cancel tests; physical IME candidate UI and DPI remain to verify. See progress.md
for test scope and failure notes.

Native Stage ordering now uses main-thread HWND_TOP/HWND_BOTTOM commands for
toFront/toBack, including the primary Stage. Raising no longer substitutes a
focus request. NativeOrderProbe checks actual HWND order across seventeen phases
with two unowned Stages and a two-level owned chain, including leaf and owner hide/reshow,
then verifies complete window/resource drainage. Nonmodal ownership explicitly
sets GWLP_HWNDPARENT after HWND creation; Godot's transient flag alone only sets
the native owner for exclusive windows. This preserves modeless input semantics.
Before Godot destroys a hidden owner's HWND, its owned HWNDs are detached so
Windows cannot destroy them behind Godot's Window objects. Native owner links are
refreshed after window recreation, skipping owners without a current HWND.
Logical focus transfer now cancels held mouse/touch state as well as keys, without
waiting for a later native focus-loss record. Native input probes verify that an
owner focus request during a child press suppresses the old release and still
allows a subsequent touch action (OpenGL and Vulkan).
Topmost/unfocusable combinations and showing a child while its owner is hidden
are not covered by this probe;
historical embedded-window ordering results below do not validate those cases.

ComboBox/ContextMenu and three-level submenu regressions now use independent
native popup windows too. GL/safe and Vulkan/separate cover selection, dismissal,
keyboard navigation, cross-window hover and cleanup. Captures wait for actual
visible GPU content and have been inspected. Single-monitor screen-edge placement
now passes native popup tests: Glass visual bounds use the Godot usable desktop
rectangle, ComboBox opens upward, submenus flip left, and custom Popup autoFix
true/false respects or preserves overflow. Dynamic/multiple-monitor placement,
DPI changes and physical desktop input remain unverified. All Godot monitors are
now enumerated with primary first and their own full/usable bounds and DPI; changed
snapshots refresh Glass Screen objects and window screen associations. The probe
passes on the available single monitor. Windows platform/output scale now follows
Godot's effective DPI / 96 (or 1 with prism.allowhidpi=false). On macOS the host
reports screen DPI as UI scale × 96 for the same convention: `screen_get_dpi`
returns physical DPI there, which would break the Java-side dpi/96 scaling.
Logical screen/work
rectangles follow upstream Glass screen anchoring while platform bounds stay in
native pixels. The 200% system-scale probe verifies independent native windows,
fractional render scales, pixels, logical dimensions and local/screen mouse
coordinates; Mixed-scale screen
geometry has synthetic coverage, but physical multi-monitor/hotplug validation,
native DPI transitions and logical-size preservation during transitions remain
incomplete. Historical fixed-pixel fixture results need HiDPI revalidation.
The ordinary popup, three-level menu, screen-edge and owner-bounds fixtures have
now been revalidated at the current 200% system scale on GL/safe and Vulkan/separate.
The bounds fixture checks an independent native popup, including visible content
outside a shrunk owner, screen-space positioning, hide/reshow and owner-close
cleanup. It supersedes the old requirement to clip popup content to the owner.

Primary closure now has a native-window lifetime regression: the root HWND hides,
independent Stages retain actual OS visibility/input, later Stages remain native,
and closing the last Stage triggers implicit exit. It passed on OpenGL and Vulkan. Godot's Windows style update preserves the existing
WS_VISIBLE bit, fixing borderless windows that previously had rendered viewports
but an invisible HWND after style changes. Popup regressions check IsWindowVisible
as well as GPU contents; this still does not replace OS-screen capture acceptance.

## Historical embedded-window results

The following host-bounds and single-window results describe the earlier backend.
The current GodotApplication returns no custom popup bounds, so standard JavaFX
monitor work-area placement applies. The migrated native bounds fixtures are
described above; this section preserves the earlier embedded-window results.

Open autoFix popups now receive host geometry-change notifications on the FX thread,
with listeners removed on hide or autoFix disable. A plain Popup probe passes
GL/Vulkan separate-thread shrink/move/grow, autoFix toggling, hide/reshow and owner
closure checks, including GPU pixels and cleanup. Physical dragging, moving nested
menus and mixed-DPI behavior remain unverified.

Godot exposes an optional popup work area through Glass/Toolkit. Standard popup
autoFix and side-flipping now use the host viewport bounds; ordinary backends keep
their monitor work area and Screen enumeration is unchanged. Edge ComboBox,
left-flipped submenu and explicit autoFix true/false probes pass GL/Vulkan separate
mode. Already-open popups during host movement/resize and broader DPI cases remain.

Three-level ContextMenu keyboard and pointer navigation now passes GL and Vulkan
separate-thread probes, including left/right return/reopen, leaf activation and
outside-click hierarchy dismissal. Layer counts and resource cleanup are checked.
Host-edge popup placement remains incomplete; see logical-windows.md.

Closing the primary Stage now preserves the native host and input for independent
visible Stages. A GL/Vulkan separate-thread probe verifies surviving mouse/key
actions, another secondary Stage, original host dimensions and complete teardown
with normal implicit exit. Native visibility follows all logical windows. See
logical-windows.md for the exact tested boundary and remaining lifetime cases.

Held keys, mouse buttons and touches now have cancellation on disable/hide and
native focus loss, with key release on logical focus transfer. Late releases and
canceled key echoes are suppressed without blocking fresh presses. Modal-disable
Button tests pass GL and Vulkan separate-thread mode for mouse/touch/Space, no
accidental action/drag and successful subsequent gestures. See logical-windows.md
for details. Secondary Stage hide/close while holding mouse/touch/Space and Scene
reuse now also pass both configurations. Physical focus loss, owner closure while
held and other drag controls remain unverified.

Nested WINDOW_MODAL and APPLICATION_MODAL Stage tests now pass in GL and Vulkan
separate-thread mode, including disabled input, nested-loop return and focus
restoration. Secondary window level ordering and toBack are implemented and tested;
owned windows remain above owners. See logical-windows.md for scope and evidence.

Secondary untitled/transparent logical windows now render inside the single native
host. The owned-Stage probe passes OpenGL and Vulkan separate-thread checks for
mouse/key focus routing, movement/opacity, hide/show and owner close; see
logical-windows.md. Decorated secondary windows and secondary min/max/fullscreen
remain explicitly unsupported. Popup auto-hide/grabs, level grouping, modal corner
cases and complete cancellation during focus loss still require work.

Basic ComboBox/ContextMenu popup interaction now passes GL/Vulkan separate-thread
tests. Logical focus grabs notify ungrab on owner hide, focus changes and outside
subtree presses; right-click/menu-key/Shift+F10 now dispatch Glass menu events.
Verified paths include option selection, outside-click/Escape dismissal and menu
actions. Nested popup grabs, edge placement and full modal/capture cases remain.

## Current Glass runtime and system interfaces

The backend is selected by `-Dglass.platform=Godot`. PlatformFactory finds
GodotPlatformFactory through Glass's existing class-name convention.

Implemented and integration-tested:

- GodotEventLoop owns a non-daemon thread named JavaFX Application Thread.
  GodotApplication installs this thread as the Glass event thread before
  startup. Neither Godot main nor the probe thread executes callbacks.
- invokeLater is FIFO; invokeAndWait propagates exceptions to its caller.
  Termination rejects pending synchronous tasks so their callers do not hang.
- Nested event loops retain a stack. Upstream Glass EventLoop handles
  deferred exits of non-innermost loops; the integration test exercises this.
- GodotPulseScheduler waits for native Godot ticks on a daemon receiver,
  coalesces pending pulses and delivers timer callbacks on the event thread.
  It has no independent periodic clock driving JavaFX. If the host tick
  starves (the Godot main loop stalls, for example during a heavy GPU burst
  in the engine draw phase), the 100 ms receive timeout posts a coalesced
  starvation pulse so animations keep wall-clock progress; starvation posts
  are capped at 3 per stall so a modal-length stall can never push the
  bounded render queue against its submit retry deadline.
- GodotTimer supports periodic and per-frame start, pause, resume and stop.
  Missed periods coalesce instead of creating a catch-up backlog.
- Initial Glass Screen dimensions/DPI come from a Godot main-thread native
  snapshot, without invoking display APIs from Java threads.

GodotApplication temporarily inherits the existing HeadlessApplication for
its platform-neutral key mapping and pixel-holder implementations. It
overrides screen allocation, event handling, window/view creation, cursors
and Robot. It does not allocate or use the headless full-screen framebuffer.
Native input and cursor support are connected. The inherited character-to-key
mapping is not proof of complete keyboard-layout support; physical testing of
other layouts remains separate from the logical-key and Unicode event paths.

Primary Window/View now route bounded commands through JNI to the Godot main
thread. The primary Glass window uses the existing Godot HWND; secondary windows use
the independent native-window transport. Implemented
commands cover Unicode title, bounds, visibility, focus, resize constraints,
window mode, background, stock cursor and topmost state. Host snapshots carry
an applied-command sequence so stale dimensions cannot undo a pending resize.
Monitor dimensions and viewport dimensions are reported separately. View
resize callbacks execute on the Glass thread. Pixel uploads remain explicitly
unsupported: this bridge is not a bitmap presentation fallback.

Mouse motion, button transitions, dragging and fractional wheel input now
travel through the native bounded queue. Logical keys are translated to
Glass key symbols independently from Unicode text, including non-BMP text
and repeated press/typed delivery. The extended window probe injects events
through Input.parse_input_event and checks the real Java View callbacks;
this is not a physical keyboard/mouse or IME acceptance test.

On macOS, wheel and trackpad scrolling follow the native Mac Glass contract
instead of the Windows one. The host reports both as kind-17 scroll records
carrying MacGestureSupport-style deltas: NSEvent line deltas for wheel ticks,
and pan point deltas after the 0.1 precise-scrolling conversion for trackpad
InputEventPanGesture (which previously never reached Java at all). The Java
side delivers them as performed scroll gestures with the native 10px
multiplier, so one wheel tick scrolls 10px per line unit like other macOS
applications; the Windows lines/40px contract made it 4x that. The macOS
platform layer normalizes precise point deltas from smooth-scrolling wheel
mice to line units (ten points per line) before creating wheel events, so
classic and smooth wheels report the same factor semantics. Upstream Godot
dispatches every gesture event twice (a gesture-specific dispatch plus the
generic one in Input._parse_input_event_impl); the fork drops the duplicate
so each InputEventPanGesture reaches Java as exactly one ScrollEvent, a
contract the scroll-pan probe pins by comparing injected and received event
counts. Godot supplies
no gesture phase or momentum flags, so macOS produces SCROLL events without
SCROLL_STARTED/FINISHED and without inertia marking. Remote-desktop tools
(ToDesk/UU 远程) inject scroll as phase-less precise-delta events with their
own synthesized inertia; such streams contain micro oscillations and burst
deltas produced by the injector, which the bridge delivers verbatim (as does
native Mac Glass). Jitter observed only under remote control is therefore
an input-source artifact, not a bridge defect; AppKit apps merely mask it
with their own smooth-scroll animation and rubber-banding.

Touch press/drag/release now enters the bounded queue and Glass TouchInputSupport.
The first active touch also produces synthesized mouse events for ordinary
controls. Godot-emulated mouse events are filtered to avoid duplicate promotion.
The mixed GodotView probe passes this path and a touch Button action on GL/Vulkan;
physical touch hardware and multi-touch gesture recognition remain unverified.

The system clipboard now has immediate CF_UNICODETEXT, CF_HTML and RTF read/write/clear using
the existing Godot HWND. Every read queries Windows so external changes are
visible; the adapter does not pretend its cached Java data is the clipboard.
Native ownership transfer, bounded clipboard-lock retries, a 16 MiB per-format limit,
NUL rejection and malformed/unterminated input checks are implemented. HTML reuses
the upstream WinHTMLCodec with UTF-8 byte offsets; RTF uses upstream Windows Glass
ASCII serialization (non-ASCII RTF should use RTF escapes). All payloads are prepared
before clearing the clipboard. File-list encoding snapshots and validates each Java
String once before sizing the native block; concurrent replacement of array entries
cannot change the encoded lengths or cause a second-read null/overflow.
File lists publish as CF_HDROP (UTF-16
`DROPFILES`) and read back as `String[]` paths; images publish as CF_DIB
(BITMAPINFO + BGRA pixels, no file header) and read back through
PixelReader/WritableImage conversion; URL reads fall back to the ANSI
UniformResourceLocator with ACP conversion when the Unicode variant is absent,
mirroring the OLE drag-in extractor. Custom formats use
`RegisterClipboardFormatW` with the `application/x-godot-custom-*` MIME
convention and round-trip in both directions. The Quantum layer serializes
Serializable values (including Strings) before Glass sees them; the bridge
unwraps a serialized String back to its UTF-8 form so the wire matches direct
Glass callers, and passes other byte payloads through unchanged. OS
publication failures can
still leave a partially published set; this is not a transactional OS API.

On macOS (`macos_clipboard.mm`) the same formats use NSPasteboard: HTML/RTF
ride the `public.html`/`public.rtf` types, file lists round-trip the verbatim
`NSFilenamesPboardType` property list, and custom formats keep the
`application/x-godot-custom-*` pasteboard types. HTML offset encoding uses the
new `GodotHtmlCodec`, because the upstream WinHTMLCodec is excluded from
non-Windows builds. The macOS script uses the native pasteboard peer and the
Windows script uses a Windows Forms STA peer. Both run the two-way exchange
directly on the system clipboard and leave the final test content in place. The
probe verifies selected TextField Unicode copy/paste, empty/clear, rejected writes
preserving existing data, JavaFX-to-Godot DisplayServer text, external-to-JavaFX
paste, CF_HDROP path round-trip, CF_DIB pixel round-trip, ANSI-only URL read
fallback and `application/x-godot-custom-*` round-trip. A .NET peer
independently checks CF_HTML byte offsets/Chinese/emoji and
RTF, then publishes all three formats for JavaFX to read. Publication handshakes avoid racing OLE
flush with repeated reads. Windows clipboard transients are retried within the
same assertions: the peer re-reads a null `Clipboard.GetDataObject()`
(documented while another process holds the clipboard) and the Godot scene
re-reads `DisplayServer.clipboard_get()` for up to two seconds before failing.


IME enablement, candidate positioning, ordered preedit, character commit,
cancellation and bounded focus completion are now implemented. The TextField
probe passes on GL/Vulkan without touching clipboard state. See ime-godot.md for
the event transport and the remaining physical-input/candidate/DPI limitations.

The native clipboard custom-format enumeration distinguishes a normal end from
a Win32 enumeration failure. A failure raises `IllegalStateException` rather
than returning a partial list; the open clipboard is still closed by its scope
guard. `test-clipboard-ownership.cmd` verifies the enumeration result boundary
with mock API calls, without accessing the system clipboard. The C# test
snapshot independently rejects incomplete enumeration before any test writes.

The virtual keyboard entry points (`_requestInput`/`_releaseInput`) summon and
dismiss the Windows touch keyboard through the shell's ITipInvocation toggle
and the `IPTip_Main_Window` handle. This is a best-effort integration: COM
creation, Toggle, and close-message failures retain their HRESULT and the host
logs the first failure for each operation without terminating the JVM. A missing
keyboard window on release needs no action. `test-virtual-keyboard.ps1` checks
only exception-free Java calls and continued host ticks; it does not establish
that a keyboard appeared or closed. Component availability, keyboard visibility
and repeated Toggle behavior remain physical acceptance items. On macOS there
is no touch keyboard: the entry points report an explicit unsupported warning
(`macos_tabtip.h`) and `test-virtual-keyboard.ps1` has no macOS entry. The isolated
`test-tabtip-result.cmd` injects native failures and verifies result propagation
and COM Release without interacting with the desktop. Not implemented: native
system menus. Native file dialogs are described below. Independent popup/modal Stages and
monitor snapshots are implemented as described above; physical mixed-monitor
transitions remain unverified.
Mouse enter/exit and close requests use the same FIFO. The host temporarily
disables SceneTree auto-accept-quit, giving Glass an opportunity to veto a
close request; removal restores the previous setting. A close request does
not destroy the Glass window until application code accepts it. Focus-loss
key-state handling now cancels held keys, buttons and touches through the
window-addressed input path; the independent-window tests cover this behavior.
Application-local drag/drop now uses a dedicated GodotDragClipboard and the
standard Glass enter/over/leave/drop callbacks. It retains drag data only for
the gesture, negotiates COPY/MOVE/LINK, and pumps the FX event queue while flush
waits for completion. Remaining records from an already-polled host batch stay
available inside that loop. DRAG_DONE is issued once, before source Scene
teardown or balancing mouse release; rejection, Escape and source/target hiding
cancel the gesture. This data path does not touch the system clipboard.

This is an intermediate implementation, not complete desktop drag/drop support.
Windows OLE transfer to and from other applications works: when the pointer
leaves every hosted window mid-drag, the snapshot moves to a native
`DoDragDrop` source (text, HTML, RTF, URL and file list formats), and foreign
drags enter through the OLE drop-target delegate on each hosted HWND. The
`test-drag-drop-external.ps1` fixture drives both directions against a real
Win32 OLE endpoint with synthesized mouse input, including a named custom
format (`application/x-godot-custom-*`) carried by the OLE data object; see
TESTS.md. `Dragboard.setDragView(image, offsetX, offsetY)` rides the same
handoff: the Quantum layer publishes the view as
`application/x-java-drag-image` buffers, the bridge forwards them to the host,
and the host registers an `IDragSourceHelper` bitmap preview (built from the
BGRA payload, image-center offsets when none were given) before `DoDragDrop`
starts. The OLE `IDataObject` accepts the formats the shell writes back
through `SetData` (DragImageBits/DragContext), which the registration
requires. The shell renders that preview for the OLE portion of the gesture;
while the pointer remains inside hosted windows, the local dispatch loop
draws no preview image. The external fixture asserts the stored
`DragImageBits` (dimensions and offset) during DragEnter.
Application-local targeting currently uses the host's window
ordering/bounds; it cannot establish whether another process occludes that
location, although OLE hit testing now covers the cross-process case. The
`test-drag-drop.ps1` fixture passes seven cases on Vulkan/safe, Vulkan/separate,
OpenGL/safe and OpenGL/separate; the earlier OpenGL/separate context-switch
error 170 was fixed by marshalling native-GL vsync switches and sub-window
make-current calls onto the render thread (upstream
`display_server_windows.cpp`/`gl_manager_windows_native.cpp`). The fixture
covers internal lifecycle and data formats; see
TESTS.md for exact scope.
Unsupported entry points report
unsupported operations; they must be implemented before claiming Glass
compatibility. Standard Application controls now run through Prism-Godot;
see progress.md for current rendering and mixed-scene verification.

On macOS, cross-process drag/drop uses the Cocoa dragging protocols instead of
OLE. Inbound drags enter through a per-window drag delegate installed on
`DisplayServerMacOS` (`window_set_drag_delegate`); `GodotContentView` consults
it before the default file-drop handling and reports the dragging location in
the same Godot screen coordinates the mouse path uses. Outbound drags start an
`NSDraggingSession` whose completion arrives as the same synthetic input record
the Windows backend pushes. AppKit only tracks the physical button for sessions
started inside a real `mouseDragged` dispatch, so the host command does not
begin the session itself: it queues a one-shot drag-start handler on the window
(`window_set_drag_start_handler`), and `GodotContentView` invokes it from the
next real `mouseDragged` with the live event. A `mouseUp` arriving first
cancels the pending start (the completion still fires with effect 0), so a
stale session can never trigger on an unrelated later drag. Pasteboard
conventions match the macOS clipboard adapter with two macOS 26 adjustments:
`NSPasteboardItem` rejects type strings that are not valid UTIs, so file lists
ride as per-item `NSURL` writers (the system synthesizes the verbatim
`NSFilenamesPboardType` list on the dragging pasteboard for readers;
cross-process serialization silently drops file items whose path does not
exist on disk), and custom formats publish the UTI twin of the
`application/x-godot-custom-*` MIME names (the prefix's `/` becomes `.`,
decoded back on extraction; see `macos_custom_format.h`).
`Dragboard.setDragView` builds the session's preview image from the same BGRA
payload. The `scripts/test-drag-drop-ole-inject.sh` fixture feeds the payload
through the module's own pasteboard writer and the inbound delegate state
machine without a physical gesture; `scripts/test-drag-drop-external.sh`
covers the physical cross-process drag with a Cocoa helper (drag-out, drag-in,
Escape cancel). Custom formats of an outbound drag are registered on the
host's own windows when the drag starts, so inbound self-drags carry them;
custom-only drags arriving from other processes without a prior registration
cannot be received.

Validation:

```powershell
.\scripts\build-jfx-media.ps1
.\scripts\build-windows.ps1 -Target godot-library
.\scripts\stage-godot-library.ps1
.\scripts\test-glass-scheduler.ps1
.\scripts\test-glass-window.ps1
.\scripts\test-glass-window.ps1 -Runtime
```

The Java fixture loads the packaged engine and selects GodotApplication.
GlassSchedulerProbe validates thread identity, initial screen dimensions,
invokeAndWait exception propagation, nested loops, periodic/per-frame timers,
pause/resume, and cancellation of a definitely queued/parked synchronous
caller. It terminates Glass and waits for host shutdown. The test requires
both GLASS_SCHEDULER_PASS and M2_GLASS_SCHEDULER_PASS, not exit zero alone.
Latest result: PASS, artifacts/logs/m2-glass-scheduler.log.

GlassWindowProbe checks actual host size/position, View events, Unicode title,
stock cursor and GPU background pixels, and requires exactly one window in
Godot's display-server registry. Its image is a GPU readback, not an OS desktop
screenshot. Window checks do not establish JavaFX Stage/controls compatibility.
The `-Runtime` check runs the imported project from `artifacts/runtime-window`.
The latest probe also checks mouse boundary notifications, first-close veto,
second-close acceptance, and restoration of SceneTree's original quit policy.

The window probe exposed an upstream Windows event-pump issue: looking up an
invalid focused-window ID with mutable RBMap indexing inserted a phantom
window. The minimal core patch uses find() and treats missing focus as IME
inactive, preserving the existing event-pump behavior without mutating the map.

## ImageCursor

`GodotCursor` owns a copy of the Glass pixel payload, supporting BGRA_PRE byte
and ARGB_PRE int buffers without depending on HeadlessPixels' byte-only conversion.
Selection sends a bounded owned asset through `GodotBridge.customCursor`; no Java
thread creates an HWND/HCURSOR or calls DisplayServer. On the Godot main thread,
the pixels are reordered into the Image resource supplied to
`cursor_set_custom_image`. Premultiplied channels are preserved for Windows' native
cursor bitmap. The custom arrow slot is cleared on stock-cursor selection and host
stop, keeping at most the currently selected native image in Godot's cursor cache.

The adapter supports 1..256 pixel dimensions and hotspots inside the image, with
1 MiB maximum cursor payload queued across host commands. Cursor best-size queries
return the requested dimensions clamped to that cap. Primary and independent
secondary Stage cursor changes use the same ordered global pointer operations.

`test-image-cursor.ps1` passes GL/safe and Vulkan/separate. It uses standard
ImageCursor instances, injected pointer events and an independent child Stage,
checks 32x24/48x40 cursor switching, default reset and reuse, and queries the
installed Windows bitmap via GetIconInfo/GetDIBits for size, hotspot and half-alpha
premultiplied color. Final host removal clears the custom cursor metadata and all
owned rendering resources. This does not prove physical-pointer visibility on the
desktop, mixed-DPI scaling, or long-duration native handle stability.

The cursor adapter tracks Glass explicit visibility independently from the NONE
shape. Stock and image changes cannot override an explicit hide; selecting a new
image after NONE shows it only when visibility is allowed. The prior Godot mouse
mode is captured on first cursor use and restored on host stop. Diagnostics are
refreshed on show, while a fully transparent custom image is identified by the
actual null Windows cursor handle with Godot's mouse mode still visible.

The expanded fixture has thirteen steps, including hidden stock/image changes,
explicit show, NONE-to-image recovery, all-transparent-to-default recovery and
teardown while hidden. GL/safe and Vulkan/separate pass. The runner's `-Runtime`
option runs the fixture from an isolated project directory.

## Independent Stage churn

`scripts/test-stage-churn.ps1 -Renderer gl_compatibility -RenderThread safe
-Cycles 180 -HeapMiB 128` exercises repeated independent native Stage creation
and closure through host input. Use `-Renderer mobile -RenderThread safe`
for Vulkan. The fixture checks native window identity/count, three alternating
sizes, rendered pixels, closure, stable owned-resource and texture-memory baselines,
and final resource drain. It does not force garbage collection; Java heap, natural
GC counts and weak Stage references are recorded. JSON reports are written to
`artifacts/reference/stage-churn-<renderer>-<thread>-<cycles>-heap<MiB>.json`.

Both 180-cycle configurations pass these assertions. The initial OpenGL run's
64-byte-per-cycle growth was traced to an unreleased initial COM reference in
Godot's WinRT advanced-color event handler. Adopting that reference into ComPtr
fixes the leak: the post-fix OpenGL Stage run has only 8 bytes of static-memory
variation over cycles 20..180. Native-only Window and SubViewport controls are
available through test-native-churn.ps1, with an optional StaticRangeLimitBytes
gate after cycle 20. The Vulkan residual growth was subsequently traced to
RendererCompositorRD's map of dead screen-texture descriptor entries. Screen
blitting now uses UniformSetCacheRD's resource-invalidation cleanup. The post-fix
Vulkan native-window run passes a 1024-byte static-range limit (observed 500 bytes),
and the real Stage 180-cycle and packaged Runtime VFX window-controls regressions
pass. Passing these bounded tests does not establish full process, driver or
long-duration memory stability.

## Windows URL clipboard format (2026-11-04)

GodotSystemClipboard also maps JavaFX URI_TYPE to the registered Windows format
UniformResourceLocatorW. URL strings use NUL-terminated UTF-16, preserving Chinese
and supplementary characters. URL-only writes do not invent a plain-text format;
text/HTML/RTF/URL can also be published together. All payloads are validated and
allocated before EmptyClipboard, so a rejected URL cannot erase existing data.
Reads always query Windows, including updates made by another application.

The clipboard fixture now checks URL-only format discovery, Unicode round trips,
NUL rejection without replacement, clearing and independent Windows Forms exchange
in both directions. The 2026-11-04 access-denied snapshot attempt was historical;
the later 2026-11-05 implementation and recorded validation above supersede it,
including ANSI URL fallback, images, files and the named custom-format convention.
Those historical results are not a fresh clipboard test in this review.

## Inbound OLE timeout correction (2026-11-09)

Review correction (2026-11-09): inbound OLE callbacks now use cancellable FX
queue tasks. If the bounded native wait expires before execution, the queued
Enter/Drop is skipped and target cleanup is queued in order. Module-injected
timeout/recovery tests pass on Vulkan/OpenGL without real mouse input. Already
executing application handlers are not interrupted or rolled back; this is a
queued-request cancellation guarantee, not transactional application execution.

## Windows native file and directory dialogs (2026-11-04)

Glass delegates open, multiple-open, save and directory selection to Windows
IFileDialog on a dedicated COM STA thread. The Godot main thread resolves the
Stage's native HWND; the chooser is a system dialog, not a Godot FileDialog node.
Extension descriptions and patterns are passed separately, and the selected
filter index maps back to the original JavaFX ExtensionFilter object.

The FX thread pumps its event loop while awaiting completion, so animation and
scheduled work continue. The entire owner chain is disabled using balanced Glass
counters and restored in reverse order, preserving pre-existing modal disables.
Closing/hiding the owner cancels the request. Host shutdown closes the worker's
dialog windows and pumps synchronous Windows messages while joining the worker,
allowing native owner re-enable messages to finish without a shutdown deadlock.
Cancellation returns null to JavaFX; native failures are explicit exceptions.
Save selection returns a path and does not create the selected file.

Only one chooser may be active per host; concurrent/reentrant chooser calls fail
explicitly. This remains a compatibility limitation. The test entry point is
`scripts/test-file-dialog.ps1`; see TESTS.md for fixture setup and acceptance.

On macOS the same submit/poll/cancel contract is served by NSOpenPanel and
NSSavePanel, presented with `beginSheetModalForWindow` on the AppKit main thread
(which is the Godot main thread) so the host loop keeps running while a chooser
is open. Extension filters map to UTType content types with an accessory popup
when more than one filter exists; a filter whose patterns match no UTType
rejects everything, matching the Windows behavior of an unselectable filter.
`dialogCancel` from the FX thread is observed by a per-frame pump on the main
thread, which aborts the presented panel. The test entry point is
`scripts/test-file-dialog.sh`; because driving a real panel would need
accessibility permission and real keystrokes, the runner enables a module test
hook (`GODOT_JFX_DIALOG_HOOK=1`) that answers the same contract
deterministically. Native panel appearance, sheet positioning and physical
keyboard interaction remain unverified.

## Windows desktop Robot (2026-11-04)

GodotApplication now creates GodotRobot. Keyboard/button/wheel operations reuse
OpenJFX's source-built WinRobot input routines via WinPlatformFactory; loading
`glass.dll` for those routines does not create a second Glass event loop or
window. Coordinate conversion uses the existing GodotScreenLayout/Glass Screen
logical-to-physical mapping. GodotBridge registers three module-native methods
for cursor position/movement and GDI desktop capture. They execute OS calls on
the Java caller and never touch Godot Nodes or RenderingServer.

Capture uses a top-down 32-bit DIB, BitBlt with CAPTUREBLT and GdiFlush; DCs and
bitmaps are released on all paths. Returned desktop pixels are opaque ARGB.
Logical capture rectangles are intersected with each screen and mapped into a
single output image; monitor gaps remain transparent. `scaleToFit=true` uses
requested logical dimensions; false uses the origin monitor's scale. Capture
is capped at 16,777,216 pixels per buffer; non-finite coordinates and oversized
requests are rejected. This is an explicit screenshot path, not the UI renderer.
Mixed-DPI/negative-origin desktop transitions still require physical validation.

On macOS, GodotRobot dispatches keyboard, button and wheel operations to
OpenJFX's MacRobot through reflection (loading the source-built glass library
without creating a second Glass event loop), while cursor position, cursor
warping and desktop capture use CoreGraphics in `macos_robot.h` (`CGEvent`,
`CGWarpMouseCursorPosition`, `CGWindowListCreateImage`). The robot fixtures
have not been run on macOS; they seize the physical input devices and await
user authorization.

`test-robot.ps1` uses standard javafx.scene.robot.Robot, with no Godot input
injection. The fixture is temporarily topmost, checks desktop pixels before
input, restores the pointer and releases synthesized buttons/keys on completion.
It verifies committed A text, a button click, wheel direction, cursor coordinates,
scaled/native-size pixel capture, WritableImage reuse, 100 repeated captures,
invalid inputs and FX-thread enforcement. A generated OS screenshot at
`artifacts/reference/robot-desktop.png` is visually inspected. Vulkan/safe,
OpenGL/safe and packaged Vulkan/safe pass at scale 2. This is bounded functional
coverage, not a GDI handle-growth or all-key-layout certification.

Windows can deny foreground activation while the app's thread still has an
active window, so Stage.isFocused alone is not sufficient desktop-test evidence.
The first diagnostic runs exposed this and an IME candidate surface intercepting
clicks. The fixture commits text with Enter and dismisses candidates with Escape
before testing the button; it does not disable the user's IME or change layouts.

`test-drag-drop.ps1 -Robot -Renderer mobile` drives the same seven drag assertions
through real OS-synthesized mouse/key events. The default mode remains host
injection to test same-batch delivery deterministically. Both modes pass;
physical hardware and external OLE transfers remain distinct acceptance items.

## Cursor shape sync with the Viewport default (2026-11-05)

JavaFX cursor-shape commands set the OS cursor through DisplayServer, but the
Godot Viewport re-asserts the `Input` default cursor shape on every mouse
motion over the hosted surface (no Godot Control is hovered there), reverting
the JavaFX cursor to the arrow between commands. The host now mirrors every
cursor shape/image command into that default through the new quiet setter
`Input::set_default_cursor_shape_quiet`, which updates the fallback without
synthesizing a fake motion event into the scene. The pre-runtime shape is
saved on host attachment and restored on stop. Custom image cursors hang off
CURSOR_ARROW, so the default is pinned to ARROW while one is active. Note the
upstream enum quirk: on Windows the BDIAGSIZE glyph is the NESW diagonal and
FDIAGSIZE is NWSE (names swapped). `test-resize-cursor.ps1` (OpenGL
safe/separate) covers hover-in/hover-out shape assertions for the VFX-style
resize grip.

## Input wake-up and same-frame window commands (2026-11-05)

Input events arrive between host frame ticks. Previously they waited for the
next tick's drain, and the window commands they produced (for example
title-bar drag moves) only applied in the next frame's NOTIFICATION_PROCESS,
so a dragged window trailed the cursor by several frames. Three changes close
the gap:

- Mouse-button events now normalize the modifier mask to the post-event button
  state (a press sets its flag, a release clears it), matching the native
  wParam semantics Quantum expects; without it the press-drag-release gesture
  was created and destroyed within the press event itself. On Windows a
  motion whose mask lost the held buttons is additionally repaired from the
  tracked press/release stream, mirroring how native WM_MOUSEMOVE always
  carries wParam. macOS native motions always carry the pressed buttons from
  NSEvent, so no mask can be lost there; the repair is compiled out on macOS
  so an explicit mask-less motion still ends the press-drag-release gesture
  (re-arming it with stale held state surfaced as a spurious drag in the
  input-lifecycle probe).
- The frame queue gained an input generation (`pulse_input` at every input
  enqueue point, `awaitInputTick` JNI). A dedicated "Godot input receiver"
  daemon thread in GodotApplication wakes on new input and schedules an
  immediate `drainInput` on the FX event thread (an AtomicBoolean coalesces
  repeats; the flag resets before the drain so a mid-drain pulse queues a
  follow-up instead of being lost).
  Glass termination now clears a volatile receiver-running flag, checked
  after the bounded native wait and before queued input dispatch. The receiver
  ends when its current wait returns (at most 1000 ms, plus scheduling delay),
  even if the host stays alive without further input. Termination does not join
  on the FX thread or shorten the idle polling interval. The scheduler probe
  keeps the host alive and joins both input/frame receivers with a 2500 ms
  test deadline after Glass termination.
- Host commands gained a second application point at the RenderingServer
  `frame_pre_draw` signal (main thread in both render-thread modes), so
  commands produced in response to this frame's input move native windows
  before this frame's presentation instead of the next one.

`test-window-drag.ps1` measures the resulting window-to-cursor lag at 2.0
frames average (max 3) on all four renderer/thread combinations. That historical probe warped the physical cursor (`DRAG_CURSOR_WARPED`). The
current fixture only reads cursor position, places the window away from it and
uses Godot synthetic input; it does not move the real pointer. Historical lag
measurements do not establish the current fixture's latency or physical acceptance.

## VSync pacing fallback (2026-11-05)

Some Windows display states pace FIFO presents far below the refresh rate
(observed: a stable ~33-Hz plateau on a 60 Hz panel, reproduced by a bare
Godot window with no JavaFX on both Vulkan and OpenGL, while native D3D stays
at 60). The host performs a one-shot health check after the host reaches
RUNNING: it skips 2 s of bring-up, samples 2 s of frame intervals, and when
VSync is ENABLED on a non-fullscreen window and the average frame interval
exceeds 1.4x the refresh period, it switches to VSYNC_DISABLED plus
`Engine.max_fps` to the rounded refresh rate. An application-owned nonzero cap
disables this fallback, and a finite refresh rate of at least 55 Hz is required.
This tries CPU pacing in response to observed low cadence; it neither proves
the cause nor guarantees tear-free display. Java completion/failure or host
stop restores each setting only if it still equals the installed fallback
value, preserving later differing application settings. The transition prints
`JAVAFX_VSYNC_FALLBACK avg_frame_ms=... refresh_hz=...`; set
`GODOT_JFX_VSYNC_FALLBACK=0` to keep plain VSync. Measured: animation
benchmark 32.751 -> 58.050 compositions/s; with the knob off it stays at
32.751. See frame-benchmark.md for the evidence chain.

## DataObject ownership and query review (2026-11-10)

`QueryGetData` now checks advertised metadata without serializing file lists or
copying HGLOBAL payloads. Custom MIME prefix validation no longer allocates a
temporary string. `GetData`, format enumeration and enumerator cloning convert
STL allocation failures into `E_OUTOFMEMORY`; failed enumerator outputs are null.

A failed `SetData(..., TRUE)` leaves ownership with its caller, as required by
[the COM SetData contract](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-idataobject-setdata).
Only successful insertion transfers the medium; an unsuccessful copy-mode
insertion releases only its own copy. Unsupported indexed media are rejected.
The standalone drag-image fixture injects allocation failures and observes
release counts without moving the mouse, changing clipboard contents or starting
a drag. It does not replace cross-process or visible-preview acceptance.

## Windows OpenGL queued-window lifetime (2026-11-10)

The GL manager now serializes window-table/current-context access between the
window owner and render thread. Deferred make-current/VSync operations return
when their window was already removed, instead of inserting a default record
through map indexing. A failed context switch keeps the prior current-window
state; buffer swapping tolerates there being no current window during teardown.
The engine finishes the rendering server before destroying the display server,
so these queued manager callbacks remain within the manager's lifetime.

`test-window-immediate-close.ps1` exercises 32 immediate native Window closes
without inserting rendering fences between creation, VSync changes and close.
The prior implementation produced invalid-handle GL errors despite printing the
fixture's end marker; acceptance therefore checks errors and exit code as well
as that marker. The test requires no physical input automation.

### Clipboard allocation failure ownership (2026-11-10)

Full-format publication reserves its bounded extra-format list before acquiring
Windows memory, then owns every unpublished HGLOBAL through a scope guard.
Successful SetClipboardData transfers null the corresponding handle; exceptions
and early returns free only blocks still owned locally. File-list and ANSI URL
readers similarly guard borrowed memory locks during C++ string/vector allocation.
Allocating clipboard JNI entry points translate std::bad_alloc to Java
OutOfMemoryError after local cleanup. Publication is not transactional once
EmptyClipboard has succeeded: a later Windows publication failure can still
leave only some formats published.

The standalone `test-clipboard-ownership.cmd` verifies ownership and unlocking
under stack unwinding using private allocations, without touching the system
clipboard. It is not a full JNI out-of-memory or clipboard interoperation test.

DIB image decoding validates the signed height range before negation, including
LONG_MIN, and validates padded row storage before reading pixels. JNI image
allocation exceptions are preserved instead of replaced with a layout error.
The standalone ownership test also covers this production layout validator.

For supported 24/32-bit BI_RGB DIBs, pixel storage starts after the header and
all `biClrUsed` RGBQUAD entries, not necessarily immediately after the header.
Both the color table and remaining pixel bytes are bounds checked before reads.
See [Microsoft bitmap header types](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmap-header-types).

Clipboard and OLE CF_HDROP readers share `windows_dropfiles.h`: a byte-oriented
scanner requires a complete list terminator after the final path terminator.
UTF-16 units are read with memcpy, so odd pFiles offsets do not produce
unaligned wchar_t dereferences. Each caller keeps partial results local until
the complete list is accepted. ANSI conversion writes into final string
storage rather than a temporary wstring. Existing path-count/length limits
remain; malformed clipboard data raises an error and malformed OLE file data
is rejected as that format.

OLE DataObject SetData replacements take precedence over initial source data,
and enumeration lists each format once. A replaced medium is detached to a
local value only after the new medium is installed; ReleaseStgMedium can call
external COM code and reenter SetData, so no vector-entry reference is used
after that callback. The native drag-image fixture verifies reentrant reads
and 64 appended formats during release as well as built-in text replacement.

Custom clipboard encoding validates ByteBuffer bounds before copying into the
Java heap. Raw payloads retain the existing 16-MiB wire limit (including NUL).
Serialized String inputs must have an exact short/long-string byte length;
modified UTF-8 overhead is bounded separately before decoding, then the decoded
UTF-8 payload still passes the ordinary limit/NUL checks. Caller buffer position
and limit are preserved. Malformed serialization catches IO/class-resolution
exceptions only; VM errors such as OutOfMemoryError are not swallowed.
The low-heap clipboard-encoding probe never accesses the system clipboard.

Clipboard image publication also checks dimensions before allocating the Java
ARGB staging array. This matches `windows_clipboard.h`: each dimension is at
most 16384 and the pixel payload plus the 40-byte BITMAPINFOHEADER must fit in
64 MiB. A 4096-by-4096 image exceeds that total because of the header; rejecting
it before copying avoids an allocation that the native publisher would reject
anyway. The offline encoding probe checks this boundary without creating a
large image or opening the system clipboard. The original Glass Pixels buffer
already exists at this point; this check bounds the additional publication copy.

## Scroll-wheel observation timing (2026-11-10 review)

The synthetic wheel fixture observes ScrollPane position after event dispatch.
Previously its filter measured before the skin processed the third event, so
it reported two notches (80 pixels with three-line Windows settings) as the
three-notch result and accepted it with a loose minimum. The probe now retains
the per-event native-formula checks and compares the final displacement with
the sum of all three deltas, clamped to the available content extent, within
0.01 pixels. Vulkan/separate and OpenGL/safe both produce 120 pixels for the
current settings. On macOS the probe checks the native Mac Glass formula
instead: three notches yield 30 pixels at the fixed 10px multiplier.
No Windows wheel preference is changed by this fixture;
zero-line and other preference branches were not exercised on this machine
in this run. This is Godot synthetic input, not physical mouse-wheel acceptance.

## Drag fixture thread ownership (2026-11-10 review)

PhysicalDragProbe uses FutureTask for driver-to-FX calls: exceptions reach the
waiting driver and timeout/interruption cancels queued work. Cancellation does
not interrupt an already running FX action. Its event trace uses synchronized
publication and immutable snapshots for checks, rather than concurrent stream
iteration over an ArrayList. Shutdown interrupts and joins the driver, with
volatile completion/failure publication and synchronized failure aggregation.
The optional Robot is created on the FX thread and its pressed state is tracked
for release/destroy on close or failure.

Default synthetic mobile/separate and GL/safe runs pass the exact drag/resize
path checks after this change. At that stage the physical Robot branch was compiled but not run. A later
authorized mobile/separate Robot run passed drag and resize assertions
(`physical_drag-mobile-separate-robot.log`, both Java and Godot PASS markers).
This covers the tested 2x-DPI desktop path, not other displays or injected
failure/timeout cleanup.

### Native drop-target registration lifetime (2026-11-10)

A Windows drop target is published in WindowData only after RegisterDragDrop
succeeds. Registration failure releases the temporary COM object and leaves the
existing delegate unchanged; subsequent callers can retry. The platform delegate
setter returns an Error, so the JavaFX host reports a runtime failure instead of
retaining a handler for an unregistered window. Clearing a delegate still works
without creating a target. The final COM Release invokes the C++ destructor via
memdelete, so member-owned storage is released as well as the object allocation.
This applies to both native file-drop and JavaFX delegate registration; failure
messages retain the Windows HRESULT.

### IDataObject output contracts (2026-11-10)

The native drag source and the external test helper now copy FORMATETC fields
before clearing the target-device pointer in GetCanonicalFormatEtc. This follows
[Microsoft's device-independent implementation guidance](https://learn.microsoft.com/en-us/windows/win32/api/objidl/nf-objidl-idataobject-getcanonicalformatetc).
Null outputs fail explicitly. Unsupported advisory subscriptions clear their
connection/enumerator outputs. The shared component contract runs against both
objects; it does not establish cross-process physical drag/drop correctness.

### Drag clipboard cache ownership (2026-11-10)

The native OLE target's extraction path uses scoped ownership for incoming
STGMEDIUM, HGLOBAL locks and format enumerators. Allocation failure during the
copy or custom-format collection therefore releases acquired resources before
the target boundary rejects the drag. The boundary catches allocation/length
failures, clears the previous payload and returns DROPEFFECT_NONE without
falling through to another consumer or unwinding through the COM callback.
The standalone drag-image component fixture injects these failures without
calling Java or moving the mouse; it does not prove cross-process recovery.

GodotDragClipboard.current now resolves DND through Glass's shared Clipboard
cache on every lookup. It no longer keeps a second static instance reference:
Clipboard.remove can evict the shared entry when its last assistant closes.
This keeps external payload publication tied to the same cache as target-side
ClipboardAssistance readers. It does not touch the system clipboard.

### Lossless wheel settings (2026-11-10)

Window input V2 carries vertical lines and horizontal characters in separate
fields. The old `(lines + 8) * 1024 + chars` representation clamped horizontal
values to 1000 and could overflow signed arithmetic for large vertical values.
The new fields preserve all UINT32 bit patterns, including page-scroll -1 after
Java conversion, and retain Win Glass's 40-pixel multipliers. This changes the
internal JNI input layout; rebuild both the host and JFX SDK together.

### OLE JNI argument failure cleanup (2026-11-11)

Inbound drag callbacks stop preparing arguments as soon as JNI reports an
exception. They release every created local reference, report and clear the
exception, balance any thread attachment, and return no accepted drop effect.
They never invoke the Java callback with a partially prepared payload.
`test-dnd-drag-image.cmd` injects failures at all 23 JNI operations in a
representative two-custom-format payload and checks these rules. This is a
mock JNI regression, not an actual JVM heap-exhaustion test. Bridge shutdown uses the same mutex as callback entry. The worker publishes the
VM, global class reference and method together; it clears them only after an
admitted callback has released its references and detached. The lock spans
GetEnv through cleanup, so shutdown cannot overtake the gap before attachment.
No host/queue lock is held while Java dispatch runs; its existing wait is bounded.
The mock fixture pauses at that gap and requires the gate to remain locked,
then checks that calls after closure perform no JNI work. This proves the gate
protocol in isolation; it does not exhaust all Windows/JVM shutdown schedules.

### Custom cursor queue sequence (2026-11-11)

A custom cursor command consumes its host acknowledgement sequence only after
successful queue insertion, matching ordinary window and icon commands. A
native allocation failure leaves both queue contents and the next sequence
unchanged; a retry can use that sequence. This avoids a nonexistent command
remaining in the shutdown-drain watermark. An isolated fixture built from the
actual JNI function body (with a mock JNI environment) injects deque allocation
failure at queue sizes 0 through 255 and checks rollback and successful retry.
It does not simulate process-wide exhaustion during full application shutdown.

### Screen snapshot allocation failure (2026-11-11)

The screenInfo JNI entry copies monitor metadata while holding the host mutex.
If that native copy cannot allocate, it releases the lock and reports Java
OutOfMemoryError rather than allowing a C++ exception to cross the JNI boundary.
An isolated fixture extracted from the actual entry verifies the exception,
lock release and a successful later query. Normal monitor enumeration remains
covered by test-screens.ps1; neither check changes the desktop configuration.

### Outbound drag request allocation boundary (2026-11-11)

The entire dragStartExternal JNI request construction now catches native
allocation failure, including text/rich-text strings and file/custom/image
buffers, rather than covering only selected vector operations. The owned
request unwinds without publication and Java receives OutOfMemoryError. JNI
local references belong to the native invocation and are released when it
returns. The isolated extracted-function fixture injects failures in the
request object, text and rich-text allocation, then retries on the same runtime.
This fixture does not exhaustively inject every payload branch or actual JVM
heap exhaustion; cross-process transfers remain separate integration evidence.

### Default cursor restoration ownership (2026-11-11)

A host saves the Godot application's default cursor when connecting to JavaFX and
restores that saved value once when stopping. A diagnostic-only host that never
connected to JavaFX does not own this setting. Later destruction after EXIT_TREE
also leaves any newly chosen application cursor intact. The native-window
fixture checks the unbound-host case, and the image-cursor fixture checks a new
application cursor between normal exit and final host destruction; both use
synthetic viewport input, without moving the physical pointer.

On Windows, an owned Stage retains its HWND owner when its always-on-top
level changes. Sending a topmost Stage to the back lowers it within the
topmost group. Hiding an owner detaches its immediate owned HWNDs before
Windows destroys the handle. The window-order and failure-shutdown probes
cover these transitions.
