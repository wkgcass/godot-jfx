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

constexpr size_t MAX_TEXT_BYTES = 16 * 1024 * 1024;
constexpr size_t MAX_URL_CHARS = 4096;
constexpr size_t MAX_PATHS = 4096;
constexpr size_t MAX_PATH_CHARS = 32768;

// Windows DROPEFFECT bit layout, shared with the Java contract.
constexpr uint32_t DROPEFFECT_NONE = 0;
constexpr uint32_t DROPEFFECT_COPY = 1;
constexpr uint32_t DROPEFFECT_MOVE = 2;
constexpr uint32_t DROPEFFECT_LINK = 4;

// Modifier bits inside the Java keyState argument, matching Windows MK_*.
constexpr uint32_t KEY_SHIFT = 0x04;
constexpr uint32_t KEY_CONTROL = 0x08;

// Custom format names ride as UTF-16 on every platform; Windows stores them
// in std::wstring, this backend uses the portable equivalent.
using wide_string = std::u16string;

struct SourceData {
	std::u16string text, url;
	std::string html, rtf; // HTML carries its Windows clipboard header; both are NUL-terminated.
	std::vector<std::u16string> files;
	std::vector<std::pair<std::u16string, std::string>> custom; // Pasteboard type name, NUL-terminated bytes.
	// Dragboard.setDragView payload, as published by the Quantum layer: BGRA
	// bytes in a big-endian w/h envelope. Offsets use INT32_MIN when absent,
	// matching the Glass default of the image center.
	struct DragImage {
		uint32_t width = 0, height = 0;
		int32_t offset_x = INT32_MIN, offset_y = INT32_MIN;
		std::vector<uint8_t> bgra;
		bool present() const { return width != 0 && height != 0; }
	};
	DragImage image;
	uint32_t effects = 0;
	int buttons = 0; // Java bit mask 1 << buttonIndex (1 left, 2 right, 3 middle).
	int64_t source_id = 0; // Glass window id; 0 is the root host window.
};

// Published together after JNI registration. The worker closes this gate before
// DestroyJavaVM; the mutex covers the whole upcall, including GetEnv/attachment
// and detachment. Clearing an atomic class pointer alone leaves an entry race.
struct UpcallState {
	std::mutex mutex;
	JavaVM *jvm = nullptr;
	jclass bridge = nullptr;
	jmethodID callback = nullptr;
	void publish(JavaVM *vm, jclass type, jmethodID method) {
		std::lock_guard<std::mutex> lock(mutex);
		jvm = vm;
		bridge = type;
		callback = method;
	}
	void close() {
		std::lock_guard<std::mutex> lock(mutex);
		jvm = nullptr;
		bridge = nullptr;
		callback = nullptr;
	}
};

struct Upcall {
	UpcallState *state = nullptr;
	explicit operator bool() const {
		if (!state) return false;
		std::lock_guard<std::mutex> lock(state->mutex);
		return state->jvm && state->bridge && state->callback;
	}
};

inline jstring to_jstring(JNIEnv *env, const std::u16string *value) {
	if (!value) return nullptr;
	return env->NewString(reinterpret_cast<const jchar *>(value->data()), jsize(value->size()));
}
inline jstring call_string(JNIEnv *env, const std::string &value) {
	return env->NewStringUTF(value.c_str());
}
inline jbyteArray call_bytes(JNIEnv *env, const std::string *value) {
	if (!value) return nullptr;
	jbyteArray result = env->NewByteArray(jsize(value->size()));
	if (result && !value->empty()) env->SetByteArrayRegion(result, 0, jsize(value->size()), reinterpret_cast<const jbyte *>(value->data()));
	return result;
}

// Synchronous Godot-main-thread upcall. The Java handler re-dispatches to the
// JavaFX event thread with a bounded wait, so a stalled FX loop degrades to
// DROPEFFECT_NONE instead of deadlocking the host.
inline jint call_target(const Upcall &upcall, jint kind, int64_t id, jint sx, jint sy, jint effects, jint key_state,
		const std::string &mimes, const std::u16string *text, const std::string *html, const std::string *rtf,
		const std::u16string *url, const std::u16string *files,
		const std::vector<std::pair<std::u16string, std::string>> *custom) {
	if (!upcall.state) return 0;
	// No host/queue lock is held here. The Java dispatch has a bounded wait.
	std::lock_guard<std::mutex> lifetime(upcall.state->mutex);
	JavaVM *jvm = upcall.state->jvm;
	jclass bridge = upcall.state->bridge;
	jmethodID callback = upcall.state->callback;
	if (!jvm || !bridge || !callback) return 0;
	JNIEnv *env = nullptr;
	jint env_result = jvm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_8);
	bool attached = false;
	if (env_result == JNI_EDETACHED) {
		if (jvm->AttachCurrentThread(reinterpret_cast<void **>(&env), nullptr) != JNI_OK) return 0;
		attached = true; // Balance the attach: DestroyJavaVM waits for attached threads.
	} else if (env_result != JNI_OK) return 0;
	jstring mime_arg = nullptr, text_arg = nullptr, url_arg = nullptr, files_arg = nullptr;
	jbyteArray html_arg = nullptr, rtf_arg = nullptr;
	jobjectArray names_arg = nullptr, data_arg = nullptr;
	// Once JNI raises an exception, only exception handling and local-reference
	// cleanup are permitted here. Stop marshalling at the first failed operation.
	auto marshal = [&]() {
		if (env->ExceptionCheck()) return;
		mime_arg = call_string(env, mimes);
		if (env->ExceptionCheck()) return;
		text_arg = to_jstring(env, text);
		if (env->ExceptionCheck()) return;
		html_arg = call_bytes(env, html);
		if (env->ExceptionCheck()) return;
		rtf_arg = call_bytes(env, rtf);
		if (env->ExceptionCheck()) return;
		url_arg = to_jstring(env, url);
		if (env->ExceptionCheck()) return;
		files_arg = to_jstring(env, files);
		if (env->ExceptionCheck() || !custom) return;
		jclass string_class = env->FindClass("java/lang/String");
		if (!string_class) return;
		names_arg = env->NewObjectArray(jsize(custom->size()), string_class, nullptr);
		env->DeleteLocalRef(string_class);
		if (env->ExceptionCheck()) return;
		jclass bytes_class = env->FindClass("[B");
		if (!bytes_class) return;
		data_arg = env->NewObjectArray(jsize(custom->size()), bytes_class, nullptr);
		env->DeleteLocalRef(bytes_class);
		if (env->ExceptionCheck()) return;
		for (jsize i = 0; i < jsize(custom->size()); ++i) {
			jstring name = env->NewString(reinterpret_cast<const jchar *>((*custom)[i].first.data()), jsize((*custom)[i].first.size()));
			if (!name) return;
			env->SetObjectArrayElement(names_arg, i, name);
			env->DeleteLocalRef(name);
			if (env->ExceptionCheck()) return;
			jbyteArray payload = call_bytes(env, &(*custom)[i].second);
			if (payload) {
				if (!env->ExceptionCheck()) env->SetObjectArrayElement(data_arg, i, payload);
				env->DeleteLocalRef(payload);
			}
			if (env->ExceptionCheck()) return;
		}
	};
	marshal();
	jint action = 0;
	if (!env->ExceptionCheck()) {
		action = env->CallStaticIntMethod(bridge, callback, kind, jlong(id), sx, sy, effects, key_state,
				mime_arg, text_arg, html_arg, rtf_arg, url_arg, files_arg, names_arg, data_arg);
	}
	if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); action = 0; }
	if (mime_arg) env->DeleteLocalRef(mime_arg);
	if (text_arg) env->DeleteLocalRef(text_arg);
	if (html_arg) env->DeleteLocalRef(html_arg);
	if (rtf_arg) env->DeleteLocalRef(rtf_arg);
	if (url_arg) env->DeleteLocalRef(url_arg);
	if (files_arg) env->DeleteLocalRef(files_arg);
	if (names_arg) env->DeleteLocalRef(names_arg);
	if (data_arg) env->DeleteLocalRef(data_arg);
	if (attached) jvm->DetachCurrentThread();
	return action;
}

// Data extracted from a dragging pasteboard. Presence flags mirror the MIME list.
struct Payload {
	bool has_text = false, has_html = false, has_rtf = false, has_url = false, has_files = false;
	std::u16string text, url, files;
	std::string html, rtf; // NUL-terminated, matching the Java contract.
	std::vector<std::pair<std::u16string, std::string>> custom; // NUL-terminated bytes.
	std::string mimes;
};

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
