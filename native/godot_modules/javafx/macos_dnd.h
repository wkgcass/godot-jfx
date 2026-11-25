#pragma once

#include <jni.h>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#include "macos_custom_format.h"
#include "unix_drag_payload.h"

// Cocoa drag/drop between the hosted JavaFX application and other macOS
// processes. Dragging destinations call the module through the
// DisplayServerMacOS drag delegate on the Godot main thread; outbound drags
// start an NSDraggingSession whose completion reaches Java as a synthetic
// input record. This header stays Objective-C free so the host's JNI
// translation unit can include it; pasteboard and session code lives in
// macos_dnd.mm. Pasteboard conventions match the system clipboard adapter
// (macos_clipboard.mm): public.html/public.rtf carry the rich payloads without
// their NUL terminator, file lists prefer the verbatim NSFilenamesPboardType
// property list (the system synthesizes it from file-url items; item-level
// NSFilenamesPboardType writes are rejected on macOS 26), and custom formats
// publish the UTI twin of the application/x-godot-custom-* MIME names
// (NSPasteboardItem rejects non-UTI type strings; see macos_custom_format.h).
namespace godot_javafx::macos_dnd {

using namespace godot_javafx::unix_drag;

// Reads a dragging pasteboard (id<NSDraggingInfo> as void*). Availability is
// always queried; payload data is extracted only with_data (drag enter/drop).
// Malformed payloads drop that one format instead of failing the drag. Returns
// false when nothing the Java side understands is present, which lets the view
// fall back to Godot's own file-drop handling.
bool extract(void *sender, Payload &payload, bool with_data);

// Handles drag-in events for one host window through the DisplayServerMacOS
// drag delegate. Runs on the Godot main thread inside Cocoa dragging
// callbacks; ownership and per-window lifetime are managed by the JavaFX host.
struct TargetHandler {
	int64_t id = 0;
	Upcall upcall;
	Payload enter_payload;

	jint dispatch(jint kind, int x, int y, uint32_t effects, uint32_t key_state, const Payload *payload) {
		return call_target(upcall, kind, id, x, y, jint(effects), jint(key_state),
				payload ? payload->mimes : std::string(),
				payload && payload->has_text ? &payload->text : nullptr,
				payload && payload->has_html ? &payload->html : nullptr,
				payload && payload->has_rtf ? &payload->rtf : nullptr,
				payload && payload->has_url ? &payload->url : nullptr,
				payload && payload->has_files ? &payload->files : nullptr,
				payload && !payload->custom.empty() ? &payload->custom : nullptr);
	}

	// kind: 1 entered, 2 updated, 3 exited, 4 drop. effect is the allowed
	// DROPEFFECT mask on entry and the chosen effect on return.
	bool handle(int kind, void *sender, int x, int y, uint32_t *effect);
};

// Starts a Cocoa dragging session from the window p_window_id (p_ns_window is
// its NSWindow *) carrying the source data and optional drag image. AppKit
// only tracks the physical mouse button for sessions started inside a real
// mouseDragged dispatch, so the session actually begins on the next drag
// event delivered to the content view (registered through DisplayServerMacOS
// ::window_set_drag_start_handler). done runs on the main thread exactly
// once with the resulting DROPEFFECT (0 when the drag was cancelled or the
// session failed to start). Returns false when no session could start (done
// is not called then).
bool begin_source(const SourceData &data, int64_t p_window_id, void *ns_window, void (*done)(void *ctx, uint32_t effect), void *ctx);

// Test hook: publishes p_data on a private pasteboard and feeds a synthetic
// dragging info through the target's enter/drop handlers, verifying the
// outbound format exposure and the inbound extractor/dispatch without a
// physical mouse. Returns true when the drop was accepted with a real effect.
bool simulate_drop(TargetHandler &target, int x, int y, const SourceData &data);

} // namespace godot_javafx::macos_dnd
