#ifdef WAYLAND_ENABLED
#include "javafx_host_wayland.h"
#include "linux_dnd.h"
#include "linux_drag_image.h"
#include "linux_clipboard.h"

#include "platform/linuxbsd/wayland/display_server_wayland.h"
#include <chrono>
#include <poll.h>
#include <unistd.h>

namespace godot_javafx {
namespace {
using Clock = std::chrono::steady_clock;

// The source writes on its own schedule. Bound both transfer time and the
// aggregate size across formats, and close the pipe on every exit path.
bool read_mime(int fd, Clock::time_point deadline, size_t &budget, std::string &bytes) {
	if (fd < 0) return false;
	struct Pipe {
		int fd;
		~Pipe() { close(fd); }
	} pipe{ fd };
	struct pollfd input{ fd, POLLIN, 0 };
	char buffer[16384];
	while (true) {
		auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
		if (ms <= 0) return false;
		int ready = poll(&input, 1, int(ms));
		if (ready < 0 && errno == EINTR) continue;
		if (ready <= 0 || !(input.revents & (POLLIN | POLLHUP))) return false;
		ssize_t count = read(fd, buffer, sizeof(buffer));
		if (count == 0) return true;
		if (count < 0 && errno == EINTR) continue;
		if (count < 0 || size_t(count) > budget) return false;
		bytes.append(buffer, size_t(count));
		budget -= size_t(count);
	}
}

uint32_t drag_event(void *userdata, const WaylandThread::DragEventMessage &event, String &mime) {
	using namespace linux_dnd;
	using Phase = WaylandThread::DragEventMessage;
	auto &target = *static_cast<TargetHandler *>(userdata);
	try {
		uint64_t identity = event.offer->get_instance_id();
		if (event.phase == Phase::ENTER) {
			target.leave();
			target.wayland_offer = identity;
			auto deadline = Clock::now() + std::chrono::milliseconds(1500);
			size_t budget = MAX_TEXT_BYTES;
			for (const String &type : event.mime_types) {
				std::string name(type.utf8().get_data());
				if (!supported_format(name)) continue;
				std::string bytes;
				if (!read_mime(event.offer->open_mime(type), deadline, budget, bytes)) break;
				size_t before = target.enter_payload.mimes.size();
				decode_format(target.enter_payload, name, std::move(bytes));
				if (target.wayland_mime.empty() && target.enter_payload.mimes.size() > before) target.wayland_mime = name;
			}
		}
		if (target.wayland_offer != identity) return 0;
		if (event.phase == Phase::LEAVE) {
			target.leave();
			return 0;
		}
		target.x = event.point.x;
		target.y = event.point.y;
		uint32_t effects = event.actions & (DROPEFFECT_COPY | DROPEFFECT_MOVE);
		uint32_t keys = (event.shift ? KEY_SHIFT : 0) | (event.control ? KEY_CONTROL : 0);
		uint32_t action = 0;
		if (!target.wayland_mime.empty() && (event.phase != Phase::DROP || (target.accepted & effects))) {
			mime = String::utf8(target.wayland_mime.c_str());
			action = target.dispatch(event.phase, effects, keys);
		}
		if (event.phase == Phase::DROP) {
			if (action) target.enter_payload = {};
			target.leave();
		}
		if (event.phase != Phase::DROP) target.accepted = action;
		return action;
	} catch (const std::exception &error) {
		ERR_PRINT(String("Wayland drag target failed: ") + error.what());
		target.leave();
		return 0;
	}
}
}

namespace wayland_clipboard {
static DisplayServerWayland *server() {
	return Object::cast_to<DisplayServerWayland>(DisplayServer::get_singleton());
}

static void fail(JNIEnv *env, const char *message) {
	env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}

static String mime_name(JNIEnv *env, jstring name) {
	if (!name || env->GetStringLength(name) > 256) return String();
	const char *utf8 = env->GetStringUTFChars(name, nullptr);
	if (!utf8) return String();
	String value = String::utf8(utf8);
	env->ReleaseStringUTFChars(name, utf8);
	return value;
}

jobjectArray JNICALL formats(JNIEnv *env, jclass) {
	auto *display = server();
	if (!display) { fail(env, "Wayland clipboard display is unavailable"); return nullptr; }
	Vector<String> types = display->clipboard_types();
	jclass type = env->FindClass("java/lang/String");
	if (!type) return nullptr;
	jobjectArray result = env->NewObjectArray(types.size(), type, nullptr);
	if (!result) return nullptr;
	for (int i = 0; i < types.size(); ++i) {
		auto text = types[i].utf16();
		jstring name = env->NewString(reinterpret_cast<const jchar *>(text.get_data()), text.length());
		if (!name) return nullptr;
		env->SetObjectArrayElement(result, i, name);
		env->DeleteLocalRef(name);
		if (env->ExceptionCheck()) return nullptr;
	}
	return result;
}

jbyteArray JNICALL read(JNIEnv *env, jclass, jstring name) try {
	auto *display = server();
	if (!display) { fail(env, "Wayland clipboard display is unavailable"); return nullptr; }
	String mime = mime_name(env, name);
	if (env->ExceptionCheck()) return nullptr;
	Vector<uint8_t> owned;
	int fd;
	Error error = display->clipboard_open(mime, owned, fd);
	if (error == ERR_DOES_NOT_EXIST) return nullptr;
	if (error != OK) { fail(env, "Cannot open Wayland clipboard offer"); return nullptr; }
	std::string received;
	size_t limit = mime == "image/png" ? 68U << 20 : 16U << 20;
	if (fd >= 0 && !read_mime(fd, Clock::now() + std::chrono::seconds(5), limit, received)) {
		fail(env, "Wayland clipboard transfer exceeded its size or time limit");
		return nullptr;
	}
	const size_t size = fd >= 0 ? received.size() : owned.size();
	if (size > (68U << 20)) { fail(env, "Wayland clipboard value too large"); return nullptr; }
	jbyteArray result = env->NewByteArray(jsize(size));
	if (result && size) {
		const void *bytes = fd >= 0 ? static_cast<const void *>(received.data()) : owned.ptr();
		env->SetByteArrayRegion(result, 0, size, static_cast<const jbyte *>(bytes));
	}
	return result;
} catch (const std::bad_alloc &) {
	env->ThrowNew(env->FindClass("java/lang/OutOfMemoryError"), "Wayland clipboard read");
	return nullptr;
}

void JNICALL write(JNIEnv *env, jclass, jobjectArray names, jobjectArray values) {
	auto *display = server();
	if (!display) { fail(env, "Wayland clipboard display is unavailable"); return; }
	if (!names || !values || env->GetArrayLength(names) != env->GetArrayLength(values) || env->GetArrayLength(names) > 40) {
		env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid Wayland clipboard arrays");
		return;
	}
	HashMap<String, Vector<uint8_t>> formats;
	for (int i = 0; i < env->GetArrayLength(names); ++i) {
		auto name = static_cast<jstring>(env->GetObjectArrayElement(names, i));
		if (env->ExceptionCheck()) return;
		String mime = mime_name(env, name);
		env->DeleteLocalRef(name);
		if (env->ExceptionCheck()) return;
		auto bytes = static_cast<jbyteArray>(env->GetObjectArrayElement(values, i));
		if (env->ExceptionCheck()) return;
		if (mime.is_empty() || formats.has(mime) || !bytes || env->GetArrayLength(bytes) > (mime == "image/png" ? 68 : 16) * 1024 * 1024) {
			env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), "Invalid Wayland clipboard value");
			return;
		}
		Vector<uint8_t> content;
		if (content.resize(env->GetArrayLength(bytes)) != OK) {
			env->ThrowNew(env->FindClass("java/lang/OutOfMemoryError"), "Wayland clipboard write");
			return;
		}
		if (!content.is_empty()) env->GetByteArrayRegion(bytes, 0, content.size(), reinterpret_cast<jbyte *>(content.ptrw()));
		env->DeleteLocalRef(bytes);
		if (env->ExceptionCheck()) return;
		formats.insert(mime, content);
	}
	if (display->clipboard_set_data(formats) != OK) fail(env, "Wayland clipboard needs an active seat and input serial");
}
}
}

namespace godot_javafx {
Dictionary linux_cursor_info() {
	return static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->cursor_get_custom_buffer_info();
}

void linux_finish_ime(DisplayServerEnums::WindowID id, bool commit) {
	static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->window_finish_javafx_ime(id, commit);
}

void linux_release_startup_window(DisplayServerEnums::WindowID id) {
	static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->window_set_javafx_visible(id, true);
}

void linux_set_root_visible(bool visible) {
	static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->window_set_javafx_visible(DisplayServerEnums::MAIN_WINDOW_ID, visible);
}

bool linux_window_visible(DisplayServerEnums::WindowID id) {
	return static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->window_is_javafx_visible(id);
}

Dictionary wayland_window_icon_info(DisplayServerEnums::WindowID id) {
	return static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->window_get_icon_buffer_info(id);
}

String wayland_exported_parent(DisplayServerEnums::WindowID id) {
	auto *server = Object::cast_to<DisplayServerWayland>(DisplayServer::get_singleton());
	if (server && id != DisplayServerEnums::INVALID_WINDOW_ID) {
		return server->window_get_exported_handle(id).trim_prefix("wayland:");
	}
	return {};
}

bool wayland_start_drag(DisplayServerEnums::WindowID id, const unix_drag::SourceData &data) {
	try {
		auto *server = Object::cast_to<DisplayServerWayland>(DisplayServer::get_singleton());
		if (!server) return false;
		WaylandThread::DragSourceData source;
		source.actions = data.effects & (unix_drag::DROPEFFECT_COPY | unix_drag::DROPEFFECT_MOVE);
		for (const auto &[type, bytes] : linux_dnd::encode_formats(data)) {
			Vector<uint8_t> content;
			if (content.resize(bytes.size()) != OK) return false;
			if (!bytes.empty()) memcpy(content.ptrw(), bytes.data(), bytes.size());
			source.formats.insert(String::utf8(type.c_str()), content);
		}
		if (data.image.present()) {
			source.size = Size2i(data.image.width, data.image.height);
			source.bgra = data.image.bgra.data();
			if (!linux_dnd::drag_image(data.image, source.hotspot.x, source.hotspot.y)) return false;
		}
		Error err = server->drag_source_start(id, source);
		if (err != OK) ERR_PRINT(vformat("Wayland drag source could not start: %s", error_names[err]));
		return err == OK;
	} catch (const std::exception &error) {
		ERR_PRINT(String("Wayland drag source failed: ") + error.what());
	}
	return false;
}

int wayland_drag_result(DisplayServerEnums::WindowID id, bool cancel) {
	auto *server = Object::cast_to<DisplayServerWayland>(DisplayServer::get_singleton());
	if (server) return server->drag_source_result(id, cancel);
	return 0;
}

bool linux_set_drag_target(DisplayServerEnums::WindowID id, linux_dnd::TargetHandler *target) {
	return static_cast<DisplayServerWayland *>(DisplayServer::get_singleton())->window_set_drag_target(id, target ? drag_event : nullptr, target);
}
}
#endif
