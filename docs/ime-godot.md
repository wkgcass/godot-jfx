# Glass-Godot IME

> Current configuration (2026-11-13): JavaFX hosting supports only Viewport +
> safe. Custom RD-direct and separate-thread host support have been removed.
> Dated RD/separate measurements below are historical evidence, not runnable
> configurations or acceptance of the current build. See [tests](../TESTS.md)
> for current commands.


Glass-Godot enables the Windows input method context of the corresponding Stage's
existing Godot HWND when a JavaFX text control accepts input method events. IME
does not create an extra native text control. Root host commands and native-window
properties 16/17/18 enable the context, position the candidate UI and finish
composition respectively. Candidate positions come from JavaFX InputMethodRequests
in screen coordinates and are converted to that window's local coordinates. The
rendering scale is not restricted to one: render-scale fixtures and VFX captures
include scale 2. Physical IME candidate placement across DPI/monitor transitions
remains unverified.

Godot NOTIFICATION_OS_IME_UPDATE reads DisplayServer preedit text/caret on the
main thread and selects the focused native window identity. The host retains IME
state separately for every window. JavaFXHost.update_window_ime_composition(id,...)
also exposes this ingress to integrations/tests; update_ime_composition targets
the root. The caret is converted from Godot Unicode code points
to Java UTF-16 offsets. Input record 13 starts a composition packet with length
and caret; record 14 carries up to eight UTF-16 units. Each V2 input record contains twelve doubles: the source window ID remains
in field 9 (zero-based), with fields 10/11 reserved for scroll settings. The whole packet enters
the existing input FIFO atomically, preserving ordering with keys and pointers.
The 16,384-unit composition and 4,096-record queue limits fail explicitly.

test-native-ime.ps1 passes GL and Vulkan separate-thread mode in a secondary Stage
outside the root, with local candidate coordinates, unchanged root text, Chinese/
emoji composition/commit/cancel, focus completion, disable and resource cleanup.
It temporarily aligns/restores the physical pointer for the final injected click,
because composition completion pumps real Windows mouse events. Actual system IME
candidate selection, reconversion and mixed-DPI placement are not yet accepted.

Glass delivers preedit through notifyInputMethod to the normal JavaFX control
skin. Godot's Windows backend delivers committed characters through WM_CHAR and
InputEventKey; Glass clears preedit before those typed events to avoid duplication.
The source Windows backend now publishes an IME update at END_COMPOSITION and
returns empty preedit after composition ends, including cancellation. Its getters
also reject missing focus windows and nonpositive native string lengths.

Before focus changes, Glass queues completion on main and waits at most two
seconds for acknowledgement. Main completes the Windows context and drains its
resulting character messages before acknowledging. Glass delivers only that window's queued composition packets and Unicode commits
(keys without a physical key code) to the old focus owner before returning; any
remaining preedit is canceled. Mouse events and ordinary physical keys stay in
the ordered queue until the current callback returns. Draining all input here
previously dispatched a queued release inside an unfinished mouse press.
Godot main never calls JavaFX controls. This bounded handshake is only used while
preedit is active. Host shutdown and timeout are reported, not silently ignored.

Run the injected-event test with:

```powershell
.\scripts\test-ime.ps1
.\scripts\test-ime.ps1 -Renderer mobile
```

It uses a standard TextField and Button, verifies Chinese and supplementary
Unicode preedit, caret offsets, replacement, typed commit, cancellation through
the DisplayServer query path and focus cleanup. It does not touch the clipboard.
These are host-ingress tests, not physical Chinese/Japanese/Korean IME acceptance.
Godot exposes a caret but not Windows clause/highlight attributes, so current
composition runs use JavaFX's unselected-raw highlight. Live candidate placement,
conversion choices, reconversion, multiple text controls and DPI require further
interactive coverage before claiming complete Windows input-method compatibility.

The IME and input-cancellation Java probes propagate startup callback failures and
request Platform.exit in a finally block around completion waits, including interruption.
The injected-event tests remain distinct from physical input-method acceptance.

On macOS the same host commands 16/17/18 apply; commit is routed to
`DisplayServerMacOS::window_commit_ime_composition`, which commits the marked
text through NSTextInputContext (`discardMarkedText` followed by `insertText`).
The injected probes run as `scripts/test-ime.sh` and
`scripts/test-native-ime.sh`; physical IME candidate UI on macOS remains
unverified.
