# Glass-Godot — windows, scheduling and input

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


Recorded test results below describe their named workload and build; they are
not an automatic rerun after every subsequent change. See [acceptance status](acceptance-status.md) for current limits and the
[archived review](../agentdir/docs/review-open-items.md) for the original evidence.

On Linux, Glass exchanges MIME offers on the current seat. Multiple writes in an FX dispatch coalesce into one selection, and hiding a window flushes its pending publication. The file list preserves local absolute paths, including `file://localhost/` entries, in offer order. Remote hosts, malformed URIs and non-file entries are skipped. An HTTP-only offer exposes a URL and has no file-list flavor. The memory encoding test covers these conversions. See the [Linux clipboard tests](../TESTS.md).

Standard `Stage.getIcons()` supports setting, replacing and clearing icons on
the primary and independent native windows, including hide/reshow. Glass copies
byte/int pixel buffers into immutable BGRA_PRE payloads; Godot applies them on
its main thread through DisplayServer.window_set_icon. Premultiplication is
preserved because the Windows icon backend copies channels into its bitmap.
No scene texture or per-frame icon upload is introduced. Each icon is bounded
to 256x256 and each queue's pending icon payloads to 1 MiB. Standard Quantum
WindowStage prepares a 32×32 icon on Windows and a 128×128 icon on Linux. The Linux fixture reads the Wayland icon buffer for seven update steps on the root and secondary windows, including a transparent corner, half-alpha blue, clearing and hide/reshow.

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
cancel tests; physical IME candidate UI and DPI remain to verify. See the [implementation history](../agentdir/docs/progress.md)
for test scope and failure notes.

On macOS, AppKit keeps owned Stages together. To raise a child within that
group, the host reattaches it above its owner. To lower it, the host brings
its same-level siblings forward in their existing order. The host observes
the visible window numbers in Window Server order to check the result.

On Windows, native Stage ordering uses main-thread HWND_TOP/HWND_BOTTOM commands for
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
Godot's effective DPI / 96 (or 1 with prism.allowhidpi=false). On macOS and Linux/Wayland the host
reports Godot's desktop UI scale × 96. The physical monitor DPI can differ
from that scale. When a monitor scales below 100%, an unconstrained Stage
axis keeps the Glass unlimited-size sentinel during conversion to pixels.
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

Windows and macOS use the screen point recorded with each mouse or drag event for hit testing and for conversion to the receiving Glass window's local coordinates. This also covers input queued while a Stage moves. Wayland uses the receiving surface and its local coordinates.


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
and repeated Toggle behavior remain physical acceptance items. On macOS and
Linux the host reports an explicit unsupported warning for each operation.
The Linux warning includes the active Godot display server (Wayland).
`test-tabtip-result.sh` checks their return values in isolation.
`test-virtual-keyboard.sh --compile-only` compiles the Java probe, and
`--robot` checks the host warnings and subsequent ticks. The isolated
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
see the [implementation history](../agentdir/docs/progress.md) for the rendering and mixed-scene verification runs.

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
.\scripts\build-windows.ps1 -Target jfx
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
The scheduler probe passed. New runs write `agentdir/logs/m2-glass-scheduler.log`.

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

Glass cursor changes preserve Godot's captured mouse mode while a scene is using relative input. The scene releases capture on exit from first-person navigation.

## Linux Wayland windows

A window-mode command is acknowledged when the host sends it. The compositor reports the new toplevel state later in a configure event. Glass keeps the current mode across intervening snapshots and queues the latest requested transition, so maximizing a Stage and restoring it produce distinct JavaFX notifications.

### Screen association on native Wayland

In the current Godot backend, screen enumeration reads the advertised outputs.
The primary-screen and current-window-screen queries both return index zero.
The Wayland thread records which outputs a surface enters and leaves, but the
current-window-screen query does not use that information. The reported work
area is the full output rectangle. Glass selects a screen from window bounds
and refreshes its screen object when monitor settings change.

On the isolated Weston output, the OpenGL screen fixture verified one
3120×2080 output at scale 2. That test cannot establish which monitor follows
a window moved across outputs with different scale factors. In this release
the Vulkan fixture timed out at its first screen check on the same desktop.

### Window stacking and focus on WSL2

On Linux Wayland, bringing a Stage to the front goes through the Godot
foreground request and the compositor's xdg-activation protocol. WSLg 1.0.73
on the test machine does not advertise xdg-activation. Godot logs that
limitation during startup. Closing an owned Stage can trigger this request
as JavaFX returns focus to its owner. When the focused owned window closes,
Glass first selects its visible, input-enabled owner before considering
unrelated Stages. The compositor determines native keyboard focus. Explicit lowering and inspection of
global stacking remain unsupported by this Wayland backend.

Wayland does support a compositor-driven window move or resize initiated by a pointer gesture. The application gives xdg-shell the seat and input serial, and the compositor controls placement during that gesture. From a primary-button press handler, a custom title bar can call `GodotRuntime.startWindowMove(stage)` on the FX thread. A true result means Glass queued the request. On the host thread, Godot checks that the Wayland pointer grab still belongs to that window and passes its press serial to the compositor. The same path works for the main Stage and an owned Stage. The physical JavaFX fixture instead issues `Stage.setX` and `setY` during drag events and checks an absolute screen position. Standard xdg-shell exposes no setter for that position. The two Robot failures refer specifically to this contract. [xdg-shell requests](../godot/thirdparty/wayland-protocols/stable/xdg-shell/xdg-shell.xml)

The host tracks a minimize request separately from the configured toplevel
mode. An inactive configure can arrive when the user selects another window.
The host clears the request when this surface gains activation or receives
keyboard focus. This allows desktop-initiated restoration to report the
configured windowed, maximized or fullscreen mode. Private Weston reproduced
the earlier false windowed report on an inactive configure and verified
desktop restoration of the ordinary VFX Stage on both GPU drivers.
The source editor also restored previously maximized and fullscreen children
on Vulkan and OpenGL. Each regained its original mode, 3120×2080 geometry,
keyboard focus and green reference pixel. The probe checked the focused,
presented child before requesting minimization. In an earlier OpenGL trial
that sent minimize during the first fullscreen transition, Weston immediately
returned the seat to the child and the probe never observed a stable minimized
interval. The traces are in `agentdir/artifacts/wayland-shell-restore-P8ZWu1G3/`.

On private labwc 0.9.3, the source-built release with engine `ace7814e1e52…` ran the same native Stage fixture with Vulkan and OpenGL. A read-only taskbar client observed the owner and child enter the minimized state. After JavaFX requested restoration, the owner still reported minimized at step 12 and the fixture timed out on both drivers. In separate runs the taskbar client requested `unset_minimized` for those two windows over version 3 of the optional wlroots foreign toplevel management protocol. The compositor confirmed restoration of each handle, and the unchanged fixture passed its remaining geometry, pixel and shutdown checks on both drivers. The controller identifies the two test windows by their fixture titles. Its results are recorded separately from application-only acceptance in `wayland-toolkit-publication-QI3DyI7e/stage-restore/verified.json` under the LCD publication archive. The WSLg registry previously sampled on this machine exposed neither this taskbar interface nor xdg-activation. [wlroots taskbar protocol](https://raw.githubusercontent.com/swaywm/wlr-protocols/master/unstable/wlr-foreign-toplevel-management-unstable-v1.xml)

WSLg 1.0.73 advertises `weston_rdprail_shell` version 1. The protocol has one request, `set_focus_proxy`. Weston restricts binding to its own shell client and uses the proxy to represent keyboard focus on the Windows side. An ordinary JavaFX application therefore cannot use this interface to activate an owner after a dialog closes, reposition a Stage or restore a minimized window. The protocol and binding check below match the Weston revision in this machine's `/mnt/wslg/versions.txt`. [WSLg protocol](https://github.com/microsoft/weston-mirror/blob/2318fecaeac1f1a2d5a7a042c34d931c71dae04c/protocol/weston-rdprail-shell.xml) and [Weston binding check](https://github.com/microsoft/weston-mirror/blob/2318fecaeac1f1a2d5a7a042c34d931c71dae04c/rdprail-shell/shell.c#L4267-L4286).

Two traces isolated the application-modal case on private Weston. With the
fixture's host-injected clicks, the independent Stage still held native
keyboard focus before the application-modal dialog opened. When the dialog
closed, JavaFX saw neither Stage focused at `showAndWait` return. By the
900 ms sample Weston and JavaFX had returned focus to the independent Stage.
In the control run, the virtual seat clicked the visible owner's background
before the dialog opened. JavaFX still reported the owner unfocused at return,
then reported it focused at the 16 ms sample and through 900 ms. Both drivers
reproduced the distinction. The native seat events, JavaFX properties and
child images are in `agentdir/artifacts/wayland-release-nOfa55Xe/modal-trace/`
and `modal-seat/`, in the logs ending in `-verified.log`.

An independent GTK 3.24.52 client reproduced the timing on the same two private Wayland compositors. The client waited for actual focus on the selected starting window, opened a transient modal dialog, and hid it after GTK reported it active. In all eight cases the owner was still inactive on return from `gtk_dialog_run`. The Wayland keyboard-enter trace confirmed the final recipient. With the owner initially active, both compositors restored it by the 16 ms observation. With the independent window initially active, Weston restored the independent window and labwc restored the owner. An explicit `gtk_window_present(owner)` immediately after dialog destruction produced the same final recipient as ordinary close in each of these runs. This comparison covers a programmatic hide in GTK. JavaFX's immediate-return assertion still fails on `a312dd9c27c1…` in both Weston and labwc. The native probe, all eight traces and the observation table are in `agentdir/artifacts/wayland-shared-shaders-DYodM9AZ/gtk-modal-focus-VaFJb2Xo/`.

## Drag and drop on Linux Wayland

Wayland stages use the compositor to hand a native drag between their independent surfaces. A private `application/x-*` MIME can accompany text, HTML, RTF, URI and file-list entries. The original drag clipboard retains the Java value when another Stage in the same JVM receives the drop. An independent native client can exchange opaque data under the original MIME name. The existing `application/x-godot-custom-*` text convention is preserved. [MIME names, byte framing and limits](bridge-call-inventory.md)

The private labwc cross-Stage Robot fixture verifies COPY and LINK within the source Stage, MOVE into its owned Stage, refusal, Escape before native handoff, and closing either Stage during a gesture. During the MOVE to the owned Stage, the Wayland trace records the private MIME, the target's acceptance of MOVE, and the compositor's completion. The desktop target is taken from the test compositor's configured placement. Moving a few pixels inside that target after native handoff gives the compositor a pointer motion during its drag grab. The seven scenarios passed on each B390 driver. A separate GTK peer verified both directions of a four-byte private payload with embedded and trailing zero bytes. External Escape cancellation on labwc remains a separate failure. The traces, screenshots and per-case logs are under `agentdir/artifacts/wayland-cross-stage-tn1HHwAW/`.

The isolated labwc 0.9.3 compositor used Debian wlroots 0.19.2-1. Its `wlr_seat_start_drag` installs a keyboard grab. The grab's key handler in `types/data_device/wlr_drag.c` ignores keys, including Escape. The pointer grab completes an accepted drop on button release. This accounts for the recorded Escape injection, missing source key event and subsequent COPY. The Debian patch for this version only changes layer-shell. The matching source archives and the extracted drag implementation are alongside the test logs. [wlroots 0.19.2-1 source](https://snapshot.debian.org/package/wlroots/0.19.2-1/)

On the same WSL2 machine, isolated niri revision `02ee0585` delivered the external Escape cancellation. With Vulkan/mobile and OpenGL/gl_compatibility, the regular and runtime fixtures each recorded COPY on the first drop, the four opaque bytes on the inbound drop, and a null transfer mode after Escape. The GTK target recorded one drop. Its independent capture showed the 8×6 translucent preview and all four cursor marks. niri composites the pointer and drag icon together, so the measurement cursor leaves the center clear. Focus follows the pointer in this fixture to let GTK acquire keyboard focus before its drag-initiating pointer press. Results and GTK peer logs are in `agentdir/artifacts/wayland-niri-WMYYUVqs/canonical/results/`. [Test command](../TESTS.md#linux-原生-wayland-窗口) · [Tested niri source](https://github.com/niri-wm/niri/tree/02ee0585b9da359cb30aa2a13a6023a6e471cc23)

The host starts an outgoing drag with the Godot surface that received the first pointer press and that press's seat serial. The offer advertises COPY and MOVE as allowed by the Dragboard. Wayland has no LINK action. The source sends MIME bytes over compositor-provided pipes. Dropping back on a hosted surface uses its surface-local coordinates. The source reports the action on `wl_data_source.dnd_finished` and reports no action on cancellation. A compositor keyboard-focus change during the grab leaves the drag active. Hiding or destroying the source peer or stopping the host releases the data source and its shared-memory icon.

On isolated Weston 14, a virtual seat dragged from the packaged Glass runtime to an independent GTK Wayland process. GTK received the Unicode payload, the compositor confirmed COPY and JavaFX reported COPY. A separate gesture re-entered the JavaFX surface and completed one drop. Releasing over a target with no matching MIME type produced a compositor cancellation and a null JavaFX transfer mode. All three cases passed on Vulkan and OpenGL. A 12×10 drag view with a (5,3) hotspot occupied 24×20 output pixels with its top-left corner 10 pixels left and 6 pixels above the pointer at scale 2. The gestures used the isolated compositor's virtual input. Pressing Escape over the accepting GTK target in a separate run did not cancel the operation on this Weston setup. On button release GTK received the data. Logs and crops are in `agentdir/artifacts/wayland-drag-source-9QinZ5Mn/`.

An independent GTK Wayland target also read all five advertised representations
from one JavaFX drag in the release-package test. It verified the UTF-8 plain
text, HTML, RTF, URI list (HTTPS and a percent-encoded Unicode filename), and
custom MIME bytes. The GTK receiver and JavaFX source agreed on COPY and MOVE
in all four driver/action combinations. The target checks, protocol traces and
drag-image crops are in `agentdir/artifacts/wayland-release-nOfa55Xe/rich/`.

## Keyboard focus at Wayland input delivery

The Wayland seat can transfer keyboard focus to a Stage between two Glass
frame callbacks. A key delivered during that interval previously reached
the text-field listener while both JavaFX Stages still reported unfocused.
A capture at the assertion showed the native child already had focus. A
second attempt to read the native snapshot on the FX thread still failed
one Vulkan run out of eight as the host publishes that snapshot per frame.

Godot now samples the source window's native focus when queuing a key press.
Glass uses that observation before dispatching the key to its Java listeners.
The rebuilt runtime passed ten independent private labwc sessions per driver
on the B390. The original fixture checks root/child focus, key text, pointer
and touch routing, canceled presses and close handling. Per-run results are
in `agentdir/artifacts/wayland-key-focus-K1V6MLTx/input-summary.csv`.

## Showing an owner and child Stage together on Wayland

An application can call `owner.show()` and `child.show()` in the same JavaFX event handler. The startup screen can delay the owner's first image while the child is ready to draw. If the compositor receives `xdg_toplevel.set_parent` before the owner is mapped, xdg-shell treats the parent as null. The Wayland backend keeps the requested relationship and sends it once the owner enters an output or receives its first frame callback. A JavaFX child whose owner is waiting for its first image also waits to present its own first buffer. Hiding or destroying a waiting child removes its pending show request. [xdg_toplevel.set_parent](../godot/thirdparty/wayland-protocols/stable/xdg-shell/xdg-shell.xml)

The isolated labwc Robot fixture checks the child at the overlapping pixels on first display, after clicking the exposed owner, and after hiding and reopening the child. It also checks which Stage received the clicks. [Linux test commands](../TESTS.md)

For three nested, non-modal Stages, labwc 0.9.3 initially displays the grandchild above the middle Stage. Clicking the exposed middle Stage raises it over the grandchild. This happened on both Godot drivers and in an independent GTK 3 Wayland application with the same parent chain and layout. The compositor raises the root and its children, then raises the selected non-root view again. Hiding the three Stages and showing them together restored the original order in two consecutive cycles on each driver. [labwc 0.9.3 window raising](https://github.com/labwc/labwc/blob/0.9.3/src/view.c#L2103-L2115)

## Owned modal Stages on Wayland

Glass marks an owned modal Stage when it creates its native window. For
each mapped toplevel, the Wayland backend attaches an `xdg_dialog_v1` role
and sends its modal hint when the compositor offers `xdg_wm_dialog_v1`.
The role is destroyed when the hint is cleared or the native window is
destroyed. Reopening the Stage applies the hint to the new native surface.
JavaFX continues to enforce window- and application-modal input filtering.
The Wayland hint describes modality relative to the toplevel's parent.
[Wayland dialog protocol](../godot/thirdparty/wayland-protocols/staging/xdg-dialog/xdg-dialog-v1.xml)

On labwc 0.9.3, Vulkan and OpenGL traces each showed three native dialog
roles for the nested and application-modal rounds. The owner still lacked
JavaFX focus when the second `showAndWait` returned. In the source-editor
window test, both renderers attached the role to each of the child's two
toplevels, set it modal, and released both roles. Logs are under
`agentdir/artifacts/wayland-family-CCWBZZMD/check-labwc/`.

Both labwc traces show Godot requesting activation of the owner when the
application-modal Stage closes. After the dialog surface was destroyed,
the next `wl_keyboard.enter` targeted the owner in the Vulkan trace and
the independent Stage in the OpenGL trace. The Java assertion runs as
`showAndWait` returns. Its exception reaches the host log during shutdown,
so the order of those log lines cannot establish the seat focus at the
instant of the assertion.

A subsequent paired trace sampled the host and Glass states on the FX thread just before and after closing the application-modal Stage. At return on both B390 drivers the main Stage was showing and enabled, its native focus bit was set and it was Glass's logical focus target. Glass still had its application focus flag cleared from the previous pulse, when that Stage was disabled. This explains the failed Java assertion on these runs. The observations are in `restart-suite-n8jhXQQK/modal-focus-5yq5ePmf/{vulkan,opengl}/focus.log` in the release archive.

Glass now tracks application focus on Wayland separately from whether an individual Stage can accept JavaFX input. A visible but temporarily disabled owner can retain native seat focus during modal activation. Glass continues to filter input to disabled Stages. Using the updated Glass classes, the original modal assertions passed on both drivers in three consecutive runs each on Weston and labwc (12 passes). The input-cancel and native Stage input cases also passed on both drivers on labwc. Results are under `restart-suite-n8jhXQQK/modal-host-focus-uvH8F5AU/{1,2,3}-{labwc,weston}/results/` in the same release archive.

On the same desktop, a separate client observed the native Stage rapid
minimize/restore case. Minimizing the owned Stage minimized the entire
parent-child family and left neither window focused. wlroots rejected
the subsequent activation token because its source had lost focus. Both
unassisted runs timed out at step 12. In two separate runs, a single
Alt+Tab on the private seat restored the family and returned focus to the
child. Both original Java and Godot probes then passed through step 14,
including bounds, presented pixels and cleanup. The observer, client and
compositor logs are in `agentdir/artifacts/wayland-family-CCWBZZMD/`.
[labwc 0.9.3 window minimization](https://github.com/labwc/labwc/blob/0.9.3/src/view.c#L730-L753)

## Robot on Linux Wayland

Glass uses a Wayland connection owned by the FX event thread. Robot sends keys via an XKB virtual keyboard and buttons, motion and wheel events via a virtual pointer. Screen samples come from the compositor output through image-copy capture. The compositor reports the observed cursor hotspot in a separate event, which may arrive after it acknowledges the move. Querying a pointer outside every captured output or with no reported hotspot raises an explicit exception. Validation used one unrotated output at scale 1. Mixed-DPI and rotated output layouts remain unverified.

The labwc fixtures can reproduce the physical positions assumed by the tests using `--test-layout` on a private desktop. The ordinary labwc placement policy produced a black desktop pixel at the first expected blue sample. Placing the undecorated fixture at (80,80) allowed the unchanged sample, keyboard, wheel and repeated capture assertions to run. The local WSLg registry contains none of the required virtual input or image-copy capture managers. Its registry is in `agentdir/artifacts/wayland-egl-check-ed9P5d30/wslg-registry.log`. [Test commands](../TESTS.md#linux-原生-wayland-窗口)

On the B390 release `64f8f54d265b…`, one fresh labwc desktop did not report an initial pointer position before the Vulkan/runtime Robot tried to save it. The same fixture then passed in a fresh desktop with a real virtual-pointer motion before launch, and also in a fresh desktop without that motion. In both runs it verified the click, wheel, physical pixel and repeated captures. This leaves an intermittent initial-position failure. Results are under `agentdir/artifacts/wayland-niri-WMYYUVqs/pointer-init/`.

A separate native Wayland probe ran on a private labwc 0.9.3 desktop.
It moved a virtual pointer on its 1280×720 output and read back (320,180)
and (960,360) through the compositor's image-copy cursor session. A
virtual keyboard delivered F8 to an independent GTK client. Captures from
the compositor confirmed that three points changed from green to magenta
after the client handled the key. This establishes input, pointer
observation and output capture on this compositor. The Glass backend now uses those protocols from the public JavaFX Robot. The
registry, native client, transcripts and PNGs are under
`agentdir/artifacts/system-labwc-L7cshYQJ/previous-diagnostics/`.

Before the Glass backend was added, the full labwc group passed the two child-Stage IME cases and two virtual-keyboard contract cases. The other eighteen reported missing Wayland Robot support. Historical logs are under `agentdir/artifacts/wayland-activation-aPQfvnC7/robot/`.

Godot now forwards the coordinates from `wl_pointer.enter` to the new window even when the compositor sends no motion in the same frame. Previously the JavaFX button could remain unhighlighted for the entire first stationary hold. After the change, Vulkan recorded 18 missing-green frames out of 1264 across all holds and OpenGL recorded 20 out of 1269. Both original plain-button and Fusion pixel thresholds passed. The four Stage input and popup reruns also passed. Results are under `agentdir/artifacts/wayland-robot-2RIjHyHr/{hover,enter-hover,input-checks}/`.

The GTK drag helpers can now open a Wayland display and report their display
name. The labwc test layout can place both GTK peers at their declared coordinates. During drag motion, the GTK target reads the output around the pointer with grim and measures the visible drag image against the underlying color. The observer records the measured size and RGB byte count. Wayland delivers
pointer positions relative to the focused surface. Desktops with the XDG
RemoteDesktop and ScreenCast portals can grant input and capture sessions.
In the 22-case labwc matrix, the external drag fixture delivered COPY in both directions and the GTK peer measured the 8×6 image on both drivers in default and runtime modes. Escape cancellation still failed in each case. In the isolated Vulkan trace, the virtual keyboard submitted the Escape press and release during the active drag. The source received neither a key press nor cancellation before the compositor reported `dnd_drop_performed` and `dnd_finished`. The four fixture runs are under `agentdir/artifacts/wayland-robot-2RIjHyHr/drag-gesture/` and the protocol excerpt is in `escape-order.txt` in its parent directory. [labwc 0.9.3 drag handling](https://github.com/labwc/labwc/blob/0.9.3/src/dnd.c).

The OpenJFX GTK backend includes portal helpers. The Glass-Godot Robot has
yet to integrate them..
The private session bus listed `org.freedesktop.portal.Desktop` in neither
`ListNames` nor `ListActivatableNames` during this run.
[Wayland pointer protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_pointer)
and [RemoteDesktop portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html).

## ImageCursor

On Wayland the probe reads the ARGB8888 pixels from the shared-memory buffer committed to the current seat's cursor surface. It checks the buffer identity while a window has pointer focus. Physical cursor presentation still requires observation on the target desktop. Glass converts its premultiplied channels to straight RGB before the Wayland backend applies alpha. Replacing the image closes the temporary shared-memory descriptor and retains the previous cursor if allocation fails. Both drivers passed the default and runtime image-cursor cases with the rebuilt library. The four per-case logs are in `wayland-egl-check-ed9P5d30/extra/`.

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

`scripts/test-stage-churn.ps1 -Driver opengl -RenderThread safe
-Cycles 180 -HeapMiB 128` exercises repeated independent native Stage creation
and closure through host input. Use `-Driver d3d12 -RenderThread safe`
for Vulkan. The fixture checks native window identity/count, three alternating
sizes, rendered pixels, closure, stable owned-resource and texture-memory baselines,
and final resource drain. It does not force garbage collection; Java heap, natural
GC counts and weak Stage references are recorded. JSON reports are written to
`artifacts/reference/stage-churn-<driver>-<thread>-<cycles>-heap<MiB>.json`.

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

On Linux the native GTK file chooser uses the active Godot display backend.
For a Wayland owner, Godot supplies its xdg-foreign export and GTK imports
the handle as the dialog's transient parent. An unavailable handle causes
the request to report an error. An unowned chooser can open directly on
Wayland. The six Linux file-dialog matrix cases use the test hook and cover
the Java return values, cancellation and shutdown. They do not exercise GTK
window mapping or establish that a compositor supports xdg-foreign.
The separate native GTK probe on private Weston mapped a real unowned
chooser, canceled it, and verified the empty result. It also exercised the
missing-parent-handle error. See `agentdir/artifacts/wayland-egl-check-ed9P5d30/real-chooser.log`.

On labwc 0.9.3 an ordinary JavaFX application using the packaged Linux
runtime opened a real GTK chooser for its primary Stage, then for a secondary
Stage. In each of the four driver/owner combinations GTK imported the
handle over xdg-foreign v2 and the compositor reported the intended parent
and active chooser. Alt+F4 on the private seat closed each chooser and Java
received a null selection while its owner remained visible. An earlier
Escape-key attempt left the primary chooser open on both drivers. The two
runs are archived separately in `wayland-family-CCWBZZMD/chooser-close/`
and `wayland-family-CCWBZZMD/chooser/` under `agentdir/artifacts/`.

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

`test-drag-drop.ps1 -Robot -Driver d3d12` drives the same seven drag assertions
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

The physical drag and resize checks cover the tested 2× DPI desktop. Other displays and injected cleanup failures remain unverified. [Historical verification](../agentdir/docs/glass-godot.md).

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


### Resizing the VFX grip after an interactive Wayland move

In the isolated labwc session, the first size change of a moved VFX window changed its Glass-reported origin from (320, 133) to (0, 0). The physical top-left corner stayed at (230, 190). When the resize grip subtracted two screen positions, this origin change turned a requested 180×100 enlargement into a 140×33 reduction. The primary window went from 1280×800 to 1140×767 on both B390 drivers. Native Wayland pointer motion and JavaFX scene coordinates agreed throughout the gesture.

VFX uses scene-coordinate deltas for its bottom-right resize grip, drag scrolling, slider thumbs and movable shapes on all platforms. Title-bar movement retains screen-coordinate deltas when the compositor move is unavailable. The public `DragHandler` still measures screen displacement. In the source-built JAR an outward drag enlarged the primary window to 1460×900 and a subsequent inward drag reduced it to 1230×760 on both drivers, at 1× and 2×. Resizing an owned VStage preserved the position and size of its owner. A separate JavaFX Robot fixture measured all four window edges in the actual compositor output. See [TESTS.md](../TESTS.md) for the executable fixture. The external compositor captures are under `agentdir/artifacts/wayland-interaction-hQ6x4vwN/wayland-lcd-publication-z3rrr44Z/vfx-geometry-release-MrQkS9GG/compositor/`.
