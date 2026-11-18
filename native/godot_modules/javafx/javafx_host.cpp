#include "javafx_host.h"

#include "javafx_shader_rewrite.h"
#include "servers/rendering/rendering_server.h"
#include "core/object/callable_mp.h"
#include "frame_protocol.h"
#include "native_window_transport.h"

#include "core/config/engine.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/object/class_db.h"
#include "core/os/thread.h"
#include "core/os/os.h"
#include "core/os/main_loop.h"
#include "core/string/print_string.h"
#include "servers/display/display_server.h"
#include "scene/main/window.h"
#include "scene/main/scene_tree.h"

#if defined(WINDOWS_ENABLED)
#include "platform/windows/display_server_windows.h"
#include <windows.h>
#include <imm.h>
#include "windows_clipboard.h"
#include "windows_robot.h"
#include "windows_dialogs.h"
#include "windows_dnd.h"
#include "windows_tabtip.h"
#include "windows_custom_format.h"
#elif defined(MACOS_ENABLED)
#include "macos_clipboard.h"
#include "macos_robot.h"
#include "macos_dialogs.h"
#include "macos_dnd.h"
#include "macos_tabtip.h"
#include "macos_custom_format.h"
#include "javafx_host_macos.h"
#endif

#include <jni.h>
#include <atomic>
#include <array>
#include <shared_mutex>

namespace godot_javafx {

#if defined(WINDOWS_ENABLED)
namespace platform_clipboard = windows_clipboard;
namespace platform_dialogs = windows_dialogs;
namespace platform_dnd = windows_dnd;
namespace platform_robot = windows_robot;
namespace platform_tabtip = windows_tabtip;
using OsNativeWindow = HWND;
#elif defined(MACOS_ENABLED)
namespace platform_clipboard = macos_clipboard;
namespace platform_dialogs = macos_dialogs;
namespace platform_dnd = macos_dnd;
namespace platform_robot = macos_robot;
namespace platform_tabtip = macos_tabtip;
using OsNativeWindow = void *; // NSWindow *; unused by the pasteboard backend.
#endif

enum class RuntimeStatus { STARTING, RUNNING, FINISHED, FAILED };

struct HostCommand {
	int operation, a, b, sequence;
	std::u16string text;
	int cursor_width = 0, cursor_height = 0;
	std::vector<uint8_t> cursor_pixels;
	int icon_width = 0, icon_height = 0;
	std::vector<uint8_t> icon_pixels;
};

struct ReadbackRequest {
	uint64_t handle, sequence;
	int x, y, width, height;
	bool done = false;
	std::string error;
	std::vector<jint> pixels;
};

struct Runtime {
    platform_dialogs::Service dialogs;
    OsNativeWindow clipboard_owner = nullptr; // Set before the JVM thread starts; immutable.
    // Close admission and wait for in-flight native drag callbacks before detaching.
    platform_dnd::UpcallState drag_upcall;
    std::mutex dnd_mutex;
    std::unique_ptr<platform_dnd::SourceData> dnd_pending;
	FrameQueue queue;
	NativeWindowTransport native_window_transport;
	std::atomic<uint64_t> completed_render_sequence{0};
	std::atomic<uint64_t> submit_calls{0}, submit_us{0}, tick_wait_calls{0}, tick_wait_us{0};
	std::atomic<uint64_t> metadata_jni_calls{0}, metadata_jni_us{0}, fixture_probe_calls{0};
	std::mutex readback_mutex;
	std::condition_variable readback_changed;
	std::shared_ptr<ReadbackRequest> readback;
	bool readbacks_stopped = false;
	void stop_readbacks() {
		std::lock_guard<std::mutex> lock(readback_mutex);
		readbacks_stopped = true;
		readback_changed.notify_all();
	}
	std::mutex host_mutex;
	std::array<jint, 16> info{};
	std::vector<jint> screens;
	std::deque<HostCommand> host_commands;
	std::deque<std::array<double, 12>> input_events;
	int next_host_sequence = 1;
	int applied_host_sequence = 0;
	std::atomic<RuntimeStatus> status{ RuntimeStatus::STARTING };
	std::mutex error_mutex;
	std::string error;
	void fail(const std::string &message) {
		{ std::lock_guard<std::mutex> lock(error_mutex); error = message; }
		status.store(RuntimeStatus::FAILED);
        dialogs.cancel();
		stop_readbacks();
		queue.stop();
		native_window_transport.stop();
	}
};

static std::atomic<bool> probe_started{ false };
static Runtime *jni_runtime = nullptr;
static std::shared_mutex bridge_lifetime;
static std::atomic<bool> bridge_open{ false };
static std::atomic<bool> library_claimed{ false };

struct JniSample {
	std::atomic<uint64_t> &elapsed;
	uint64_t start;
	JniSample(std::atomic<uint64_t> &p_calls, std::atomic<uint64_t> &p_elapsed) : elapsed(p_elapsed), start(OS::get_singleton()->get_ticks_usec()) {
		p_calls.fetch_add(1, std::memory_order_relaxed);
	}
	~JniSample() { elapsed.fetch_add(OS::get_singleton()->get_ticks_usec() - start, std::memory_order_relaxed); }
};

static void throw_java(JNIEnv *env, const char *type, const char *message) {
	jclass exception = env->FindClass(type);
	if (exception) {
		env->ThrowNew(exception, message);
		env->DeleteLocalRef(exception);
	}
}

static jboolean submit_impl(JNIEnv *env, jobject buffer, jint length) {
	if (!buffer || length < 24 || size_t(length) > MAX_FRAME_BYTES || env->GetDirectBufferCapacity(buffer) < length) {
		throw_java(env, "java/lang/IllegalArgumentException", "Frame must be a direct buffer with a valid bounded length");
		return JNI_FALSE;
	}
	const auto *data = static_cast<const uint8_t *>(env->GetDirectBufferAddress(buffer));
	if (!data) {
		throw_java(env, "java/lang/IllegalArgumentException", "Frame is not direct");
		return JNI_FALSE;
	}
	// Own the bytes before validation. The Java caller may reuse its buffer as
	// soon as this call returns; Godot never keeps a Java memory address.
	std::vector<uint8_t> owned(data, data + length);
	Frame frame;
	std::string error;
	if (!decode_frame(owned, frame, error)) {
		throw_java(env, "java/lang/IllegalArgumentException", error.c_str());
		return JNI_FALSE;
	}
	switch (jni_runtime->queue.submit(std::move(frame))) {
		case SubmitResult::ACCEPTED: return JNI_TRUE;
		case SubmitResult::FULL: return JNI_FALSE;
		case SubmitResult::STOPPED:
			throw_java(env, "com/sun/javafx/tk/godot/GodotHostStoppedException", "Godot host is stopping");
			break;
		case SubmitResult::STALE:
			throw_java(env, "java/lang/IllegalArgumentException", "Frame sequence must increase");
			break;
		case SubmitResult::INVALID_RESOURCE:
			throw_java(env, "java/lang/IllegalArgumentException", "Invalid texture transaction or presentation boundary");
			break;
	}
	return JNI_FALSE;
}

static jboolean JNICALL submit(JNIEnv *env, jclass, jobject buffer, jint length) {
	JniSample sample(jni_runtime->submit_calls, jni_runtime->submit_us);
	try { return submit_impl(env, buffer, length); }
	catch (const std::bad_alloc &) {
		throw_java(env, "java/lang/OutOfMemoryError", "Cannot allocate owned Godot render transaction");
		return JNI_FALSE;
	}
}

static jlong JNICALL await_tick(JNIEnv *env, jclass, jlong after, jint timeout) {
	JniSample sample(jni_runtime->tick_wait_calls, jni_runtime->tick_wait_us);
	if (after < 0 || timeout < 1 || timeout > 1000) {
		throw_java(env, "java/lang/IllegalArgumentException", "Invalid frame wait arguments");
		return -1;
	}
	return jni_runtime->queue.await_tick(uint64_t(after), uint32_t(timeout));
}

static jlong JNICALL await_frame_tick(JNIEnv *env, jclass, jlong after, jint timeout) {
	JniSample sample(jni_runtime->tick_wait_calls, jni_runtime->tick_wait_us);
	if (after < 0 || timeout < 1 || timeout > 1000) {
		throw_java(env, "java/lang/IllegalArgumentException", "Invalid host-frame wait arguments");
		return -1;
	}
	return jni_runtime->queue.await_frame_tick(uint64_t(after), uint32_t(timeout));
}

static jlong JNICALL await_input_tick(JNIEnv *env, jclass, jlong after, jint timeout) {
	JniSample sample(jni_runtime->tick_wait_calls, jni_runtime->tick_wait_us);
	if (after < 0 || timeout < 1 || timeout > 1000) {
		throw_java(env, "java/lang/IllegalArgumentException", "Invalid input wait arguments");
		return -1;
	}
	return jni_runtime->queue.await_input_tick(uint64_t(after), uint32_t(timeout));
}

static jintArray JNICALL host_info(JNIEnv *env, jclass) {
	JniSample sample(jni_runtime->metadata_jni_calls, jni_runtime->metadata_jni_us);
	std::array<jint, 16> values;
	{ std::lock_guard<std::mutex> lock(jni_runtime->host_mutex); values = jni_runtime->info; }
	jintArray result = env->NewIntArray(int(values.size()));
	if (result) env->SetIntArrayRegion(result, 0, int(values.size()), values.data());
	return result;
}

static jintArray JNICALL screen_info(JNIEnv *env, jclass) {
	JniSample sample(jni_runtime->metadata_jni_calls, jni_runtime->metadata_jni_us);
	try {
		std::vector<jint> values;
		{ std::lock_guard<std::mutex> lock(jni_runtime->host_mutex); values = jni_runtime->screens; }
		jintArray result = env->NewIntArray(int(values.size()));
		if (result) env->SetIntArrayRegion(result, 0, int(values.size()), values.data());
		return result;
	} catch (const std::bad_alloc &) {
		throw_java(env, "java/lang/OutOfMemoryError", "Cannot allocate Godot screen snapshot");
		return nullptr;
	}
}

static jlong JNICALL native_window_command(JNIEnv *env, jclass, jlong id, jlong owner, jint operation,
		jint x, jint y, jint width, jint height, jint flags, jboolean visible, jstring title) {
	try {
		NativeWindowCommand command;
		command.id=id; command.owner=owner; command.operation=operation;
		command.x=x; command.y=y; command.width=width; command.height=height;
		command.flags=flags; command.visible=visible;
		if (title) {
			jsize length=env->GetStringLength(title);
			if (length>4096) throw std::invalid_argument("Native window title exceeds 4096 UTF-16 units");
			command.title.resize(length);
			if (length) env->GetStringRegion(title,0,length,reinterpret_cast<jchar *>(command.title.data()));
			if (env->ExceptionCheck()) return 0;
		}
		return jni_runtime->native_window_transport.submit(std::move(command));
	} catch (const std::bad_alloc &) { throw_java(env,"java/lang/OutOfMemoryError","Native window command allocation failed"); }
	catch (const NativeWindowTransportStopped &error) { throw_java(env,"com/sun/javafx/tk/godot/GodotHostStoppedException",error.what()); }
	catch (const std::invalid_argument &error) { throw_java(env,"java/lang/IllegalArgumentException",error.what()); }
	catch (const std::exception &error) { throw_java(env,"java/lang/IllegalStateException",error.what()); }
	return 0;
}

static jlongArray JNICALL native_window_info(JNIEnv *env, jclass, jlong id) {
	JniSample sample(jni_runtime->metadata_jni_calls, jni_runtime->metadata_jni_us);
	try {
		auto values=jni_runtime->native_window_transport.info(id);
		jlongArray result=env->NewLongArray(jsize(values.size()));
		if (result && !values.empty()) env->SetLongArrayRegion(result,0,jsize(values.size()),reinterpret_cast<const jlong *>(values.data()));
		return result;
	} catch (const std::bad_alloc &) { throw_java(env,"java/lang/OutOfMemoryError","Native window snapshot allocation failed"); return nullptr; }
}
static jlong JNICALL native_window_ack(JNIEnv *, jclass) { return jni_runtime->native_window_transport.ack(); }
static jboolean JNICALL is_shutdown_drained(JNIEnv *, jclass) {
	if (jni_runtime->completed_render_sequence.load() < jni_runtime->queue.get_last_sequence()) return JNI_FALSE;
	if (jni_runtime->native_window_transport.ack() < jni_runtime->native_window_transport.submitted()) return JNI_FALSE;
	std::lock_guard<std::mutex> lock(jni_runtime->host_mutex);
	return jni_runtime->info[11] >= jni_runtime->next_host_sequence - 1 ? JNI_TRUE : JNI_FALSE;
}

static jint host_command_impl(JNIEnv *env, jint operation, jint a, jint b, jstring text) {
	bool valid = (operation >= 1 && operation <= 20) || operation == 22 || operation == 23 || operation == 24 || operation == 26 || operation == 27;
	if (operation == 22 || operation == 23 || operation == 26 || operation == 27) valid = a == 0 && b == 0;
	if (operation == 19 || operation == 20 || operation == 24) valid = (a == 0 || a == 1) && b == 0;
	if (operation == 16) valid = (a == 0 || a == 1) && b == 0;
	if (operation == 17) valid = a >= -1000000 && a <= 1000000 && b >= -1000000 && b <= 1000000;
	if (operation == 18) valid = a == 0 && b == 0;
	if (operation == 2) valid = a > 0 && b > 0 && a <= 8192 && b <= 8192;
	if (operation == 5 || operation == 7 || operation == 9 || operation == 11 || operation == 15) valid = a == 0 || a == 1;
	if (operation == 6) valid = a >= 0 && a <= 3;
	if (operation == 8) valid = a >= 0 && a <= 1000000;
	if (operation == 10) valid = a >= -1 && a <= 19 && a != 0;
	if (operation == 12 || operation == 13) valid = a >= 0 && b >= 0 && a <= 8192 && b <= 8192;
	if (text && env->GetStringLength(text) > 4096) valid = false;
	if (!valid) {
		throw_java(env, "java/lang/IllegalArgumentException", "Invalid Godot host command");
		return 0;
	}
	HostCommand command{ operation, a, b, 0, {} };
	if (text) {
		jsize length = env->GetStringLength(text);
		command.text.resize(length);
		if (length) env->GetStringRegion(text, 0, length, reinterpret_cast<jchar *>(command.text.data()));
		if (env->ExceptionCheck()) return 0;
	}
	std::lock_guard<std::mutex> lock(jni_runtime->host_mutex);
	if (jni_runtime->host_commands.size() >= 256 || jni_runtime->next_host_sequence == INT32_MAX) {
		throw_java(env, "java/lang/IllegalStateException", "Godot host command queue limit exceeded");
		return 0;
	}
	command.sequence = jni_runtime->next_host_sequence;
	jint sequence = command.sequence;
	jni_runtime->host_commands.push_back(std::move(command));
	++jni_runtime->next_host_sequence;
	return sequence;
}

static jint JNICALL host_command(JNIEnv *env, jclass, jint operation, jint a, jint b, jstring text) {
	try { return host_command_impl(env, operation, a, b, text); }
	catch (const std::bad_alloc &) {
		throw_java(env, "java/lang/OutOfMemoryError", "Cannot allocate Godot window command");
		return 0;
	}
}

static jlong JNICALL window_icon(JNIEnv *env, jclass, jlong id, jint width, jint height, jbyteArray bgra) {
	const bool clear = width == 0 && height == 0;
	if (id < 0 || (!clear && (width < 1 || height < 1 || width > 256 || height > 256)) ||
			!bgra || env->GetArrayLength(bgra) != width * height * 4) {
		throw_java(env, "java/lang/IllegalArgumentException", "Invalid window icon"); return 0;
	}
	try {
		std::vector<uint8_t> pixels(size_t(width) * height * 4);
		if (!pixels.empty()) env->GetByteArrayRegion(bgra, 0, jsize(pixels.size()), reinterpret_cast<jbyte *>(pixels.data()));
		if (env->ExceptionCheck()) return 0;
		if (id != 0) {
			NativeWindowCommand command;
			command.id = id; command.operation = 5; command.width = width; command.height = height;
			command.icon_pixels = std::move(pixels);
			return jni_runtime->native_window_transport.submit(std::move(command));
		}
		HostCommand command{25, 0, 0, 0, {}};
		command.icon_width = width; command.icon_height = height; command.icon_pixels = std::move(pixels);
		std::lock_guard<std::mutex> lock(jni_runtime->host_mutex);
		size_t bytes = command.icon_pixels.size();
		for (const auto &queued : jni_runtime->host_commands) bytes += queued.icon_pixels.size();
		if (jni_runtime->host_commands.size() >= 256 || bytes > 1024 * 1024 || jni_runtime->next_host_sequence == INT32_MAX)
			throw std::runtime_error("Window icon queue limit exceeded");
		command.sequence = jni_runtime->next_host_sequence;
		jni_runtime->host_commands.push_back(std::move(command));
		return jni_runtime->next_host_sequence++;
	} catch (const std::bad_alloc &) { throw_java(env, "java/lang/OutOfMemoryError", "Window icon allocation failed"); }
	catch (const NativeWindowTransportStopped &error) { throw_java(env, "com/sun/javafx/tk/godot/GodotHostStoppedException", error.what()); }
	catch (const std::invalid_argument &error) { throw_java(env, "java/lang/IllegalArgumentException", error.what()); }
	catch (const std::exception &error) { throw_java(env, "java/lang/IllegalStateException", error.what()); }
	return 0;
}

static Ref<Image> window_icon_image(int width, int height, const std::vector<uint8_t> &bgra) {
	if (bgra.empty()) return Ref<Image>();
	PackedByteArray rgba; rgba.resize(bgra.size());
	for (size_t p = 0; p < bgra.size(); p += 4) {
		// Windows window_set_icon copies RGB bytes into its icon bitmap verbatim.
		// Keep Glass's premultiplied channels, matching native Glass CreateIcon;
		// this Image is an OS-icon payload, never a scene texture.
		rgba.set(p, bgra[p+2]); rgba.set(p+1, bgra[p+1]);
		rgba.set(p+2, bgra[p]); rgba.set(p+3, bgra[p+3]);
	}
	return Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, rgba);
}

static jint JNICALL custom_cursor(JNIEnv *env, jclass, jint width, jint height, jint x, jint y, jbyteArray bgra) {
	if (width < 1 || height < 1 || width > 256 || height > 256 || x < 0 || y < 0 || x >= width || y >= height ||
			!bgra || env->GetArrayLength(bgra) != width * height * 4) {
		throw_java(env, "java/lang/IllegalArgumentException", "Invalid custom cursor asset"); return 0;
	}
	try {
		HostCommand command{21,x,y,0,{}};
		command.cursor_width=width; command.cursor_height=height;
		command.cursor_pixels.resize(size_t(width)*height*4);
		env->GetByteArrayRegion(bgra,0,width*height*4,reinterpret_cast<jbyte *>(command.cursor_pixels.data()));
		if (env->ExceptionCheck()) return 0;
		std::lock_guard<std::mutex> lock(jni_runtime->host_mutex);
		// Cursor assets share the ordered host queue; cap their aggregate queued
		// size separately so repeated image changes cannot reserve 64 MiB here.
		size_t bytes=command.cursor_pixels.size();
		for(const auto &queued:jni_runtime->host_commands) bytes+=queued.cursor_pixels.size();
		if(jni_runtime->host_commands.size()>=256 || bytes>1024*1024 || jni_runtime->next_host_sequence==INT32_MAX) {
			throw_java(env,"java/lang/IllegalStateException","Custom cursor queue limit exceeded"); return 0;
		}
		command.sequence=jni_runtime->next_host_sequence;
		jint sequence=command.sequence;
		jni_runtime->host_commands.push_back(std::move(command));
		++jni_runtime->next_host_sequence;
		return sequence;
	} catch(const std::bad_alloc &) { throw_java(env,"java/lang/OutOfMemoryError","Custom cursor allocation failed"); return 0; }
}

static jintArray JNICALL read_pixels(JNIEnv *env, jclass, jlong handle, jlong sequence, jint x, jint y, jint width, jint height) {
	try {
		if (handle <= 0 || sequence <= 0 || uint64_t(sequence) > jni_runtime->queue.get_last_sequence() ||
				x < 0 || y < 0 || width <= 0 || height <= 0 || int64_t(x) + width > 8192 || int64_t(y) + height > 8192) {
			throw_java(env, "java/lang/IllegalArgumentException", "Invalid render-target readback request");
			return nullptr;
		}
		auto request = std::make_shared<ReadbackRequest>();
		request->handle = uint64_t(handle); request->sequence = uint64_t(sequence);
		request->x = x; request->y = y; request->width = width; request->height = height;
		std::unique_lock<std::mutex> lock(jni_runtime->readback_mutex);
		if (jni_runtime->readbacks_stopped) return nullptr;
		if (jni_runtime->readback) {
			throw_java(env, "java/lang/IllegalStateException", "A render-target readback is already pending");
			return nullptr;
		}
		jni_runtime->readback = request;
		bool ready = jni_runtime->readback_changed.wait_for(lock, std::chrono::seconds(10), [&] {
			return request->done || jni_runtime->readbacks_stopped;
		});
		jni_runtime->readback.reset();
		if (jni_runtime->readbacks_stopped) return nullptr;
		if (!ready) {
			throw_java(env, "java/lang/IllegalStateException", "Timed out waiting for render-target readback");
			return nullptr;
		}
		if (!request->error.empty()) {
			throw_java(env, "java/lang/IllegalArgumentException", request->error.c_str());
			return nullptr;
		}
		jintArray result = env->NewIntArray(jsize(request->pixels.size()));
		if (result) env->SetIntArrayRegion(result, 0, jsize(request->pixels.size()), request->pixels.data());
		return result;
	} catch (const std::bad_alloc &) {
		throw_java(env, "java/lang/OutOfMemoryError", "Cannot allocate render-target readback");
		return nullptr;
	}
}

static jdoubleArray drain_input(JNIEnv *env, int stride) {
	JniSample sample(jni_runtime->metadata_jni_calls, jni_runtime->metadata_jni_us);
	std::lock_guard<std::mutex> lock(jni_runtime->host_mutex);
	const size_t count = jni_runtime->input_events.size();
	jdoubleArray result = env->NewDoubleArray(jsize(count * stride));
	if (!result) return nullptr;
	for (size_t i = 0; i < count; ++i) {
		env->SetDoubleArrayRegion(result, jsize(i * stride), stride, jni_runtime->input_events[i].data());
	}
	jni_runtime->input_events.clear();
	return result;
}
static jdoubleArray JNICALL poll_input(JNIEnv *env, jclass) { return drain_input(env, 9); }
static jdoubleArray JNICALL poll_window_input(JNIEnv *env, jclass) { return drain_input(env, 12); }

static void JNICALL dialog_submit(JNIEnv *env,jclass,jlong owner,jint mode,jstring folder,jstring filename,jstring title,jobjectArray filters,jint selected) {
    platform_dialogs::submit(env,jni_runtime->dialogs,owner,mode,folder,filename,title,filters,selected);
}
static jobjectArray JNICALL dialog_poll(JNIEnv *env,jclass) { return platform_dialogs::poll(env,jni_runtime->dialogs); }
static void JNICALL dialog_cancel(JNIEnv *,jclass) { jni_runtime->dialogs.cancel(); }

static jstring JNICALL clipboard_read_text(JNIEnv *env, jclass) {
    return platform_clipboard::read(env, jni_runtime->clipboard_owner);
}
static void JNICALL clipboard_write_formats(JNIEnv *env, jclass, jstring text, jbyteArray html, jbyteArray rtf) {
    platform_clipboard::write(env, jni_runtime->clipboard_owner, text, html, rtf);
}
static void JNICALL clipboard_write_url_formats(JNIEnv *env, jclass, jstring text, jbyteArray html, jbyteArray rtf, jstring url) {
    platform_clipboard::write(env, jni_runtime->clipboard_owner, text, html, rtf, url);
}
static jstring JNICALL clipboard_read_url(JNIEnv *env, jclass) {
    try {
        return platform_clipboard::read_url(env, jni_runtime->clipboard_owner);
    } catch (const std::bad_alloc &) {
        throw_java(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr;
    }
}
static jbyteArray JNICALL clipboard_read_rich(JNIEnv *env, jclass, jint kind) {
    return platform_clipboard::read_rich(env, jni_runtime->clipboard_owner, kind);
}
static void JNICALL clipboard_write_full(JNIEnv *env, jclass, jstring text, jbyteArray html, jbyteArray rtf, jstring url,
        jobjectArray files, jintArray image, jint image_w, jint image_h, jobjectArray custom_names, jobjectArray custom_data) {
    try {
        platform_clipboard::write_full(env, jni_runtime->clipboard_owner, text, html, rtf, url, files, image, image_w, image_h,
                custom_names, custom_data);
    } catch (const std::bad_alloc &) {
        throw_java(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed");
    }
}
static jbyteArray JNICALL clipboard_read_custom(JNIEnv *env, jclass, jstring name) {
    try {
        return platform_clipboard::read_custom(env, jni_runtime->clipboard_owner, name);
    } catch (const std::bad_alloc &) {
        throw_java(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr;
    }
}
static jobjectArray JNICALL clipboard_custom_formats(JNIEnv *env, jclass) {
    try {
        return platform_clipboard::custom_formats(env, jni_runtime->clipboard_owner);
    } catch (const std::bad_alloc &) {
        throw_java(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr;
    }
}
static jobjectArray JNICALL clipboard_read_files(JNIEnv *env, jclass) {
    try {
        return platform_clipboard::read_files(env, jni_runtime->clipboard_owner);
    } catch (const std::bad_alloc &) {
        throw_java(env, "java/lang/OutOfMemoryError", "Clipboard allocation failed"); return nullptr;
    }
}
static jintArray JNICALL clipboard_read_image(JNIEnv *env, jclass) {
    return platform_clipboard::read_image(env, jni_runtime->clipboard_owner);
}
static jint JNICALL clipboard_formats(JNIEnv *, jclass) {
#if defined(WINDOWS_ENABLED)
    jint result=IsClipboardFormatAvailable(CF_UNICODETEXT) ? 1 : 0;
    UINT url=RegisterClipboardFormatW(L"UniformResourceLocatorW");
    if (url && IsClipboardFormatAvailable(url)) result |= 8;
    else {
        UINT ansi_url=RegisterClipboardFormatW(L"UniformResourceLocator");
        if (ansi_url && IsClipboardFormatAvailable(ansi_url)) result |= 8;
    }
    for (int kind=0;kind<2;++kind) {
        UINT format=platform_clipboard::rich_format(kind);
        if (format && IsClipboardFormatAvailable(format)) result |= 2 << kind;
    }
    if (IsClipboardFormatAvailable(CF_HDROP)) result |= 16;
    if (IsClipboardFormatAvailable(CF_DIB)) result |= 32;
    return result;
#elif defined(MACOS_ENABLED)
    return platform_clipboard::formats();
#endif
}
static void JNICALL drag_start_external(JNIEnv *env, jclass, jstring text, jbyteArray html, jbyteArray rtf,
        jstring url, jobjectArray files, jobjectArray custom_names, jobjectArray custom_data,
        jbyteArray drag_image, jbyteArray drag_image_offset, jint effects, jint buttons, jlong source_id) try {
    // Runs on the FX thread. The request is consumed by the Godot main thread,
    // which owns every hosted HWND and runs the modal OLE loop.
    if (effects < 1 || effects > 7 || buttons < 0 || buttons > 14 || (buttons & 1) || source_id < 0) {
        throw_java(env, "java/lang/IllegalArgumentException", "Invalid external drag request");
        return;
    }
    std::unique_ptr<platform_dnd::SourceData> data;
    try { data = std::make_unique<platform_dnd::SourceData>(); }
    catch (const std::bad_alloc &) { throw_java(env, "java/lang/OutOfMemoryError", "External drag allocation failed"); return; }
    data->effects = uint32_t(effects);
    data->buttons = buttons;
    data->source_id = source_id;
    const std::array<jstring, 2> strings = { text, url };
    for (size_t index = 0; index < strings.size(); ++index) {
        jstring value = strings[index];
        if (!value) continue;
        jsize length = env->GetStringLength(value);
        if (length < 0 || size_t(length) > (index == 0 ? platform_dnd::MAX_TEXT_BYTES / sizeof(jchar) : platform_dnd::MAX_URL_CHARS)) {
            throw_java(env, "java/lang/IllegalArgumentException", "External drag text exceeds its limit");
            return;
        }
        auto &target = index == 0 ? data->text : data->url;
        target.resize(length);
        if (length) env->GetStringRegion(value, 0, length, reinterpret_cast<jchar *>(target.data()));
        if (env->ExceptionCheck()) return;
        for (jsize i = 0; i < length; ++i) {
            if (!target[i]) { throw_java(env, "java/lang/IllegalArgumentException", "External drag text contains NUL"); return; }
        }
    }
    const std::array<jbyteArray, 2> rich = { html, rtf };
    for (size_t i = 0; i < rich.size(); ++i) {
        if (!rich[i]) continue;
        jsize length = env->GetArrayLength(rich[i]);
        if (length < 1 || size_t(length) > platform_dnd::MAX_TEXT_BYTES) {
            throw_java(env, "java/lang/IllegalArgumentException", "External drag rich data must be NUL-terminated and at most 16 MiB");
            return;
        }
        auto &target = i == 0 ? data->html : data->rtf;
        target.resize(length);
        env->GetByteArrayRegion(rich[i], 0, length, reinterpret_cast<jbyte *>(target.data()));
        if (env->ExceptionCheck()) return;
        bool valid = target[length - 1] == 0;
        for (jsize p = 0; p < length - 1; ++p) valid &= target[p] != 0;
        if (!valid) { throw_java(env, "java/lang/IllegalArgumentException", "Invalid NUL in external drag rich data"); return; }
    }
    if (files) {
        jsize count = env->GetArrayLength(files);
        if (count < 0 || size_t(count) > platform_dnd::MAX_PATHS) {
            throw_java(env, "java/lang/IllegalArgumentException", "External drag file list exceeds its limit");
            return;
        }
        try { data->files.reserve(count); }
        catch (const std::bad_alloc &) { throw_java(env, "java/lang/OutOfMemoryError", "External drag allocation failed"); return; }
        for (jsize i = 0; i < count; ++i) {
            auto path = reinterpret_cast<jstring>(env->GetObjectArrayElement(files, i));
            if (!path) {
                if (!env->ExceptionCheck()) throw_java(env, "java/lang/IllegalArgumentException", "External drag file list contains null");
                return;
            }
            jsize length = env->GetStringLength(path);
            if (size_t(length) > platform_dnd::MAX_PATH_CHARS) {
                env->DeleteLocalRef(path);
                throw_java(env, "java/lang/IllegalArgumentException", "External drag path exceeds its limit");
                return;
            }
            std::u16string value(size_t(length), 0);
            if (length) env->GetStringRegion(path, 0, length, reinterpret_cast<jchar *>(value.data()));
            env->DeleteLocalRef(path);
            if (env->ExceptionCheck()) return;
            bool clean = true;
            for (char16_t c : value) clean &= c != 0 && c != u'\n';
            if (!clean || value.empty()) { throw_java(env, "java/lang/IllegalArgumentException", "Invalid external drag path"); return; }
            try { data->files.push_back(std::move(value)); }
            catch (const std::bad_alloc &) { throw_java(env, "java/lang/OutOfMemoryError", "External drag allocation failed"); return; }
        }
    }
    if (custom_names || custom_data) {
        const jsize count = custom_names ? env->GetArrayLength(custom_names) : 0;
        if (!custom_names || !custom_data || count != env->GetArrayLength(custom_data)
                || size_t(count) > custom_format::MAX_FORMATS) {
            throw_java(env, "java/lang/IllegalArgumentException", "External drag custom formats require matching name/data arrays (at most 32)");
            return;
        }
        for (jsize i = 0; i < count; ++i) {
            auto name = reinterpret_cast<jstring>(env->GetObjectArrayElement(custom_names, i));
            auto payload = reinterpret_cast<jbyteArray>(env->GetObjectArrayElement(custom_data, i));
            if (!name || !payload) {
                if (name) env->DeleteLocalRef(name);
                if (payload) env->DeleteLocalRef(payload);
                if (!env->ExceptionCheck()) throw_java(env, "java/lang/IllegalArgumentException", "External drag custom formats contain null");
                return;
            }
            const jsize name_length = env->GetStringLength(name);
            platform_dnd::wide_string wide(size_t(name_length), 0);
            if (name_length) env->GetStringRegion(name, 0, name_length, reinterpret_cast<jchar *>(wide.data()));
            env->DeleteLocalRef(name);
            if (env->ExceptionCheck()) { env->DeleteLocalRef(payload); return; }
            if (!custom_format::valid_name(wide)) {
                env->DeleteLocalRef(payload);
                throw_java(env, "java/lang/IllegalArgumentException", "External drag custom format name outside the application/x-godot-custom- convention");
                return;
            }
            bool duplicate = false;
            for (const auto &entry : data->custom) duplicate |= entry.first == wide;
            if (duplicate) {
                env->DeleteLocalRef(payload);
                throw_java(env, "java/lang/IllegalArgumentException", "Duplicate external drag custom format");
                return;
            }
            const jsize length = env->GetArrayLength(payload);
            if (length < 1 || size_t(length) > custom_format::MAX_DATA_BYTES) {
                env->DeleteLocalRef(payload);
                throw_java(env, "java/lang/IllegalArgumentException", "External drag custom data must be NUL-terminated and at most 16 MiB");
                return;
            }
            std::string bytes(size_t(length), 0);
            env->GetByteArrayRegion(payload, 0, length, reinterpret_cast<jbyte *>(bytes.data()));
            env->DeleteLocalRef(payload);
            if (env->ExceptionCheck()) return;
            bool valid = bytes[length - 1] == 0;
            for (jsize p = 0; p < length - 1; ++p) valid &= bytes[p] != 0;
            if (!valid) { throw_java(env, "java/lang/IllegalArgumentException", "Invalid NUL in external drag custom data"); return; }
            try { data->custom.emplace_back(std::move(wide), std::move(bytes)); }
            catch (const std::bad_alloc &) { throw_java(env, "java/lang/OutOfMemoryError", "External drag allocation failed"); return; }
        }
    }
    // Optional drag view: 8-byte big-endian width/height envelope followed by
    // w*h*4 BGRA bytes, exactly as the Quantum layer publishes it. Offsets are
    // a second 8-byte big-endian pair; absent offsets keep the image-center
    // default applied by apply_drag_image.
    if (drag_image) {
        jsize length = env->GetArrayLength(drag_image);
        if (length < 8) { throw_java(env, "java/lang/IllegalArgumentException", "External drag image lacks its header"); return; }
        std::vector<uint8_t> bytes(size_t(length), 0);
        env->GetByteArrayRegion(drag_image, 0, length, reinterpret_cast<jbyte *>(bytes.data()));
        if (env->ExceptionCheck()) return;
        auto be32 = [&bytes](size_t offset) {
            return uint32_t(bytes[offset]) << 24 | uint32_t(bytes[offset + 1]) << 16
                    | uint32_t(bytes[offset + 2]) << 8 | uint32_t(bytes[offset + 3]);
        };
        uint32_t w = be32(0), h = be32(4);
        if (w == 0 || h == 0 || w > (UINT_MAX / 4) / h) {
            throw_java(env, "java/lang/IllegalArgumentException", "External drag image dimensions are invalid");
            return;
        }
        uint64_t pixel_bytes = uint64_t(w) * h * 4;
        if (uint64_t(length) < 8 + pixel_bytes) {
            throw_java(env, "java/lang/IllegalArgumentException", "External drag image is truncated");
            return;
        }
        try {
            data->image.width = w;
            data->image.height = h;
            data->image.bgra.assign(bytes.data() + 8, bytes.data() + 8 + pixel_bytes);
        } catch (const std::bad_alloc &) {
            throw_java(env, "java/lang/OutOfMemoryError", "External drag allocation failed"); return;
        }
        if (drag_image_offset) {
            jsize offset_length = env->GetArrayLength(drag_image_offset);
            if (offset_length < 8) { throw_java(env, "java/lang/IllegalArgumentException", "External drag image offset lacks its header"); return; }
            std::vector<uint8_t> offsets(size_t(offset_length), 0);
            env->GetByteArrayRegion(drag_image_offset, 0, offset_length, reinterpret_cast<jbyte *>(offsets.data()));
            if (env->ExceptionCheck()) return;
            auto be_off = [&offsets](size_t offset) {
                int32_t value = int32_t(uint32_t(offsets[offset]) << 24 | uint32_t(offsets[offset + 1]) << 16
                        | uint32_t(offsets[offset + 2]) << 8 | uint32_t(offsets[offset + 3]));
                return value;
            };
            data->image.offset_x = be_off(0);
            data->image.offset_y = be_off(4);
        }
    }
    if (data->text.empty() && data->html.empty() && data->rtf.empty() && data->url.empty() && data->files.empty() && data->custom.empty()) {
        throw_java(env, "java/lang/IllegalArgumentException", "External drag carries no data");
        return;
    }
    std::lock_guard<std::mutex> lock(jni_runtime->dnd_mutex);
    if (jni_runtime->dnd_pending) {
        throw_java(env, "java/lang/IllegalStateException", "An external drag is already pending");
        return;
    }
    jni_runtime->dnd_pending = std::move(data);
} catch (const std::bad_alloc &) {
    // JNI releases local references when this native call returns. All owned
    // native payloads unwind before reporting failure; nothing was published.
    throw_java(env, "java/lang/OutOfMemoryError", "External drag allocation failed");
}

// Library callers may outlive the SceneTree. Close admission before waiting
// for outstanding JNI operations, after waking queue and readback waiters.
template <auto Method, bool TickWait> struct GuardedBridgeMethod;
template <bool TickWait, typename Result, typename... Args, Result (JNICALL *Method)(JNIEnv *, jclass, Args...)>
struct GuardedBridgeMethod<Method, TickWait> {
    static Result JNICALL invoke(JNIEnv *env, jclass type, Args... args) {
        std::shared_lock lock(bridge_lifetime);
        if (!bridge_open.load()) {
            if constexpr (TickWait) return -1;
            throw_java(env, "java/lang/IllegalStateException", "Godot host is stopped");
            return Result();
        }
        return Method(env, type, args...);
    }
};

template <auto Method, bool TickWait = false> static void *bridge_method() {
    return reinterpret_cast<void *>(&GuardedBridgeMethod<Method, TickWait>::invoke);
}

static void register_bridge(std::shared_ptr<Runtime> runtime, JavaVM *vm, JNIEnv *env, jclass bridge) {
	JNINativeMethod methods[] = {
        { const_cast<char *>("dialogSubmit"), const_cast<char *>("(JILjava/lang/String;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;I)V"), bridge_method<&dialog_submit>() },
        { const_cast<char *>("dialogPoll"), const_cast<char *>("()[Ljava/lang/String;"), bridge_method<&dialog_poll>() },
        { const_cast<char *>("dialogCancel"), const_cast<char *>("()V"), bridge_method<&dialog_cancel>() },
        { const_cast<char *>("robotMove"), const_cast<char *>("(II)V"), bridge_method<&platform_robot::move>() },
        { const_cast<char *>("robotPosition"), const_cast<char *>("()[I"), bridge_method<&platform_robot::position>() },
        { const_cast<char *>("robotCapture"), const_cast<char *>("(IIII)[I"), bridge_method<&platform_robot::capture>() },
        { const_cast<char *>("clipboardWriteFormats"), const_cast<char *>("(Ljava/lang/String;[B[B)V"), bridge_method<&clipboard_write_formats>() },
        { const_cast<char *>("clipboardWriteUrlFormats"), const_cast<char *>("(Ljava/lang/String;[B[BLjava/lang/String;)V"), bridge_method<&clipboard_write_url_formats>() },
        { const_cast<char *>("clipboardReadUrl"), const_cast<char *>("()Ljava/lang/String;"), bridge_method<&clipboard_read_url>() },
        { const_cast<char *>("clipboardReadRich"), const_cast<char *>("(I)[B"), bridge_method<&clipboard_read_rich>() },
        { const_cast<char *>("clipboardWriteFull"), const_cast<char *>("(Ljava/lang/String;[B[BLjava/lang/String;[Ljava/lang/String;[III[Ljava/lang/String;[[B)V"), bridge_method<&clipboard_write_full>() },
        { const_cast<char *>("clipboardReadFiles"), const_cast<char *>("()[Ljava/lang/String;"), bridge_method<&clipboard_read_files>() },
        { const_cast<char *>("clipboardReadImage"), const_cast<char *>("()[I"), bridge_method<&clipboard_read_image>() },
        { const_cast<char *>("clipboardReadCustom"), const_cast<char *>("(Ljava/lang/String;)[B"), bridge_method<&clipboard_read_custom>() },
        { const_cast<char *>("clipboardCustomFormats"), const_cast<char *>("()[Ljava/lang/String;"), bridge_method<&clipboard_custom_formats>() },
        { const_cast<char *>("clipboardFormats"), const_cast<char *>("()I"), bridge_method<&clipboard_formats>() },
		{ const_cast<char *>("windowIcon"), const_cast<char *>("(JII[B)J"), bridge_method<&window_icon>() },
		{ const_cast<char *>("customCursor"), const_cast<char *>("(IIII[B)I"), bridge_method<&custom_cursor>() },
		{ const_cast<char *>("readPixels"), const_cast<char *>("(JJIIII)[I"), bridge_method<&read_pixels>() },
		{ const_cast<char *>("nativeWindowCommand"), const_cast<char *>("(JJIIIIIIZLjava/lang/String;)J"), bridge_method<&native_window_command>() },
		{ const_cast<char *>("nativeWindowInfo"), const_cast<char *>("(J)[J"), bridge_method<&native_window_info>() },
		{ const_cast<char *>("nativeWindowAck"), const_cast<char *>("()J"), bridge_method<&native_window_ack>() },
		{ const_cast<char *>("isShutdownDrained"), const_cast<char *>("()Z"), bridge_method<&is_shutdown_drained>() },
		{ const_cast<char *>("submit"), const_cast<char *>("(Ljava/nio/ByteBuffer;I)Z"), bridge_method<&submit>() },
		{ const_cast<char *>("awaitTick"), const_cast<char *>("(JI)J"), bridge_method<&await_tick, true>() },
		{ const_cast<char *>("awaitFrameTick"), const_cast<char *>("(JI)J"), bridge_method<&await_frame_tick, true>() },
		{ const_cast<char *>("awaitInputTick"), const_cast<char *>("(JI)J"), bridge_method<&await_input_tick, true>() },
		{ const_cast<char *>("hostInfo"), const_cast<char *>("()[I"), bridge_method<&host_info>() },
		{ const_cast<char *>("screenInfo"), const_cast<char *>("()[I"), bridge_method<&screen_info>() },
		{ const_cast<char *>("hostCommand"), const_cast<char *>("(IIILjava/lang/String;)I"), bridge_method<&host_command>() },
        { const_cast<char *>("pollInput"), const_cast<char *>("()[D"), bridge_method<&poll_input>() },
		{ const_cast<char *>("pollWindowInputV2"), const_cast<char *>("()[D"), bridge_method<&poll_window_input>() },
        { const_cast<char *>("clipboardReadText"), const_cast<char *>("()Ljava/lang/String;"), bridge_method<&clipboard_read_text>() },
        { const_cast<char *>("dragStartExternal"), const_cast<char *>("(Ljava/lang/String;[B[BLjava/lang/String;[Ljava/lang/String;[Ljava/lang/String;[[B[B[BIIJ)V"), bridge_method<&drag_start_external>() }
	};
    if (!bridge || env->RegisterNatives(bridge, methods, sizeof(methods) / sizeof(methods[0])) != JNI_OK) {
		if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); }
		runtime->fail("Cannot register GodotBridge in the source-built JavaFX graphics module");
	} else {
		// OLE drag target callbacks on the Godot main thread re-enter Java through
		// this one static method; keep a global reference for the VM lifetime.
		jclass bridge_global = reinterpret_cast<jclass>(env->NewGlobalRef(bridge));
		jmethodID drag_callback = bridge_global
				? env->GetStaticMethodID(bridge, "dragTargetCallback", "(IJIIIILjava/lang/String;Ljava/lang/String;[B[BLjava/lang/String;Ljava/lang/String;[Ljava/lang/String;[[B)I")
				: nullptr;
		if (!bridge_global || !drag_callback) {
			if (env->ExceptionCheck()) { env->ExceptionDescribe(); env->ExceptionClear(); }
			if (bridge_global) env->DeleteGlobalRef(bridge_global);
			runtime->fail("Cannot resolve the GodotBridge drag/drop target callback");
		} else {
			runtime->drag_upcall.publish(vm, bridge_global, drag_callback);
		}
	}
    if (runtime->status.load() != RuntimeStatus::FAILED) {
        jni_runtime = runtime.get();
        bridge_open.store(true);
    }
}

static void invoke_fixture_probe(std::shared_ptr<Runtime> runtime, JNIEnv *env, const std::string &main_class) {
	if (runtime->status.load() != RuntimeStatus::FAILED) {
		jclass fixture = env->FindClass("com/sun/javafx/tk/godot/GodotSceneFixture");
		jmethodID launch = fixture ? env->GetStaticMethodID(fixture, "runProbe", "(Ljava/lang/String;)V") : nullptr;
		jstring name = launch ? env->NewStringUTF(main_class.c_str()) : nullptr;
		if (launch && name) {
			runtime->status.store(RuntimeStatus::RUNNING);
			runtime->fixture_probe_calls.fetch_add(1, std::memory_order_relaxed);
			env->CallStaticVoidMethod(fixture, launch, name);
		}
		if (env->ExceptionCheck()) {
			env->ExceptionDescribe();
			env->ExceptionClear();
			runtime->fail("Java application failed; see JVM exception in the host log");
		}
		if (name) env->DeleteLocalRef(name);
	}
}

// Only the thread driving a scene fixture can lend its JVM to a scene-owned host.
thread_local JNIEnv *scene_env = nullptr;

static void run_scene_application(std::shared_ptr<Runtime> runtime, JavaVM *vm, std::string main_class) {
	JNIEnv *env = nullptr;
	JavaVMAttachArgs args{ JNI_VERSION_1_8, const_cast<char *>("main"), nullptr };
	if (vm->AttachCurrentThread(reinterpret_cast<void **>(&env), &args) != JNI_OK) {
		runtime->fail("Could not attach scene application thread");
		return;
	}
	jclass bridge = env->FindClass("com/sun/javafx/tk/godot/GodotBridge");
	register_bridge(runtime, vm, env, bridge);
	invoke_fixture_probe(runtime, env, main_class);
	if (runtime->status.load() == RuntimeStatus::FAILED) {
		runtime->queue.stop();
		runtime->native_window_transport.stop();
	} else {
		runtime->queue.finish();
		runtime->native_window_transport.finish();
	}
	bridge_open.store(false);
	if (jclass retained = runtime->drag_upcall.close()) env->DeleteGlobalRef(retained);
	{
		std::unique_lock lock(bridge_lifetime);
		jni_runtime = nullptr;
	}
	vm->DetachCurrentThread();
	if (runtime->status.load() != RuntimeStatus::FAILED) runtime->status.store(RuntimeStatus::FINISHED);
}

} // namespace godot_javafx

void JavaFXHost::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_startup_status"), &JavaFXHost::get_startup_status);
	ClassDB::bind_method(D_METHOD("create_native_window", "id", "owner", "bounds", "title", "flags"), &JavaFXHost::create_native_window);
	ClassDB::bind_method(D_METHOD("configure_native_window", "id", "bounds", "visible"), &JavaFXHost::configure_native_window);
	ClassDB::bind_method(D_METHOD("get_native_window_info", "id"), &JavaFXHost::get_native_window_info);
	ClassDB::bind_method(D_METHOD("get_native_window", "id"), &JavaFXHost::get_native_window);
	ClassDB::bind_method(D_METHOD("destroy_native_window", "id"), &JavaFXHost::destroy_native_window);
	ClassDB::bind_method(D_METHOD("get_native_window_count"), &JavaFXHost::get_native_window_count);
	ClassDB::bind_method(D_METHOD("is_window_input_enabled", "id"), &JavaFXHost::is_window_input_enabled);
	ClassDB::bind_method(D_METHOD("is_window_visible", "id"), &JavaFXHost::is_window_visible);
	ClassDB::bind_method(D_METHOD("is_window_above", "id", "other"), &JavaFXHost::is_window_above);
	ClassDB::bind_method(D_METHOD("run_fixture_probe", "main_class"), &JavaFXHost::run_fixture_probe);
	ClassDB::bind_method(D_METHOD("stop_host"), &JavaFXHost::stop_host);
	ClassDB::bind_method(D_METHOD("get_runtime_status"), &JavaFXHost::get_runtime_status);
	ClassDB::bind_method(D_METHOD("is_ime_active"), &JavaFXHost::is_ime_active);
	ClassDB::bind_method(D_METHOD("update_ime_composition", "text", "caret"), &JavaFXHost::update_ime_composition);
	ClassDB::bind_method(D_METHOD("update_window_ime_composition", "id", "text", "caret"), &JavaFXHost::update_window_ime_composition);
	ClassDB::bind_method(D_METHOD("get_completed_presentations"), &JavaFXHost::get_completed_presentations);
	ClassDB::bind_method(D_METHOD("get_runtime_error"), &JavaFXHost::get_runtime_error);
	ClassDB::bind_method(D_METHOD("get_applied_sequence"), &JavaFXHost::get_applied_sequence);
	ClassDB::bind_method(D_METHOD("get_backpressure_count"), &JavaFXHost::get_backpressure_count);
	ClassDB::bind_method(D_METHOD("get_render_stats"), &JavaFXHost::get_render_stats);
	ClassDB::bind_method(D_METHOD("has_pending_readback"), &JavaFXHost::has_pending_readback);
	ClassDB::bind_method(D_METHOD("get_custom_cursor_info"), &JavaFXHost::get_custom_cursor_info);
	ClassDB::bind_method(D_METHOD("get_window_icon_info", "id"), &JavaFXHost::get_window_icon_info);
	ClassDB::bind_method(D_METHOD("simulate_external_drop", "point", "text", "url", "files", "custom_name", "custom_data"), &JavaFXHost::simulate_external_drop);
}

bool JavaFXHost::has_pending_readback() const {
	if (!runtime) return false;
	std::lock_guard<std::mutex> lock(runtime->readback_mutex);
	return runtime->readback && !runtime->readback->done && !runtime->readbacks_stopped;
}

Dictionary JavaFXHost::get_render_stats() const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), Dictionary());
	Dictionary stats;
	stats["host_ticks"] = process_ticks;
	stats["offscreen_passes"] = offscreen_passes;
	stats["immediate_passes"] = immediate_passes;
	stats["quads_uploaded"] = quads_uploaded;
	stats["quads_referenced"] = quads_referenced;
	stats["direct_offscreen_calls"] = direct_offscreen_calls;
	stats["direct_offscreen_us"] = direct_offscreen_us;
	stats["direct_offscreen_render_us"] = direct_offscreen_render_us;
	stats["direct_presentation_passes"] = direct_presentation_passes;
	stats["presentations"] = completed_presentations;
	stats["applied_sequence"] = applied_sequence;
	stats["backpressure"] = get_backpressure_count();
	stats["process_us"] = process_us;
	stats["encode_us"] = encode_us;
	stats["metadata_us"] = metadata_us;
	stats["host_commands_us"] = host_commands_us;
	stats["draw_sync_us"] = draw_sync_us;
	stats["draw_sync_calls"] = draw_sync_calls;
	stats["max_draw_sync_us"] = max_draw_sync_us;
	if (profile_commands) {
		stats.merge(get_texture_patch_profile());
		stats.merge(JavaFXRenderTarget::get_render_thread_profile());
		stats["profile_texture_us"] = profile_texture_us;
		stats["profile_target_us"] = profile_target_us;
		stats["profile_geometry_us"] = profile_geometry_us;
		if (gpu_timing_enabled) {
			// Last-measured GPU time of offscreen targets; a gauge, not a counter.
			stats["offscreen_gpu_us"] = get_offscreen_gpu_time_us();
		}
		stats["profile_shader_us"] = profile_shader_us;
		stats["profile_shader_creations"] = profile_shader_creations;
	}
	if (runtime) {
		stats["completed_render_sequence"] = runtime->completed_render_sequence.load();
		stats["jni_submit_calls"] = runtime->submit_calls.load();
		stats["jni_submit_us"] = runtime->submit_us.load();
		stats["jni_tick_wait_calls"] = runtime->tick_wait_calls.load();
		stats["jni_tick_wait_us"] = runtime->tick_wait_us.load(); // Wall wait across threads, not CPU cost.
		stats["jni_metadata_calls"] = runtime->metadata_jni_calls.load();
		stats["jni_metadata_us"] = runtime->metadata_jni_us.load();
		stats["fixture_probe_calls"] = runtime->fixture_probe_calls.load();
	}
	return stats;
}

void JavaFXHost::prepare_runtime(const String &startup) {
	runtime = std::make_shared<godot_javafx::Runtime>();
	profile_commands = OS::get_singleton()->get_environment("GODOT_JFX_PROFILE_COMMANDS") == "1";
	gpu_timing_enabled = OS::get_singleton()->get_environment("GODOT_JFX_GPU_TIMING") == "1";
    runtime->clipboard_owner = reinterpret_cast<godot_javafx::OsNativeWindow>(DisplayServer::get_singleton()->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE));
	previous_auto_accept_quit = get_tree()->is_auto_accept_quit();
	get_tree()->set_auto_accept_quit(false);
	refresh_host_info();
	previous_default_cursor_shape = int(Input::get_singleton()->get_default_cursor_shape());
	default_cursor_state_saved = true;
	startup_enabled = startup == "logo" || startup == "hidden";
	startup_logo_enabled = startup == "logo";
	set_process(true);
	set_process_input(true);
}

bool JavaFXHost::connect_jvm(JNIEnv *env, jclass bridge, const String &startup) {
    ERR_FAIL_COND_V(!Thread::is_main_thread() || !is_inside_tree() || runtime, false);
    ERR_FAIL_COND_V(!RenderingServer::get_singleton()->is_on_render_thread(), false);
    JavaVM *vm = nullptr;
    if (env->GetJavaVM(&vm) != JNI_OK) return false;
    borrowed_vm = vm;
    prepare_runtime(startup);
    godot_javafx::register_bridge(runtime, vm, env, bridge);
    if (runtime->status.load() == godot_javafx::RuntimeStatus::FAILED) return false;
    runtime->status.store(godot_javafx::RuntimeStatus::RUNNING);
    return true;
}

bool JavaFXHost::claim_library() {
    return !godot_javafx::library_claimed.exchange(true);
}

bool JavaFXHost::run_fixture_probe(const String &p_main_class) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || !is_inside_tree() || runtime, false);
	ERR_FAIL_COND_V_MSG(!RenderingServer::get_singleton()->is_on_render_thread(), false,
			"JavaFX hosting requires --render-thread safe; separate is unsupported.");
	JNIEnv *env = godot_javafx::scene_env;
	ERR_FAIL_NULL_V_MSG(env, false, "A probe requires the Java scene fixture launcher.");
	ERR_FAIL_COND_V(godot_javafx::probe_started.exchange(true), false);
	JavaVM *vm = nullptr;
	ERR_FAIL_COND_V(env->GetJavaVM(&vm) != JNI_OK, false);
	prepare_runtime(OS::get_singleton()->get_environment("GODOT_JFX_STARTUP"));
	worker = std::thread(godot_javafx::run_scene_application, runtime, vm, std::string(p_main_class.utf8().get_data()));
	return true;
}

void JavaFXHost::input(const Ref<InputEvent> &p_event) {
	window_input(p_event, 0);
}

void JavaFXHost::window_input(const Ref<InputEvent> &p_event, int64_t p_id) {
	if (startup_active && startup_window_id == p_id) return;
	if (!runtime || runtime->status.load() != godot_javafx::RuntimeStatus::RUNNING) return;
	Window *source = p_id ? get_native_window(p_id) : get_window();
	if (!source) return;
	Ref<InputEventScreenTouch> touch = p_event;
	Ref<InputEventScreenDrag> drag = p_event;
	if (touch.is_valid() || drag.is_valid()) {
		Vector2 position = touch.is_valid() ? touch->get_position() : drag->get_position();
		int index = touch.is_valid() ? touch->get_index() : drag->get_index();
		Point2i origin = source->get_position();
		std::lock_guard<std::mutex> lock(runtime->host_mutex);
		if (runtime->input_events.size() >= 4096) { runtime->fail("Glass touch input queue overflow"); return; }
		runtime->input_events.push_back({touch.is_valid() ? (touch->is_pressed() ? 10.0 : 12.0) : 11.0,
			double(index),position.x,position.y,origin.x+position.x,origin.y+position.y,0,0,0,double(p_id)});
		runtime->queue.pulse_input();
		return;
	}
	Ref<InputEventKey> key = p_event;
	if (key.is_valid()) {
		int modifiers = (key->is_shift_pressed() ? 1 : 0) | (key->is_ctrl_pressed() ? 4 : 0) |
			(key->is_alt_pressed() ? 8 : 0) | (key->is_meta_pressed() ? 16 : 0);
		std::lock_guard<std::mutex> lock(runtime->host_mutex);
		if (runtime->input_events.size() >= 4096) {
			runtime->fail("Glass input queue overflow; input cannot be silently dropped");
			return;
		}
		runtime->input_events.push_back({ key->is_pressed() ? 5.0 : 6.0, double(key->get_keycode()),
			double(key->get_unicode()), 0, 0, 0, double(modifiers), key->is_echo() ? 1.0 : 0.0, 0, double(p_id) });
		runtime->queue.pulse_input();
		return;
	}
#if defined(MACOS_ENABLED)
	Ref<InputEventPanGesture> pan = p_event;
	if (pan.is_valid()) {
		// Native mac Glass reports trackpad two-finger scrolling through the
		// scroll-gesture path: precise point deltas scaled by 0.1 with a 10px
		// Java-side multiplier (GlassViewDelegate, MacGestureSupport). Godot
		// delivers the same points, negated, via InputEventPanGesture. Godot
		// carries no gesture phase or momentum flags, so only the performed
		// (SCROLL) stage can be reported, without inertia marking.
		std::array<double, 12> event{};
		event[0] = 17;
		Vector2 pos = pan->get_position();
		Point2i origin = source->get_position();
		event[2] = pos.x; event[3] = pos.y;
		event[4] = origin.x + pos.x; event[5] = origin.y + pos.y;
		event[6] = (pan->is_shift_pressed() ? 1 : 0) | (pan->is_ctrl_pressed() ? 4 : 0) |
			(pan->is_alt_pressed() ? 8 : 0) | (pan->is_meta_pressed() ? 16 : 0);
		Vector2 delta = pan->get_delta();
		event[7] = -delta.x * 0.1;
		event[8] = -delta.y * 0.1;
		event[9] = double(p_id);
		std::lock_guard<std::mutex> lock(runtime->host_mutex);
		if (runtime->input_events.size() >= 4096) {
			runtime->fail("Glass input queue overflow; input cannot be silently dropped");
			return;
		}
		runtime->input_events.push_back(event);
		runtime->queue.pulse_input();
		return;
	}
#endif
	Ref<InputEventMouse> mouse = p_event;
	if (mouse.is_null()) return;
	// Glass-Godot promotes touches to mouse events. Do not send a second
	// copy synthesized by Godot's Input singleton.
	if (mouse->get_device() == InputEvent::DEVICE_ID_EMULATION) return;
	std::array<double, 12> event{};
	event[9] = double(p_id);
	Vector2 pos = mouse->get_position();
	Point2i origin = source->get_position();
	event[2] = pos.x; event[3] = pos.y;
	event[4] = origin.x + pos.x; event[5] = origin.y + pos.y;
	int modifiers = (mouse->is_shift_pressed() ? 1 : 0) | (mouse->is_ctrl_pressed() ? 4 : 0) |
		(mouse->is_alt_pressed() ? 8 : 0) | (mouse->is_meta_pressed() ? 16 : 0);
	auto mask = mouse->get_button_mask();
	if (mask.has_flag(MouseButtonMask::LEFT)) modifiers |= 32;
	if (mask.has_flag(MouseButtonMask::RIGHT)) modifiers |= 64;
	if (mask.has_flag(MouseButtonMask::MIDDLE)) modifiers |= 128;
	if (mask.has_flag(MouseButtonMask::MB_XBUTTON1)) modifiers |= 256;
	if (mask.has_flag(MouseButtonMask::MB_XBUTTON2)) modifiers |= 512;
	event[6] = modifiers;
	Ref<InputEventMouseButton> button = p_event;
	if (button.is_valid()) {
		int index = int(button->get_button_index());
		if (index >= 4 && index <= 7) {
			if (!button->is_pressed()) return;
#if defined(MACOS_ENABLED)
			// Native mac Glass feeds NSEvent wheel line deltas through the same
			// scroll-gesture path with a 10px multiplier (MacGestureSupport), so
			// one tick scrolls 10px per line unit. The Windows lines/40px
			// contract (kind 4) would scroll 4x the native distance on macOS.
			// The macOS platform layer normalizes precise (point) wheel deltas
			// to line units before creating the event, so the factor is always
			// in lines here regardless of the wheel's reporting mode.
			event[0] = 17;
			event[index <= 5 ? 8 : 7] = button->get_factor() * ((index == 4 || index == 6) ? 1 : -1);
#else
			event[0] = 4;
			event[index <= 5 ? 8 : 7] = button->get_factor() * ((index == 4 || index == 6) ? 1 : -1);
            // Separate doubles exactly represent every UINT32 setting, including
            // 0xffffffff (page scrolling). Do not compress or clamp either axis.
            // macOS wheel input takes the kind-15 gesture path above and never
            // reaches this Windows settings lookup.
            unsigned int lines = 3, chars = 3;
#if defined(WINDOWS_ENABLED)
            SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
            SystemParametersInfoW(SPI_GETWHEELSCROLLCHARS, 0, &chars, 0);
#endif
            event[10] = double(lines);
            event[11] = double(chars);
#endif
		} else {
			event[0] = button->is_pressed() ? 2 : 3;
			event[1] = index;
			// Glass expects the post-event button state in the modifiers, matching
			// the native wParam and Godot's own mouse_get_button_state(): a press
			// carries the pressed button's flag, a release clears it. Synthetic
			// events without an up-to-date mask are normalized here so Quantum's
			// press-drag-release gesture survives the press event itself.
			int bit = index == 1 ? 32 : index == 2 ? 64 : index == 3 ? 128 : index == 8 ? 256 : index == 9 ? 512 : 0;
			if (bit) {
				if (button->is_pressed()) modifiers |= bit;
				else modifiers &= ~bit;
				uint32_t &held = held_buttons[p_id];
				if (button->is_pressed()) held |= uint32_t(bit);
				else held &= ~uint32_t(bit);
				if (!held) held_buttons.erase(p_id);
			}
			event[6] = modifiers;
		}
	} else {
		event[0] = 1;
#if defined(WINDOWS_ENABLED)
		// A plain motion event with an empty button mask ends Quantum's
		// press-drag-release gesture outright (Scene$MouseHandler). Native
		// Windows moves always carry the held buttons in wParam; re-apply the
		// state tracked from our own press/release stream so a motion whose
		// mask was lost on the way here cannot silently kill a drag.
		auto held_entry = held_buttons.find(p_id);
		uint32_t held = held_entry == held_buttons.end() ? 0 : held_entry->second;
		if (held) event[6] = modifiers | int(held);
#endif
		// macOS native motions always carry the pressed buttons reported by
		// NSEvent, so no mask can be lost in transit. Replaying held state here
		// would instead turn the mask-less hover motions that synthetic tests
		// send between press and release into spurious drags; let an explicit
		// mask-less motion end the gesture, matching native semantics.
	}
	std::lock_guard<std::mutex> lock(runtime->host_mutex);
	if (runtime->input_events.size() >= 4096) {
		runtime->fail("Glass input queue overflow; input cannot be silently dropped");
		return;
	}
	runtime->input_events.push_back(event);
	runtime->queue.pulse_input();
}

void JavaFXHost::update_ime_composition(const String &p_text, int p_caret) {
	update_window_ime_composition(0,p_text,p_caret);
}

void JavaFXHost::update_window_ime_composition(int64_t p_id, const String &p_text, int p_caret) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	if (!runtime || (p_id && !native_windows.count(p_id))) return;
	bool enabled = p_id ? native_windows.at(p_id).ime_enabled : ime_enabled;
	if (!enabled) return;
	String &previous_text = p_id ? native_windows.at(p_id).ime_text : ime_text;
	int &previous_caret = p_id ? native_windows.at(p_id).ime_caret : ime_caret;
	ERR_FAIL_COND(p_caret < 0 || p_caret > p_text.length());
	if (previous_text == p_text && previous_caret == p_caret) return;
	Char16String utf16 = p_text.utf16();
	if (utf16.length() > 16384) { runtime->fail("IME composition exceeds 16384 UTF-16 units"); return; }
	int caret = p_text.substr(0, p_caret).utf16().length();
	std::lock_guard<std::mutex> lock(runtime->host_mutex);
	size_t records = 1 + (utf16.length() + 7) / 8;
	if (runtime->input_events.size() + records > 4096) { runtime->fail("IME input queue overflow"); return; }
	runtime->input_events.push_back({13, double(utf16.length()), double(caret), 0,0,0,0,0,0,double(p_id)});
	for (int offset = 0; offset < utf16.length(); offset += 8) {
		std::array<double,12> chunk{}; chunk[0] = 14; chunk[9] = double(p_id);
		for (int n = 0; n < 8 && offset+n < utf16.length(); ++n) chunk[n+1] = utf16[offset+n];
		runtime->input_events.push_back(chunk);
	}
	runtime->queue.pulse_input();
	previous_text = p_text; previous_caret = p_caret;
}

void JavaFXHost::window_ime_command(int64_t p_id, int p_operation, int p_a, int p_b) {
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window) return;
	bool &enabled = p_id ? native_windows.at(p_id).ime_enabled : ime_enabled;
	Point2i &position = p_id ? native_windows.at(p_id).ime_position : ime_position;
	if (p_operation == 16) {
		if (!p_a) update_window_ime_composition(p_id,String(),0);
		enabled = p_a != 0;
	} else if (p_operation == 17) position = Point2i(p_a,p_b);
	if (window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return;
	if (p_operation == 16) window->set_ime_active(enabled);
	else if (p_operation == 17) window->set_ime_position(position);
	else if (p_operation == 18) {
		auto *display = DisplayServer::get_singleton();
#if defined(WINDOWS_ENABLED)
		HWND handle = reinterpret_cast<HWND>(display->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE,window->get_window_id()));
		HIMC context = ImmGetContext(handle);
		if (context) { ImmNotifyIME(context,NI_COMPOSITIONSTR,CPS_COMPLETE,0); ImmReleaseContext(handle,context); }
#elif defined(MACOS_ENABLED)
		godot_javafx::macos_commit_ime_composition(window->get_window_id());
#endif
		// Complete and drain this window's committed Unicode before acknowledging.
		display->process_events();
	}
}

void JavaFXHost::window_event(int p_kind, int64_t p_id) {
	if (!runtime) return;
	// Native Windows suppresses enter/leave notifications while a window holds
	// the mouse capture (any button down). Delivering an exit mid-drag breaks
	// native hover semantics and diverges from the Win Glass event stream.
	auto held_entry = held_buttons.find(p_id);
	if ((p_kind == 7 || p_kind == 8) && held_entry != held_buttons.end() && held_entry->second) return;
	Window *source = p_id ? get_native_window(p_id) : get_window();
	if (!source) return;
	if (p_kind == 16) {
		held_buttons.erase(p_id);
		update_window_ime_composition(p_id,String(),0);
	}
	Vector2 pos = source->get_mouse_position();
	Point2i origin = source->get_position();
	std::lock_guard<std::mutex> lock(runtime->host_mutex);
	if (runtime->input_events.size() >= 4096) runtime->fail("Glass input queue overflow on window notification");
	else {
		runtime->input_events.push_back({ double(p_kind), 0, pos.x, pos.y, origin.x+pos.x, origin.y+pos.y, 0,0,0,double(p_id) });
		runtime->queue.pulse_input();
	}
}

void JavaFXHost::_notification(int p_what) {
	if (p_what == NOTIFICATION_ENTER_TREE) {
		RenderingServer::get_singleton()->connect("frame_post_draw", callable_mp(this, &JavaFXHost::frame_presented));
		RenderingServer::get_singleton()->connect("frame_pre_draw", callable_mp(this, &JavaFXHost::pre_draw_host_commands));
		// Apply late window commands after drawing as well as before it.
		RenderingServer::get_singleton()->connect("frame_post_draw", callable_mp(this, &JavaFXHost::post_draw_host_commands));
	}
	if (runtime && (p_what == NOTIFICATION_WM_MOUSE_ENTER || p_what == NOTIFICATION_WM_MOUSE_EXIT || p_what == NOTIFICATION_WM_CLOSE_REQUEST)) {
		int kind = p_what == NOTIFICATION_WM_MOUSE_ENTER ? 7 : p_what == NOTIFICATION_WM_MOUSE_EXIT ? 8 : 9;
		window_event(kind, 0);
	}
	if (p_what == NOTIFICATION_WM_WINDOW_FOCUS_IN) window_event(15, 0);
	if (p_what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) window_event(16, 0);
	if (p_what == NOTIFICATION_PROCESS && runtime) {
		const uint64_t process_start = OS::get_singleton()->get_ticks_usec();
		if (hover_tap_epoch_us == 0) {
			hover_tap_epoch_us = process_start;
			hover_tap_probe = OS::get_singleton()->get_environment("GODOT_JFX_HOVER_TAP") == "1";
			if (!hover_tap_probe) hover_tap_epoch_us = 1; // Decided: probe off.
		}
		++process_ticks;
		startup_tick();
		if (runtime->status.load() == godot_javafx::RuntimeStatus::FINISHED || runtime->status.load() == godot_javafx::RuntimeStatus::FAILED) {
			startup_cancel();
			restore_vsync_pacing();
		}
		check_vsync_pacing(process_start);
		apply_native_window_commands();
		apply_host_commands();
#if defined(MACOS_ENABLED)
		poll_fullscreen_reattach();
		// Cocoa panels dismiss on the main thread; dialogCancel() arrives on
		// the FX thread and is observed here.
		runtime->dialogs.pump();
#endif
		refresh_drag_delegates();
		{
			std::unique_ptr<godot_javafx::platform_dnd::SourceData> dnd_request;
			{
				std::lock_guard<std::mutex> lock(runtime->dnd_mutex);
				dnd_request = std::move(runtime->dnd_pending);
			}
			if (dnd_request) run_dnd_source(std::move(dnd_request));
		}
        if (auto request=runtime->dialogs.pending()) {
            Window *owner=request->owner<0 ? nullptr : request->owner==0 ? get_window() : get_native_window(request->owner);
            godot_javafx::OsNativeWindow handle=owner ? reinterpret_cast<godot_javafx::OsNativeWindow>(DisplayServer::get_singleton()->window_get_native_handle(
                    DisplayServerEnums::WINDOW_HANDLE,owner->get_window_id())) : nullptr;
            runtime->dialogs.start(request,handle,request->owner<0 || (owner && owner->is_visible()));
        }
		host_commands_us += OS::get_singleton()->get_ticks_usec() - process_start;
		// The present fence clears on frame_post_draw, but RenderingServer.draw
		// is skipped entirely while no window can draw (e.g. macOS orders out the
		// root window when the last visible FX Stage hides or closes). Complete
		// the fence here or queue admission would stall until the producer's
		// backpressure timeout kills the render context.
		if (present_pending && !DisplayServer::get_singleton()->can_any_window_draw()) finish_pending_pass();
		godot_javafx::Frame frame;
		const uint64_t passes_before = direct_offscreen_calls + direct_presentation_passes;
		// LCD text/effects can require many dependent offscreen passes. Draw
		// these without swapping the window instead of adding
		// a display-frame delay to every target transition. Bound this work so
		// a JavaFX frame cannot monopolize the host loop.
		uint64_t pass_deadline = 0;
		// Burst budget: how long one process tick may spend applying queued
		// JavaFX frames. The default keeps a single tick from monopolizing the
		// host loop; transition-heavy bursts raise it via the environment.
		static const uint64_t pass_budget_us = [] {
			auto environment = OS::get_singleton()->get_environment("GODOT_JFX_PASS_BUDGET_US");
			return environment.is_empty() ? uint64_t(4000) : (uint64_t)environment.to_int();
		}();
		static const size_t batch_cap = [] {
			auto environment = OS::get_singleton()->get_environment("GODOT_JFX_BATCH_CAP");
			return environment.is_empty() ? size_t(16) : (size_t)environment.to_int();
		}();
		for (size_t i = 0; !present_pending && i < batch_cap && runtime->queue.take(frame); ++i) {
			const uint64_t encode_start = OS::get_singleton()->get_ticks_usec();
			const uint64_t draw_before = draw_sync_us;
			runtime->queue.pulse(); // Wake an encoder waiting for queue capacity.
			for (const auto &command : frame.commands) {
				const uint64_t command_start = profile_commands ? OS::get_singleton()->get_ticks_usec() : 0;
				const float *v = command.values;
				switch (command.opcode) {
					case godot_javafx::Opcode::BEGIN_PRESENT: active_target.unref(); begin_present(); break;
					case godot_javafx::Opcode::TARGET_SELECT:
						active_target = command.texture_handle ? get_render_target(command.texture_handle) : Ref<JavaFXRenderTarget>();
						{
							static const bool gpu_timing = OS::get_singleton()->get_environment("GODOT_JFX_GPU_TIMING") == "1";
							if (gpu_timing && active_target.is_valid()) active_target->set_measure_gpu_time(true);
						}
						target_shader = String(); target_parameters.clear(); target_instance_params.clear(); target_clip = false;
						if (active_target.is_valid()) active_target->begin_pass(false); else begin_present();
						break;
					case godot_javafx::Opcode::WINDOW_REMOVE:
						if (native_presentations.erase(command.window_id)) {
							if (auto *window = get_native_window(command.window_id)) {
								window->clear_content(); pending_native_composition = command.window_id;
							}
							present_pending = true; break;
						}
						remove_window(command.window_id);
						compose_windows(); present_pending = true;
						break;
					case godot_javafx::Opcode::WINDOW_CONFIGURE:
						if (native_presentations.count(command.window_id)) {
							if (auto *window = get_native_window(command.window_id)) {
								window->set_content_opacity(command.window_visible ? v[4] : 0);
								pending_native_composition = command.window_id;
							}
							present_pending = true; break;
						}
						configure_window(command.window_id, Rect2(v[0], v[1], v[2], v[3]), command.window_z, command.window_visible, v[4]);
						compose_windows(); present_pending = true;
						break;
					case godot_javafx::Opcode::WINDOW_PRESENT:
					case godot_javafx::Opcode::NATIVE_WINDOW_PRESENT:
						pending_window_native = command.opcode == godot_javafx::Opcode::NATIVE_WINDOW_PRESENT;
						pending_window_id = command.window_id;
						pending_window_rect = Rect2(v[0], v[1], v[2], v[3]);
						pending_window_z = command.window_z; pending_window_opacity = v[4];
						[[fallthrough]];
					case godot_javafx::Opcode::PRESENT:
					case godot_javafx::Opcode::END_PASS:
						offscreen_pass_pending = command.opcode == godot_javafx::Opcode::END_PASS;
						if (offscreen_pass_pending) ++offscreen_passes;
						completing_presentation = !offscreen_pass_pending;
						if (completing_presentation) completing_window_id = pending_window_native ? pending_window_id : 0;
						compose_target = completing_presentation && active_target.is_valid();
						if (active_target.is_valid()) active_target->end_pass(); else commit_present();
						present_pending = true;
						if (offscreen_pass_pending) complete_offscreen_pass();
						else if (active_target.is_valid() && OS::get_singleton()->get_environment("GODOT_JFX_DIRECT_PRESENT") != "0") {
							// Draw the finished target before queueing window composition,
							// allowing both to reach the next host display frame.
							const uint64_t start = OS::get_singleton()->get_ticks_usec();
							active_target->draw_offscreen_pass();
							// A presentation is the frame boundary the compose and
							// the swapchain see; deferring its render to the tick
							// end raced the compose and showed stale content
							// (hover repaints lagging/dropping). Intermediate
							// effect passes stay batched.
							const uint64_t elapsed = OS::get_singleton()->get_ticks_usec() - start;
							draw_sync_us += elapsed; ++draw_sync_calls; ++direct_presentation_passes;
							max_draw_sync_us = MAX(max_draw_sync_us, elapsed);
							finish_pending_pass();
						}
						break;
					case godot_javafx::Opcode::CLEAR:
						if (active_target.is_valid()) active_target->clear_pass(); else clear_commands();
						break;
					case godot_javafx::Opcode::CLIP:
						target_clip = command.clip_enabled; target_clip_rect = Rect2i(int32_t(command.x), int32_t(command.y), command.width, command.height);
						if (active_target.is_null()) set_draw_clip(target_clip, target_clip_rect);
						break;
					case godot_javafx::Opcode::SHADER_STATE: {
						Dictionary parameters;
						for (const auto &constant : command.constants) {
							Variant value;
							if (constant.array_count) {
								if (constant.type) {
									PackedInt32Array words; words.resize(constant.words.size());
									memcpy(words.ptrw(), constant.words.data(), constant.words.size() * 4);
									value = words;
								} else {
									PackedFloat32Array words; words.resize(constant.words.size());
									memcpy(words.ptrw(), constant.words.data(), constant.words.size() * 4);
									value = words;
								}
							} else if (constant.type) {
								// The decoder validates 1..4 components and the exact word count.
								// Scalar/vector constants do not need a heap-backed packed array.
								int32_t words[4] = {};
								memcpy(words, constant.words.data(), constant.components * sizeof(words[0]));
								switch (constant.components) {
									case 1: value = words[0]; break;
									case 2: value = Vector2i(words[0], words[1]); break;
									case 3: value = Vector3i(words[0], words[1], words[2]); break;
									case 4: value = Vector4i(words[0], words[1], words[2], words[3]); break;
								}
							} else {
								float words[4] = {};
								memcpy(words, constant.words.data(), constant.components * sizeof(words[0]));
								switch (constant.components) {
									case 1: value = words[0]; break;
									case 2: value = Vector2(words[0], words[1]); break;
									case 3: value = Vector3(words[0], words[1], words[2]); break;
									case 4: value = Vector4(words[0], words[1], words[2], words[3]); break;
								}
							}
							parameters[String(constant.name.c_str())] = value;
						}
						for (const auto &sampler : command.samplers) parameters[String(sampler.first.c_str())] = retain_sampler_texture(sampler.second);
						if (active_target.is_valid()) {
							target_shader = String(command.shader_source.c_str());
							// Target-path shaders compile value uniforms as per-instance uniforms;
							// those constants ride item instance data instead of the material,
							// so per-frame changes no longer rebuild uniform sets.
							target_instance_params.clear();
							const Vector<StringName> &godot_instance_names = godot_javafx::instance_uniform_names(target_shader);
							// Names are already cached for this shader. Visit only those keys;
							// avoid rebuilding a hash set and copying every Dictionary key per draw.
							for (const StringName &name : godot_instance_names) {
								const String key(name);
								if (const Variant *value = parameters.getptr(key)) {
									target_instance_params[name] = *value;
									parameters.erase(key); // Copy the value before invalidating its entry.
								}
							}
							target_parameters = parameters;
						}
						else { set_draw_shader_code(String(command.shader_source.c_str())); set_draw_shader_parameters(parameters); }
					} break;
					case godot_javafx::Opcode::RESIZE: set_surface_size(Size2i(command.width, command.height)); break;
					case godot_javafx::Opcode::QUADS:
					case godot_javafx::Opcode::TEXTURED_QUADS:
					case godot_javafx::Opcode::QUADS_REF: {
						// Java sends (mxx, mxy, mxt, myx, myy, myt): x' = mxx*x + mxy*y + mxt.
						const float *t = command.transform;
						const Transform2D transform(t[0], t[3], t[1], t[4], t[2], t[5]);
						const bool textured = command.opcode == godot_javafx::Opcode::TEXTURED_QUADS ||
								(command.opcode == godot_javafx::Opcode::QUADS_REF && command.texture_handle != 0);
						Ref<ArrayMesh> known;
						if (command.opcode == godot_javafx::Opcode::QUADS_REF) {
							const Ref<ArrayMesh> *found = geometry_meshes.getptr(command.geometry_handle);
							if (!found) { runtime->fail("Referenced geometry handle is not resident"); return; }
							known = *found;

						} else if (command.geometry_handle) {
							// Tagged QUADS registers fresh content exactly once; build
							// the mesh here so the handle and the draw share it.
							PackedFloat32Array vertices;
							PackedByteArray colors;
							vertices.resize(command.vertices.size()); colors.resize(command.colors.size());
							memcpy(vertices.ptrw(), command.vertices.data(), command.vertices.size() * sizeof(float));
							memcpy(colors.ptrw(), command.colors.data(), command.colors.size());
							build_prism_mesh(known, vertices, colors);
							if (known.is_null()) { runtime->fail("Cannot build registered geometry mesh"); return; }
							geometry_meshes.insert(command.geometry_handle, known);
						}
						if (command.opcode == godot_javafx::Opcode::QUADS_REF) ++quads_referenced;
						else ++quads_uploaded;
						if (active_target.is_valid()) {
							const uint64_t shaders_before = profile_commands ? active_target->get_shader_creation_count() : 0;
							RID texture = textured ? retain_sampler_texture(command.texture_handle) : RID();
							if (known.is_valid())
								active_target->draw_prism_mesh_with_instances(known, target_shader, target_parameters, target_clip, target_clip_rect, texture, transform, command.draw_alpha, &target_instance_params);
							else {
								PackedFloat32Array vertices;
								PackedByteArray colors;
								vertices.resize(command.vertices.size()); colors.resize(command.colors.size());
								memcpy(vertices.ptrw(), command.vertices.data(), command.vertices.size() * sizeof(float));
								memcpy(colors.ptrw(), command.colors.data(), command.colors.size());
								active_target->draw_prism_quads_with_instances(vertices, colors, target_shader, target_parameters, target_clip, target_clip_rect,
									texture, transform, command.draw_alpha, &target_instance_params);
							}
							if (profile_commands) profile_shader_creations += active_target->get_shader_creation_count() - shaders_before;
						}
						else if (known.is_valid()) {
							if (textured) add_textured_mesh(command.texture_handle, known, transform, command.draw_alpha);
							else add_prism_mesh(known, transform, command.draw_alpha);
						}
						else {
							PackedFloat32Array vertices;
							PackedByteArray colors;
							vertices.resize(command.vertices.size()); colors.resize(command.colors.size());
							memcpy(vertices.ptrw(), command.vertices.data(), command.vertices.size() * sizeof(float));
							memcpy(colors.ptrw(), command.colors.data(), command.colors.size());
							if (textured) add_textured_quads(command.texture_handle, vertices, colors, transform, command.draw_alpha);
							else add_prism_quads(vertices, colors, transform, command.draw_alpha);
						}
					} break;
					case godot_javafx::Opcode::GEOMETRY_FREE: {
						const Ref<ArrayMesh> *mesh = geometry_meshes.getptr(command.geometry_handle);
						if (mesh == nullptr) { runtime->fail("Geometry disposal references unknown handle"); return; }
						geometry_meshes.erase(command.geometry_handle);
						break;
					}
					case godot_javafx::Opcode::TEXTURE_CREATE:
					case godot_javafx::Opcode::TEXTURE_UPDATE:
					case godot_javafx::Opcode::FLOAT_TEXTURE_PATCH:
					case godot_javafx::Opcode::ALPHA_TEXTURE_PATCH:
					case godot_javafx::Opcode::TEXTURE_PATCH: {
						PackedByteArray pixels;
						if(command.opcode==godot_javafx::Opcode::ALPHA_TEXTURE_PATCH && !is_single_channel_texture(command.texture_handle)) {
							pixels.resize(command.pixels.size()*4);
							uint8_t *destination=pixels.ptrw();
							for(size_t index=0;index<command.pixels.size();index++) {
								const uint32_t value=uint32_t(command.pixels[index])*0x01010101u;
								memcpy(destination+index*4,&value,sizeof(value));
							}
						} else {
							pixels.resize(command.pixels.size());
							memcpy(pixels.ptrw(), command.pixels.data(), command.pixels.size());
						}
						if (command.opcode == godot_javafx::Opcode::ALPHA_TEXTURE_PATCH || command.opcode == godot_javafx::Opcode::TEXTURE_PATCH || command.opcode == godot_javafx::Opcode::FLOAT_TEXTURE_PATCH) patch_texture(command.texture_handle, Rect2i(command.x, command.y, command.width, command.height), pixels);
						else put_texture(command.texture_handle, Size2i(command.width, command.height), pixels);
					} break;
					case godot_javafx::Opcode::VIDEO_PLANE_ALLOCATE: allocate_texture(command.texture_handle, Size2i(command.width, command.height), false, true); break;
					case godot_javafx::Opcode::TEXTURE_ALLOCATE: allocate_texture(command.texture_handle, Size2i(command.width, command.height)); break;
					case godot_javafx::Opcode::FLOAT_TEXTURE_ALLOCATE: allocate_texture(command.texture_handle, Size2i(command.width, command.height), true); break;
					case godot_javafx::Opcode::TARGET_ALLOCATE: allocate_render_target(command.texture_handle, Size2i(command.width, command.height)); break;
					case godot_javafx::Opcode::SCENE_TEXTURE_ALLOCATE: {
						String path;
						if (path.append_utf8(command.scene_path.data(), command.scene_path.size()) != OK || !allocate_scene_texture(command.texture_handle, Size2i(command.width, command.height), path)) {
							runtime->fail("Cannot load embedded Godot scene: " + command.scene_path);
							return;
						}
					} break;
					case godot_javafx::Opcode::TEXTURE_DISPOSE: dispose_texture(command.texture_handle); break;
					case godot_javafx::Opcode::SCENE_TEXTURE_RESIZE: resize_scene_texture(command.texture_handle, command.source_handle, Size2i(command.width, command.height)); break;
					case godot_javafx::Opcode::SCENE_INPUT: scene_input(command.texture_handle, command.input_kind, command.input_flags, command.input_code, command.input_unicode, Vector2(v[0],v[1]), Vector2(v[2],v[3])); break;
				}
				if (profile_commands) {
					const uint64_t elapsed = OS::get_singleton()->get_ticks_usec() - command_start;
					switch (command.opcode) {
						case godot_javafx::Opcode::TEXTURE_CREATE:
						case godot_javafx::Opcode::TEXTURE_UPDATE:
						case godot_javafx::Opcode::ALPHA_TEXTURE_PATCH:
					case godot_javafx::Opcode::TEXTURE_PATCH:
						case godot_javafx::Opcode::FLOAT_TEXTURE_PATCH:
						case godot_javafx::Opcode::TEXTURE_ALLOCATE:
						case godot_javafx::Opcode::VIDEO_PLANE_ALLOCATE:
						case godot_javafx::Opcode::FLOAT_TEXTURE_ALLOCATE: profile_texture_us += elapsed; break;
						case godot_javafx::Opcode::TARGET_ALLOCATE: profile_target_us += elapsed; break;
						case godot_javafx::Opcode::TEXTURED_QUADS:
						case godot_javafx::Opcode::QUADS: profile_geometry_us += elapsed; break;
						case godot_javafx::Opcode::SHADER_STATE: profile_shader_us += elapsed; break;
						default: break;
					}
				}
			}
			applied_sequence = frame.sequence;
			encode_us += OS::get_singleton()->get_ticks_usec() - encode_start - (draw_sync_us - draw_before);
			// The first batch may wait for a previous window presentation. Give
			// subsequent work its own bounded allowance, otherwise that wait
			// reduces every host iteration to one offscreen pass. A single batch
			// remains indivisible, and the 16-batch cap still bounds this loop.
			const uint64_t now = OS::get_singleton()->get_ticks_usec();
			if (!pass_deadline) pass_deadline = now + pass_budget_us;
			else if (now >= pass_deadline) break;
		}
		if (direct_offscreen_calls + direct_presentation_passes != passes_before) {
			const uint64_t start = OS::get_singleton()->get_ticks_usec();
			RenderingServer::get_singleton()->sync();
			const uint64_t elapsed = OS::get_singleton()->get_ticks_usec() - start;
			draw_sync_us += elapsed; ++draw_sync_calls; max_draw_sync_us = MAX(max_draw_sync_us, elapsed);
			if (hover_tap_probe && elapsed > 100000) {
				print_line(vformat("HOVER_TAP t=%dms HOST_SYNC phase=rs_sync us=%d",
						int64_t((OS::get_singleton()->get_ticks_usec() - hover_tap_epoch_us) / 1000), int64_t(elapsed)));
			}
		}
		const uint64_t metadata_start = OS::get_singleton()->get_ticks_usec();
		refresh_host_info();
		metadata_us += OS::get_singleton()->get_ticks_usec() - metadata_start;
		if (!present_pending && !is_composition_pending()) runtime->completed_render_sequence.store(applied_sequence);
		apply_readback();
		runtime->queue.pulse_frame();
		// HOVER_TAP host-side stall probe: measures the gap between consecutive
		// process ticks. Paired with the FX_GAP/FX_TASK probes in GodotEventLoop,
		// this distinguishes a starving host (tick gaps) from a starving Java
		// dispatch (host ticking but no pulse posted). prev_body shows whether
		// the previous tick itself consumed the gap inside this body.
		if (hover_tap_probe) {
			const uint64_t now_us = OS::get_singleton()->get_ticks_usec();
			auto *rs_info = RenderingServer::get_singleton();
			const uint64_t pipes = rs_info->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS) +
					rs_info->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW);
			const uint64_t tex_mem = rs_info->get_rendering_info(RSE::RENDERING_INFO_TEXTURE_MEM_USED);
			const uint64_t buf_mem = rs_info->get_rendering_info(RSE::RENDERING_INFO_BUFFER_MEM_USED);
			if (hover_tap_last_tick_us && now_us - hover_tap_last_tick_us > 120000) {
				print_line(vformat("HOVER_TAP t=%dms HOST_GAP gap=%dms prev_body=%dms pipes=%d tex=%dMB buf=%dMB",
						int64_t((now_us - hover_tap_epoch_us) / 1000), int64_t((now_us - hover_tap_last_tick_us) / 1000),
						int64_t(hover_tap_last_body_us / 1000), int64_t(pipes - hover_tap_last_pipes),
						int64_t((tex_mem - hover_tap_last_tex_mem) / 1048576), int64_t((buf_mem - hover_tap_last_buf_mem) / 1048576)));
			}
			hover_tap_last_tick_us = now_us;
			hover_tap_last_body_us = now_us - process_start;
			hover_tap_last_pipes = pipes;
			hover_tap_last_tex_mem = tex_mem;
			hover_tap_last_buf_mem = buf_mem;
		}
		if (!reported_failure && runtime->status.load() == godot_javafx::RuntimeStatus::FAILED) {
			startup_cancel();
			reported_failure = true;
			ERR_PRINT(get_runtime_error());
		}
		process_us += OS::get_singleton()->get_ticks_usec() - process_start;
	} else if (p_what == NOTIFICATION_EXIT_TREE) {
		startup_cancel();

        if (runtime) runtime->dialogs.stop();
		set_window_input_enabled(0, true);
		while (!native_windows.empty()) destroy_native_window(native_windows.begin()->first);
		if (ime_enabled) get_window()->set_ime_active(false);
		ime_enabled = false;
		RenderingServer::get_singleton()->disconnect("frame_post_draw", callable_mp(this, &JavaFXHost::frame_presented));
		RenderingServer::get_singleton()->disconnect("frame_pre_draw", callable_mp(this, &JavaFXHost::pre_draw_host_commands));
		RenderingServer::get_singleton()->disconnect("frame_post_draw", callable_mp(this, &JavaFXHost::post_draw_host_commands));
		present_pending = false;
		offscreen_pass_pending = false;
		completing_presentation = false;
		active_target.unref(); target_parameters.clear(); target_instance_params.clear();
		if (runtime) get_tree()->set_auto_accept_quit(previous_auto_accept_quit);
		stop_host();
	}
	if (p_what == MainLoop::NOTIFICATION_OS_IME_UPDATE && runtime) {
		auto *display = DisplayServer::get_singleton();
		String text = display->ime_get_text();
		int caret = CLAMP(display->ime_get_selection().x, 0, text.length());
		auto focused = display->get_focused_window();
		if (get_window()->get_window_id() == focused) update_ime_composition(text,caret);
		else for (const auto &entry : native_windows)
			if (entry.second.window->is_visible() && entry.second.window->get_window_id() == focused) update_window_ime_composition(entry.first,text,caret);
	}
}

void JavaFXHost::complete_offscreen_pass() {
	++immediate_passes;
	auto *rs = RenderingServer::get_singleton();
	if (active_target.is_valid() && OS::get_singleton()->get_environment("GODOT_JFX_DIRECT_OFFSCREEN") != "0") {
		const uint64_t start = OS::get_singleton()->get_ticks_usec();
		direct_offscreen_render_us += active_target->draw_offscreen_pass();
		const uint64_t elapsed = OS::get_singleton()->get_ticks_usec() - start;
		direct_offscreen_us += elapsed; ++direct_offscreen_calls;
		draw_sync_us += elapsed; ++draw_sync_calls; max_draw_sync_us = MAX(max_draw_sync_us, elapsed);
		active_target->finish_pass();
		// Match the normal completion path and the admission ledger: samplers
		// and retired resources from this pass cannot survive into the next one.
		finish_present(); active_target.unref(); target_parameters.clear(); target_instance_params.clear();
		present_pending = false; offscreen_pass_pending = false;
	} else {
		const uint64_t start = OS::get_singleton()->get_ticks_usec();
		rs->draw(false, 0.0);
		const uint64_t elapsed = OS::get_singleton()->get_ticks_usec() - start;
		draw_sync_us += elapsed; ++draw_sync_calls; max_draw_sync_us = MAX(max_draw_sync_us, elapsed);
	}
}

void JavaFXHost::frame_presented() {
	finish_pending_pass();
	startup_post_draw();
}

void JavaFXHost::finish_pending_pass() {
	if (present_pending) {
		if (pending_native_composition) {
			auto *window = get_native_window(pending_native_composition);
			if (window && window->is_present_pending()) return;
			pending_native_composition = 0;
		}
		if (active_target.is_valid()) active_target->finish_pass();
		finish_present();
		if (compose_target) {
			if (pending_window_id) {
				if (pending_window_native) {
					native_presentations.insert(pending_window_id);
					// Native lifetime commands may close a Stage before a queued
					// Prism frame arrives. Never recreate it as an embedded layer.
					if (auto *window = get_native_window(pending_window_id)) {
						window->set_content_opacity(pending_window_opacity);
						window->present_content(active_target, pending_window_rect.size);
					}
					pending_window_id = 0; pending_window_native = false;
					compose_target = false; active_target.unref();
					target_parameters.clear(); target_instance_params.clear();
					// The target's texture is already final (its presentation pass
					// was drawn synchronously) and the window retains the target
					// until its own composition replaces it. Complete the handoff
					// immediately: holding the host-wide present fence until the
					// window's post-draw throttled every queued frame to that
					// window's compose cadence.
					if (completing_presentation) {
						++completed_presentations;
						if (startup_active && completing_window_id == startup_window_id) startup_frame_ready = true;
					}
					completing_presentation = false;
					present_pending = false;
					offscreen_pass_pending = false;
					return;
				}
				configure_window(pending_window_id, pending_window_rect, pending_window_z, true, pending_window_opacity);
				set_window_content(pending_window_id, active_target);
				compose_windows();
				pending_window_id = 0; compose_target = false; active_target.unref();
				return;
			}
			begin_present(); clear_commands();
			set_draw_shader_code("shader_type canvas_item; render_mode unshaded, blend_premul_alpha;");
			add_render_target(active_target, Rect2(Vector2(), get_surface_size()));
			commit_present(); compose_target = false; active_target.unref();
			return;
		}
		active_target.unref(); target_parameters.clear(); target_instance_params.clear();
		if (completing_presentation) {
			++completed_presentations;
			if (startup_active && completing_window_id == startup_window_id) startup_frame_ready = true;
		}
		completing_presentation = false;
		present_pending = false;
		offscreen_pass_pending = false;
	}
}

void JavaFXHost::refresh_host_info() {
	auto *display = DisplayServer::get_singleton();
	Window *host_window = get_window();
	Size2i size = host_window->get_size();
	Point2i pos = host_window->get_position();
	Size2i screen;
	Point2i screen_pos;
	Rect2i usable;
	int dpi = 96;
	bool found_current_screen = false;
	// Gather on the Godot thread; JNI readers only copy this immutable snapshot.
	// Glass requires the primary monitor first, regardless of Godot's index order.
	std::vector<jint> screens;
	int primary_screen = display->get_primary_screen();
	const int screen_count = display->get_screen_count();
	const int current_screen = display->window_get_current_screen();
	screens.reserve(screen_count * 10);
	for (int pass = 0; pass < 2; ++pass) {
		for (int index = 0; index < screen_count; ++index) {
			if ((index == primary_screen) != (pass == 0)) continue;
			Point2i origin = display->screen_get_position(index);
			Size2i extent = display->screen_get_size(index);
			Rect2i work = display->screen_get_usable_rect(index);
#if defined(MACOS_ENABLED)
			// macOS reports a physical-panel DPI (with a 72 fallback) rather than
			// a UI-scale-anchored value. The Java side derives scale as dpi/96 to
			// match DisplayServerWindows::screen_get_scale, so feed it the macOS
			// UI scale instead of the physical DPI.
			const int screen_dpi = int(display->screen_get_scale(index) * 96.0f + 0.5f);
#else
			const int screen_dpi = display->screen_get_dpi(index);
#endif
			screens.insert(screens.end(), { index + 1, origin.x, origin.y, extent.x, extent.y,
				work.position.x, work.position.y, work.size.x, work.size.y, screen_dpi });
			if (index == current_screen) {
				screen = extent; screen_pos = origin; usable = work; dpi = screen_dpi;
				found_current_screen = true;
			}
		}
	}
	// Reuse this frame's monitor snapshot, not a timed cache: monitor/DPI/work-area
	// changes remain visible every frame. Fall back if topology changed mid-query.
	if (!found_current_screen) {
		screen = display->screen_get_size(); screen_pos = display->screen_get_position();
		usable = display->screen_get_usable_rect();
#if defined(MACOS_ENABLED)
		dpi = int(display->screen_get_scale() * 96.0f + 0.5f);
#else
		dpi = display->screen_get_dpi();
#endif
	}
	// Never hold the JNI snapshot mutex while calling the OS or scene API.
	const std::array<jint, 16> info = { size.x, size.y, dpi, pos.x, pos.y,
		screen.x, screen.y, screen_pos.x, screen_pos.y, host_window->has_focus() ? 1 : 0,
		int(host_window->get_mode()), runtime->applied_host_sequence,
		usable.position.x, usable.position.y, usable.size.x, usable.size.y };
	std::lock_guard<std::mutex> lock(runtime->host_mutex);
	runtime->screens = std::move(screens);
	runtime->info = info;
}

void JavaFXHost::pre_draw_host_commands() {
	// Apply window commands on the main thread before presentation.
	if (!runtime || !Thread::is_main_thread()) return;
	apply_host_commands();
}

void JavaFXHost::post_draw_host_commands() {
	// Apply window commands on the main thread after presentation, except
	// primary-window resizes: Window::set_size recreates the root render
	// target, and doing that right after the draw leaves it empty for any
	// frame_post_draw observer (the next draw is one frame away). Let the
	// process/pre-draw application take the resize instead, so the clear and
	// the redraw land in the same frame.
	if (!runtime || !Thread::is_main_thread()) return;
	{
		std::lock_guard<std::mutex> lock(runtime->host_mutex);
		for (const auto &command : runtime->host_commands) {
			if (command.operation == 2) return;
		}
	}
	apply_host_commands();
}

void JavaFXHost::check_vsync_pacing(uint64_t p_now_us) {
	if (vsync_probe_done) return;
	if (!runtime || runtime->status.load() != godot_javafx::RuntimeStatus::RUNNING) return;
	auto *display = DisplayServer::get_singleton();
	// An application-owned cap is intentional pacing, not evidence of a
	// broken present mode. Recheck throughout sampling in case it changes.
	if (Engine::get_singleton()->get_max_fps() != 0) { vsync_probe_done = true; return; }
	if (vsync_probe_begin_us == 0) {
		if (OS::get_singleton()->get_environment("GODOT_JFX_VSYNC_FALLBACK") == "0") { vsync_probe_done = true; return; }
		if (display->window_get_vsync_mode(DisplayServerEnums::MAIN_WINDOW_ID) != DisplayServerEnums::VSYNC_ENABLED) { vsync_probe_done = true; return; }
		vsync_probe_begin_us = p_now_us;
		vsync_probe_prev_us = p_now_us;
		return;
	}
	const uint64_t elapsed = p_now_us - vsync_probe_begin_us;
	// Skip JVM/render bring-up, then sample two seconds of frame intervals.
	if (elapsed < 2000000) { vsync_probe_prev_us = p_now_us; return; }
	if (elapsed <= 4000000) {
		vsync_probe_sum_us += p_now_us - vsync_probe_prev_us;
		vsync_probe_prev_us = p_now_us;
		++vsync_probe_count;
		return;
	}
	vsync_probe_done = true;
	if (vsync_probe_count < 8) return;
	const double avg_us = double(vsync_probe_sum_us) / vsync_probe_count;
	const float refresh_hz = display->screen_get_refresh_rate(display->window_get_current_screen());
	if (!Math::is_finite(refresh_hz) || refresh_hz < 55.0f) return;
	const double period_us = 1000000.0 / refresh_hz;
	if (avg_us <= period_us * 1.4) return;
	Window::Mode mode = get_window()->get_mode();
	if (mode == Window::MODE_FULLSCREEN || mode == Window::MODE_EXCLUSIVE_FULLSCREEN) return;
	if (display->window_get_vsync_mode(DisplayServerEnums::MAIN_WINDOW_ID) != DisplayServerEnums::VSYNC_ENABLED) return;
	display->window_set_vsync_mode(DisplayServerEnums::VSYNC_DISABLED);
	fallback_fps = int(Math::round(refresh_hz));
	Engine::get_singleton()->set_max_fps(fallback_fps);
	print_line(vformat("JAVAFX_VSYNC_FALLBACK avg_frame_ms=%.3f refresh_hz=%.3f: observed low host cadence with VSync enabled; trying CPU pacing", avg_us / 1000.0, double(refresh_hz)));
}

void JavaFXHost::restore_vsync_pacing() {
	if (fallback_fps == 0) return;
	// Admission only changes an uncapped, VSync-enabled host. Restore each
	// setting only if it still equals the value this host installed.
	if (Engine::get_singleton()->get_max_fps() == fallback_fps)
		Engine::get_singleton()->set_max_fps(0);
	auto *display = DisplayServer::get_singleton();
	if (display->window_get_vsync_mode(DisplayServerEnums::MAIN_WINDOW_ID) == DisplayServerEnums::VSYNC_DISABLED)
		display->window_set_vsync_mode(DisplayServerEnums::VSYNC_ENABLED);
	fallback_fps = 0;
}

void JavaFXHost::apply_host_commands() {
	std::deque<godot_javafx::HostCommand> pending_commands;
	{ std::lock_guard<std::mutex> lock(runtime->host_mutex); pending_commands.swap(runtime->host_commands); }
	Window *host_window = get_window();
	auto *display = DisplayServer::get_singleton();
	for (const auto &command : pending_commands) {
		int a = command.a, b = command.b;
		switch (command.operation) {
			case 1: host_window->set_title(String::utf16(command.text.data(), int(command.text.size()))); break;
			case 2: host_window->set_size(Size2i(a, b)); set_surface_size(Size2i(a, b)); break;
			case 3: host_window->set_position(Point2i(a, b)); break;
			case 4: request_window_focus(host_window); break;
			case 5: {
				set_visible(a != 0);
				if (startup_show(0, a != 0)) break;
				// Godot forbids hiding its root Window through Window::set_visible.
				// Hide/show the existing native window; never create a second one.
#if defined(WINDOWS_ENABLED)
				HWND handle = reinterpret_cast<HWND>(display->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE));
				ShowWindow(handle, a ? SW_SHOW : SW_HIDE);
#elif defined(MACOS_ENABLED)
				godot_javafx::macos_set_window_visible(reinterpret_cast<void *>(display->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE)), a != 0);
#endif
			} break;
			case 6: host_window->set_mode(static_cast<Window::Mode>(a)); break;
			case 7: host_window->set_flag(Window::FLAG_RESIZE_DISABLED, !a); break;
			case 8: set_modulate(Color(1, 1, 1, float(a) / 1000000.0f)); break;
			case 9: host_window->set_flag(Window::FLAG_ALWAYS_ON_TOP, a != 0); break;
			case 10: {
				using namespace DisplayServerEnums;
				if(custom_cursor_active) { display->cursor_set_custom_image(Ref<Resource>(),CURSOR_ARROW); custom_cursor_active=false; custom_cursor_info.clear(); }
				if (!managed_cursor_state) { previous_mouse_mode = display->mouse_get_mode(); managed_cursor_state = true; }
				cursor_none_requested = a == -1;
				display->mouse_set_mode(cursor_visible && !cursor_none_requested ? MOUSE_MODE_VISIBLE : MOUSE_MODE_HIDDEN);
				if (cursor_none_requested) break;
				CursorShape shape = CURSOR_ARROW;
				switch (a) {
					case 2: shape = CURSOR_IBEAM; break;
					case 3: shape = CURSOR_CROSS; break;
					case 4: shape = CURSOR_DRAG; break;
					case 5: case 6: shape = CURSOR_POINTING_HAND; break;
					case 7: case 8: case 11: shape = CURSOR_HSIZE; break;
					case 9: case 10: case 12: shape = CURSOR_VSIZE; break;
					case 13: shape = CURSOR_FORBIDDEN; break;
					case 14: shape = CURSOR_WAIT; break;
					// Godot's Windows BDIAGSIZE glyph is the NESW diagonal and
					// FDIAGSIZE is NWSE (the enum names are swapped upstream).
					case 15: case 18: shape = CURSOR_BDIAGSIZE; break;
					case 16: case 17: shape = CURSOR_FDIAGSIZE; break;
					case 19: shape = CURSOR_MOVE; break;
				}
				display->cursor_set_shape(shape);
				// The Viewport re-asserts the Input default cursor on every mouse
				// motion (no Godot Control is hovered over the JavaFX surface).
				// Keep that default in sync so the JavaFX cursor is not reverted
				// to the arrow between JavaFX cursor commands. The quiet setter
				// avoids injecting a fake motion event into the hosted scene.
				Input::get_singleton()->set_default_cursor_shape_quiet(static_cast<Input::CursorShape>(shape));
			} break;
			case 11:
				if (!managed_cursor_state) { previous_mouse_mode = display->mouse_get_mode(); managed_cursor_state = true; }
				cursor_visible = a != 0;
				display->mouse_set_mode(cursor_visible && !cursor_none_requested ? DisplayServerEnums::MOUSE_MODE_VISIBLE : DisplayServerEnums::MOUSE_MODE_HIDDEN);
				refresh_custom_cursor_info();
				break;
			case 21: {
				if (!managed_cursor_state) { previous_mouse_mode = display->mouse_get_mode(); managed_cursor_state = true; }
				cursor_none_requested = false;
				display->mouse_set_mode(cursor_visible ? DisplayServerEnums::MOUSE_MODE_VISIBLE : DisplayServerEnums::MOUSE_MODE_HIDDEN);
				PackedByteArray rgba; rgba.resize(command.cursor_pixels.size());
				for(size_t p=0;p<command.cursor_pixels.size();p+=4) {
#if defined(MACOS_ENABLED)
					// Glass pixels arrive premultiplied; DisplayServerMacOS applies
					// its own premultiply pass when building the NSCursor bitmap,
					// so hand it straight-alpha values to avoid double darkening.
					const uint8_t alpha = command.cursor_pixels[p+3];
					const uint32_t r = alpha ? std::min(255u, uint32_t(command.cursor_pixels[p+2]) * 255 / alpha) : 0;
					const uint32_t g = alpha ? std::min(255u, uint32_t(command.cursor_pixels[p+1]) * 255 / alpha) : 0;
					const uint32_t b = alpha ? std::min(255u, uint32_t(command.cursor_pixels[p]) * 255 / alpha) : 0;
					rgba.set(p,uint8_t(r)); rgba.set(p+1,uint8_t(g));
					rgba.set(p+2,uint8_t(b)); rgba.set(p+3,alpha);
#else
					rgba.set(p,command.cursor_pixels[p+2]); rgba.set(p+1,command.cursor_pixels[p+1]);
					rgba.set(p+2,command.cursor_pixels[p]); rgba.set(p+3,command.cursor_pixels[p+3]);
#endif
				}
				Ref<Image> image=Image::create_from_data(command.cursor_width,command.cursor_height,false,Image::FORMAT_RGBA8,rgba);
				display->cursor_set_shape(DisplayServerEnums::CURSOR_ARROW);
				display->cursor_set_custom_image(image,DisplayServerEnums::CURSOR_ARROW,Vector2(a,b));
				// The custom image hangs off CURSOR_ARROW; keep the Viewport's
				// per-motion fallback there as well so it cannot restore a stale
				// system shape over the custom cursor.
				Input::get_singleton()->set_default_cursor_shape_quiet(InputClassEnums::CURSOR_ARROW);
				custom_cursor_active=true;
				refresh_custom_cursor_info();
			} break;
			case 12: host_window->set_min_size(Size2i(a, b)); break;
			case 13: host_window->set_max_size(Size2i(a, b)); break;
			case 14:
				// Glass background has RGB only. A transparent Stage must not
				// acquire an opaque backing rectangle behind its Scene texture.
				set_background(host_window->get_flag(Window::FLAG_TRANSPARENT) ? Color(0, 0, 0, 0) :
						Color(float((a >> 16) & 255) / 255.f, float((a >> 8) & 255) / 255.f, float(a & 255) / 255.f));
				break;
			case 15: host_window->set_flag(Window::FLAG_BORDERLESS, a != 0); break;
			case 19: set_window_input_enabled(0, a != 0); break;
			case 20: host_window->set_flag(Window::FLAG_NO_FOCUS, a == 0); break;
			case 22: case 23: restack_window(host_window, command.operation == 23); break;
			case 24:
				host_window->set_flag(Window::FLAG_TRANSPARENT, a != 0);
				host_window->set_transparent_background(a != 0);
				if (a) set_background(Color(0, 0, 0, 0));
				break;
			case 25: display->window_set_icon(godot_javafx::window_icon_image(command.icon_width, command.icon_height, command.icon_pixels), host_window->get_window_id()); break;
			case 16: case 17: case 18: window_ime_command(0,command.operation,a,b); break;
			case 26: {
#if defined(WINDOWS_ENABLED)
				const HRESULT result = godot_javafx::platform_tabtip::request();
				if (FAILED(result)) WARN_PRINT_ONCE(vformat("JavaFX touch keyboard request failed (HRESULT %d); OS keyboard availability is not guaranteed.", int64_t(result)));
#elif defined(MACOS_ENABLED)
				if (!godot_javafx::platform_tabtip::request()) { WARN_PRINT_ONCE("JavaFX touch keyboard requests are not supported on macOS; OS keyboard availability is not guaranteed."); }
#endif
			} break;
			case 27: {
#if defined(WINDOWS_ENABLED)
				const HRESULT result = godot_javafx::platform_tabtip::release();
				if (FAILED(result)) WARN_PRINT_ONCE(vformat("JavaFX touch keyboard close request failed (HRESULT %d).", int64_t(result)));
#elif defined(MACOS_ENABLED)
				if (!godot_javafx::platform_tabtip::release()) { WARN_PRINT_ONCE("JavaFX touch keyboard close requests are not supported on macOS."); }
#endif
			} break;
		}
		runtime->applied_host_sequence = command.sequence;
	}
#if defined(MACOS_ENABLED)
	// AppKit routes in-content edge/corner presses of a resizable window to
	// its native resize chrome before the content view sees them, which eats
	// exactly the presses FX resize grips sit on (Windows borders live
	// outside the client area and never conflict). FX windows own their
	// in-client input; resizing stays available through host set_size
	// commands, so the native resizable mask stays off on macOS regardless
	// of the FX resizable flag.
	if (host_window && !host_window->get_flag(Window::FLAG_RESIZE_DISABLED)) {
		host_window->set_flag(Window::FLAG_RESIZE_DISABLED, true);
	}
#endif
}

Dictionary JavaFXHost::get_window_icon_info(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), Dictionary());
	Window *window = get_window();
	if (p_id != 0) {
		auto found = native_windows.find(p_id);
		if (found == native_windows.end()) return Dictionary();
		window = found->second.window;
	}
#if defined(WINDOWS_ENABLED)
	if (!window || window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return Dictionary();
	HWND handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE, window->get_window_id()));
	HICON native_icon = reinterpret_cast<HICON>(SendMessageW(handle, WM_GETICON, ICON_BIG, 0));
	Dictionary result; result["installed"] = native_icon != nullptr;
	ICONINFO icon{};
	if (native_icon && GetIconInfo(native_icon, &icon)) {
		BITMAP bitmap{};
		if (GetObjectW(icon.hbmColor, sizeof(bitmap), &bitmap) && bitmap.bmWidth > 0 && bitmap.bmWidth <= 256 && bitmap.bmHeight > 0 && bitmap.bmHeight <= 256) {
			result["width"] = bitmap.bmWidth; result["height"] = bitmap.bmHeight;
			BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
			info.bmiHeader.biWidth = bitmap.bmWidth; info.bmiHeader.biHeight = -bitmap.bmHeight;
			info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
			std::vector<uint32_t> pixels(size_t(bitmap.bmWidth) * bitmap.bmHeight);
			HDC dc = GetDC(nullptr);
			if (dc) {
				if (GetDIBits(dc, icon.hbmColor, 0, bitmap.bmHeight, pixels.data(), &info, DIB_RGB_COLORS) == bitmap.bmHeight) {
					result["center_argb"] = int64_t(pixels[size_t(bitmap.bmHeight/2) * bitmap.bmWidth + bitmap.bmWidth/2]);
					result["corner_argb"] = int64_t(pixels[0]);
				}
				ReleaseDC(nullptr, dc);
			}
		}
		if (icon.hbmColor) DeleteObject(icon.hbmColor);
		if (icon.hbmMask) DeleteObject(icon.hbmMask);
	}
	return result;
#elif defined(MACOS_ENABLED)
	// NSWindow carries no per-window icon; nothing to read back.
	(void)window;
	Dictionary result;
	result["installed"] = false;
	return result;
#endif
}

void JavaFXHost::refresh_custom_cursor_info() {
	custom_cursor_info.clear();
	if (!custom_cursor_active || DisplayServer::get_singleton()->mouse_get_mode() != DisplayServerEnums::MOUSE_MODE_VISIBLE) return;
#if defined(WINDOWS_ENABLED)
	if (!GetCursor()) { custom_cursor_info["native_null"] = true; return; }
	// Inspect the installed Windows cursor immediately, rather than
	// merely echoing the submitted dimensions and hotspot.
	ICONINFO icon{};
	if(GetIconInfo(GetCursor(),&icon)) {
		BITMAP bitmap{};
		if(GetObjectW(icon.hbmColor,sizeof(bitmap),&bitmap)) {
			custom_cursor_info["width"]=bitmap.bmWidth; custom_cursor_info["height"]=bitmap.bmHeight;
			custom_cursor_info["hotspot_x"]=int(icon.xHotspot); custom_cursor_info["hotspot_y"]=int(icon.yHotspot);
			BITMAPINFO bitmap_info{};
			bitmap_info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
			bitmap_info.bmiHeader.biWidth=bitmap.bmWidth; bitmap_info.bmiHeader.biHeight=-bitmap.bmHeight;
			bitmap_info.bmiHeader.biPlanes=1; bitmap_info.bmiHeader.biBitCount=32; bitmap_info.bmiHeader.biCompression=BI_RGB;
			if(bitmap.bmWidth>0 && bitmap.bmWidth<=256 && bitmap.bmHeight>0 && bitmap.bmHeight<=256) {
				std::vector<uint32_t> native_pixels(size_t(bitmap.bmWidth)*bitmap.bmHeight);
				HDC dc=GetDC(nullptr);
				if(GetDIBits(dc,icon.hbmColor,0,bitmap.bmHeight,native_pixels.data(),&bitmap_info,DIB_RGB_COLORS)==bitmap.bmHeight)
					custom_cursor_info["center_argb"]=int64_t(native_pixels[size_t(bitmap.bmHeight/2)*bitmap.bmWidth+bitmap.bmWidth/2]);
				ReleaseDC(nullptr,dc);
			}
		}
		if(icon.hbmColor) DeleteObject(icon.hbmColor);
		if(icon.hbmMask) DeleteObject(icon.hbmMask);
	}
#elif defined(MACOS_ENABLED)
	// Inspect the installed Cocoa cursor, mirroring the Windows readback
	// instead of echoing the submitted dimensions and hotspot.
	int32_t width = 0, height = 0, hotspot_x = 0, hotspot_y = 0;
	uint32_t center_argb = 0;
	bool native_null = false;
	if (!godot_javafx::macos_cursor_info(width, height, hotspot_x, hotspot_y, center_argb, native_null)) return;
	if (native_null) { custom_cursor_info["native_null"] = true; return; }
	custom_cursor_info["width"] = width;
	custom_cursor_info["height"] = height;
	custom_cursor_info["hotspot_x"] = hotspot_x;
	custom_cursor_info["hotspot_y"] = hotspot_y;
	custom_cursor_info["center_argb"] = int64_t(center_argb);
#endif
}

void JavaFXHost::stop_host() {
	ERR_FAIL_COND(!Thread::is_main_thread());
	if (borrowed_vm) godot_javafx::bridge_open.store(false);
	restore_vsync_pacing();
    if (runtime) runtime->dialogs.stop();
    if (runtime) {
        std::lock_guard<std::mutex> lock(runtime->dnd_mutex);
        runtime->dnd_pending.reset();
    }
    // Detach native drag delegates before the windows they reference go away;
    // the delegate userdata points at the TargetHandler owned by this host.
    {
#if defined(WINDOWS_ENABLED)
        auto *display = static_cast<DisplayServerWindows *>(DisplayServer::get_singleton());
        for (const auto &entry : drag_targets) {
            if (entry.first && entry.first->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
                display->window_set_drag_delegate(entry.first->get_window_id(), nullptr, nullptr);
        }
#elif defined(MACOS_ENABLED)
        for (const auto &entry : drag_targets) {
            if (entry.first && entry.first->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
                godot_javafx::macos_window_set_drag_delegate(entry.first->get_window_id(), nullptr, nullptr);
        }
#endif
        drag_targets.clear();
    }
	if(custom_cursor_active) {
		DisplayServer::get_singleton()->cursor_set_custom_image(Ref<Resource>(),DisplayServerEnums::CURSOR_ARROW);
		custom_cursor_active=false; custom_cursor_info.clear();
	}
	if (managed_cursor_state) {
		DisplayServer::get_singleton()->mouse_set_mode(DisplayServerEnums::MouseMode(previous_mouse_mode));
		managed_cursor_state = false;
	}
	// Restore the Viewport's per-motion fallback cursor shape from before the
	// JavaFX runtime started managing it.
	if (default_cursor_state_saved) {
		Input::get_singleton()->set_default_cursor_shape_quiet(InputClassEnums::CursorShape(previous_default_cursor_shape));
		default_cursor_state_saved = false;
	}
	held_buttons.clear();
	geometry_meshes.clear();
	if (runtime) runtime->stop_readbacks();
	// Close window admission before destroying peers, so a queued create cannot
	// resurrect a window while the Host remains in the scene tree. The Godot main
	// thread owns destruction; Java shutdown need not submit more window commands.
	if (runtime) runtime->native_window_transport.stop();
	while (!native_windows.empty()) destroy_native_window(native_windows.begin()->first);
	if (runtime) runtime->native_window_transport.publish({}, native_window_sequence);
	if (runtime) runtime->queue.stop();
	if (borrowed_vm) {
		// The library's platform thread remains attached throughout the engine loop.
		JNIEnv *env = nullptr;
		ERR_FAIL_COND(borrowed_vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_8) != JNI_OK);
		if (jclass retained = runtime->drag_upcall.close()) env->DeleteGlobalRef(retained);
		std::unique_lock lock(godot_javafx::bridge_lifetime);
		godot_javafx::jni_runtime = nullptr;
		runtime->status.store(godot_javafx::RuntimeStatus::FINISHED);
		borrowed_vm = nullptr;
	}
}

void JavaFXHost::apply_readback() {
	std::shared_ptr<godot_javafx::ReadbackRequest> request;
	{
		std::lock_guard<std::mutex> lock(runtime->readback_mutex);
		request = runtime->readback;
		if (!request || request->done || runtime->readbacks_stopped ||
				runtime->completed_render_sequence.load() < request->sequence) return;
	}
	// Only this main-thread consumer touches Godot resources. The render caller
	// stays blocked, so it cannot rewrite/dispose its locked source during capture.
	std::vector<jint> pixels;
	std::string error;
	try {
		auto source = find_render_target(request->handle);
		if (source.is_null()) error = "Readback source is not a live render target";
		else if (active_target == source) error = "Readback source still has an unfinished render pass";
		else if (int64_t(request->x) + request->width > source->get_size().x ||
				int64_t(request->y) + request->height > source->get_size().y) error = "Readback rectangle exceeds render target";
		else {
			// A new allocation already scheduled an initial transparent clear.
			// Complete that once, without reopening/redrawing a previously read RT.
			if (!source->has_initialized_contents()) {
				auto *rs = RenderingServer::get_singleton();
				rs->draw(false, 0.0); rs->sync(); source->finish_pass();
			}
			Ref<Image> image =
					RenderingServer::get_singleton()->texture_2d_get(source->get_texture());

			if (image.is_null() || image->is_empty() || image->get_width() < request->x + request->width ||
					image->get_height() < request->y + request->height) error = "Render target has no complete readable image";
			else {
				image->convert(Image::FORMAT_RGBA8);
				const PackedByteArray data = image->get_data();
				pixels.resize(size_t(request->width) * request->height);
				for (int y = 0; y < request->height; ++y) {
					const uint8_t *row = data.ptr() + (size_t(request->y + y) * image->get_width() + request->x) * 4;
					for (int x = 0; x < request->width; ++x) {
						const uint8_t *p = row + x * 4;
						pixels[size_t(y) * request->width + x] = jint((uint32_t(p[3]) << 24) | (uint32_t(p[0]) << 16) | (uint32_t(p[1]) << 8) | p[2]);
					}
				}
			}
		}
	} catch (const std::bad_alloc &) { error = "Cannot allocate readback pixel storage"; }
	{
		std::lock_guard<std::mutex> lock(runtime->readback_mutex);
		request->pixels = std::move(pixels); request->error = std::move(error); request->done = true;
		runtime->readback_changed.notify_all();
	}
}

void JavaFXHost::apply_native_window_commands() {
	godot_javafx::NativeWindowCommand command;
	for (int count=0; count<256 && runtime->native_window_transport.take(command); ++count) {
		bool accepted=true;
		Rect2i bounds(command.x,command.y,command.width,command.height);
		if (command.operation==1) accepted=create_native_window(command.id,command.owner,bounds,
				String::utf16(command.title.data(),int(command.title.size())),command.flags);
		else if (command.operation==2) accepted=configure_native_window(command.id,bounds,command.visible);
		else if (command.operation==3) destroy_native_window(command.id);
		else if (command.operation==5) {
			auto found = native_windows.find(command.id);
			accepted = found != native_windows.end();
			if (accepted) DisplayServer::get_singleton()->window_set_icon(godot_javafx::window_icon_image(command.width, command.height, command.icon_pixels), found->second.window->get_window_id());
		}
		else accepted=set_native_window_property(command.id,command.flags,command.x,command.y,
				String::utf16(command.title.data(),int(command.title.size())));
		if (!accepted) { runtime->fail("Native window command could not be applied"); return; }
		native_window_sequence=command.sequence;
	}
	std::map<int64_t,godot_javafx::NativeWindowSnapshot> snapshots;
	for (const auto &entry : native_windows) {
		auto *window=entry.second.window;
		Point2i pos=window->get_position(); Size2i size=window->get_size();
		snapshots.emplace(entry.first,godot_javafx::NativeWindowSnapshot{entry.first,entry.second.owner,window->get_window_id(),
			pos.x,pos.y,size.x,size.y,window->is_visible()?1:0,window->has_focus()?1:0,int(window->get_mode()),native_window_sequence});
	}
	runtime->native_window_transport.publish(std::move(snapshots),native_window_sequence);
}

#if defined(WINDOWS_ENABLED)
// DisplayServerWindows drag delegate: OLE callbacks arrive on the Godot main
// thread, which owns every TargetHandler, so no locking is needed here.
static bool javafx_drag_delegate(void *p_userdata, int p_kind, void *p_data_object, DWORD p_key_state, POINTL p_point, DWORD *r_effect) {
	auto *handler = static_cast<godot_javafx::windows_dnd::TargetHandler *>(p_userdata);
	if (!handler) return false;
	return handler->handle(p_kind, static_cast<IDataObject *>(p_data_object), p_key_state, p_point, r_effect);
}
#elif defined(MACOS_ENABLED)
// DisplayServerMacOS drag delegate: Cocoa dragging callbacks arrive on the
// Godot main thread, which owns every TargetHandler, so no locking is needed.
static bool javafx_drag_delegate(void *p_userdata, int p_kind, void *p_sender, int p_x, int p_y, uint32_t *r_effect) {
	auto *handler = static_cast<godot_javafx::macos_dnd::TargetHandler *>(p_userdata);
	if (!handler) return false;
	return handler->handle(p_kind, p_sender, p_x, p_y, r_effect);
}
#endif

void JavaFXHost::refresh_drag_delegates() {
#if defined(WINDOWS_ENABLED)
	if (!runtime || !is_inside_tree()) return;
	std::map<Window *, int64_t> current;
	current[get_window()] = 0;
	for (const auto &entry : native_windows) current[entry.second.window] = entry.first;
	// Handlers for destroyed windows are dropped in destroy_native_window; this
	// sweep only covers windows removed outside that path. The WindowData (and
	// its delegate pointer) is destroyed together with the Window.
	for (auto it = drag_targets.begin(); it != drag_targets.end();) {
		if (current.count(it->first)) { ++it; continue; }
		it = drag_targets.erase(it);
	}
	// A closed gate means the JVM is leaving; OLE upcalls must stop.
	godot_javafx::windows_dnd::Upcall upcall{ &runtime->drag_upcall };
	auto *display = static_cast<DisplayServerWindows *>(DisplayServer::get_singleton());
	if (!upcall) {
		for (const auto &entry : drag_targets) {
			if (entry.first && entry.first->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
				display->window_set_drag_delegate(entry.first->get_window_id(), nullptr, nullptr);
		}
		drag_targets.clear();
		return;
	}
	for (const auto &entry : current) {
		Window *window = entry.first;
		if (!window || window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) continue;
		if (drag_targets.count(window)) continue;
		auto handler = std::make_unique<godot_javafx::windows_dnd::TargetHandler>();
		handler->id = entry.second;
		handler->upcall = upcall;
		if (display->window_set_drag_delegate(window->get_window_id(), &javafx_drag_delegate, handler.get()) != OK) {
			runtime->fail("Cannot register the native OLE drag target for a JavaFX window");
			return;
		}
		drag_targets[window] = std::move(handler);
	}
#elif defined(MACOS_ENABLED)
	if (!runtime || !is_inside_tree()) return;
	std::map<Window *, int64_t> current;
	current[get_window()] = 0;
	for (const auto &entry : native_windows) current[entry.second.window] = entry.first;
	// Handlers for destroyed windows are dropped in destroy_native_window; this
	// sweep only covers windows removed outside that path. The WindowData (and
	// its delegate pointer) is destroyed together with the Window.
	for (auto it = drag_targets.begin(); it != drag_targets.end();) {
		if (current.count(it->first)) { ++it; continue; }
		it = drag_targets.erase(it);
	}
	// A closed gate means the JVM is leaving; Cocoa upcalls must stop.
	godot_javafx::macos_dnd::Upcall upcall{ &runtime->drag_upcall };
	if (!upcall) {
		for (const auto &entry : drag_targets) {
			if (entry.first && entry.first->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
				godot_javafx::macos_window_set_drag_delegate(entry.first->get_window_id(), nullptr, nullptr);
		}
		drag_targets.clear();
		return;
	}
	for (const auto &entry : current) {
		Window *window = entry.first;
		if (!window || window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) continue;
		if (drag_targets.count(window)) continue;
		auto handler = std::make_unique<godot_javafx::macos_dnd::TargetHandler>();
		handler->id = entry.second;
		handler->upcall = upcall;
		if (!godot_javafx::macos_window_set_drag_delegate(window->get_window_id(),
				reinterpret_cast<void *>(&javafx_drag_delegate), handler.get())) {
			runtime->fail("Cannot register the Cocoa drag target for a JavaFX window");
			return;
		}
		drag_targets[window] = std::move(handler);
	}
#endif
}

// Test hook: feeds the module's own OLE source DataObject through the inbound
// drag delegate, verifying the outbound format exposure and the inbound
// extractor/dispatch without a physical mouse or the modal OLE loop. The real
// cross-process gesture remains covered by the external drag/drop fixture.
bool JavaFXHost::simulate_external_drop(const Vector2i &p_point, const String &p_text, const String &p_url,
		const PackedStringArray &p_files, const String &p_custom_name, const PackedByteArray &p_custom_data) {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	if (!runtime) return false;
#if defined(WINDOWS_ENABLED)
	refresh_drag_delegates();
	auto it = drag_targets.find(get_window());
	if (it == drag_targets.end()) return false;
	auto to_u16 = [](const String &p_value) {
		Char16String wide = p_value.utf16();
		return std::u16string(reinterpret_cast<const char16_t *>(wide.get_data()), size_t(wide.length()));
	};
	godot_javafx::windows_dnd::SourceData data;
	data.text = to_u16(p_text);
	data.url = to_u16(p_url);
	for (int i = 0; i < p_files.size(); ++i) data.files.push_back(to_u16(p_files[i]));
	if (!p_custom_name.is_empty()) {
		Char16String name16 = p_custom_name.utf16();
		std::wstring name(reinterpret_cast<const wchar_t *>(name16.get_data()), size_t(name16.length()));
		ERR_FAIL_COND_V_MSG(!godot_javafx::custom_format::valid_name(name), false, "Invalid custom drag format name");
		std::string bytes;
		if (!p_custom_data.is_empty()) bytes.assign(reinterpret_cast<const char *>(p_custom_data.ptr()), size_t(p_custom_data.size()));
		if (bytes.empty() || bytes.back() != 0) bytes.push_back(0);
		ERR_FAIL_COND_V_MSG(bytes.size() > godot_javafx::custom_format::MAX_DATA_BYTES, false, "Custom drag payload exceeds 16 MiB");
		data.custom.emplace_back(std::move(name), std::move(bytes));
	}
	auto *object = new godot_javafx::windows_dnd::DataObject(std::move(data));
	POINTL point{ p_point.x, p_point.y };
	DWORD enter_effect = DROPEFFECT_COPY;
	bool entered = it->second->handle(1, object, 0, point, &enter_effect);
	bool dropped = false;
	if (entered) {
		DWORD drop_effect = DROPEFFECT_COPY;
		// A rejected drop still clears the handler's enter state.
		dropped = it->second->handle(4, object, 0, point, &drop_effect) && drop_effect != DROPEFFECT_NONE;
	}
	object->Release();
	return dropped;
#elif defined(MACOS_ENABLED)
	refresh_drag_delegates();
	auto it = drag_targets.find(get_window());
	if (it == drag_targets.end()) return false;
	auto to_u16 = [](const String &p_value) {
		Char16String wide = p_value.utf16();
		return std::u16string(reinterpret_cast<const char16_t *>(wide.get_data()), size_t(wide.length()));
	};
	godot_javafx::macos_dnd::SourceData data;
	data.text = to_u16(p_text);
	data.url = to_u16(p_url);
	for (int i = 0; i < p_files.size(); ++i) data.files.push_back(to_u16(p_files[i]));
	if (!p_custom_name.is_empty()) {
		std::u16string name = to_u16(p_custom_name);
		ERR_FAIL_COND_V_MSG(!godot_javafx::custom_format::valid_name(name), false, "Invalid custom drag format name");
		std::string bytes;
		if (!p_custom_data.is_empty()) bytes.assign(reinterpret_cast<const char *>(p_custom_data.ptr()), size_t(p_custom_data.size()));
		if (bytes.empty() || bytes.back() != 0) bytes.push_back(0);
		ERR_FAIL_COND_V_MSG(bytes.size() > godot_javafx::custom_format::MAX_DATA_BYTES, false, "Custom drag payload exceeds 16 MiB");
		data.custom.emplace_back(std::move(name), std::move(bytes));
	}
	return godot_javafx::macos_dnd::simulate_drop(*it->second, p_point.x, p_point.y, data);
#endif
}

void JavaFXHost::run_dnd_source(std::unique_ptr<godot_javafx::platform_dnd::SourceData> p_data) {
	ERR_FAIL_COND(!Thread::is_main_thread());
#if defined(WINDOWS_ENABLED)
	Window *source = p_data->source_id ? get_native_window(p_data->source_id) : get_window();
	HWND handle = nullptr;
	if (source && source->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
		handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(
				DisplayServerEnums::WINDOW_HANDLE, source->get_window_id()));
	if (handle) {
		// Balance Godot's per-button SetCapture before OLE takes the mouse. The
		// Java drag session is in external mode and swallows these release records.
		POINT cursor{};
		GetCursorPos(&cursor);
		ScreenToClient(handle, &cursor);
		LPARAM where = MAKELPARAM(cursor.x, cursor.y);
		if (p_data->buttons & 2) SendMessageW(handle, WM_LBUTTONUP, 0, where);
		if (p_data->buttons & 4) SendMessageW(handle, WM_RBUTTONUP, 0, where);
		if (p_data->buttons & 8) SendMessageW(handle, WM_MBUTTONUP, 0, where);
	}
	DWORD effect = 0;
	DWORD allowed = p_data->effects;
	auto drag_preview = std::move(p_data->image);
	auto *object = new (std::nothrow) godot_javafx::windows_dnd::DataObject(std::move(*p_data));
	auto *source_impl = new (std::nothrow) godot_javafx::windows_dnd::DropSource;
	if (object && source_impl) {
		// The shell preview must be registered before the modal OLE loop starts.
		godot_javafx::windows_dnd::apply_drag_image(object, drag_preview);
		HRESULT result = DoDragDrop(object, source_impl, allowed, &effect);
		if (result != DRAGDROP_S_DROP) effect = 0;
	}
	if (object) object->Release();
	if (source_impl) source_impl->Release();
	if (runtime->status.load() != godot_javafx::RuntimeStatus::RUNNING) return;
	std::lock_guard<std::mutex> lock(runtime->host_mutex);
	if (runtime->input_events.size() >= 4096) runtime->fail("Glass input queue overflow on drag completion");
	else {
		runtime->input_events.push_back({ 20.0, double(effect), 0, 0, 0, 0, 0, 0, 0, 0 });
		runtime->queue.pulse_input();
	}
#elif defined(MACOS_ENABLED)
	Window *source = p_data->source_id ? get_native_window(p_data->source_id) : get_window();
	void *handle = nullptr;
	if (source && source->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
		handle = reinterpret_cast<void *>(DisplayServer::get_singleton()->window_get_native_handle(
				DisplayServerEnums::WINDOW_HANDLE, source->get_window_id()));
	if (handle && !p_data->custom.empty()) {
		// Inbound drags only reach the delegate for registered pasteboard types;
		// advertise this source's custom formats on every drag target window.
		std::vector<std::u16string> types;
		for (const auto &entry : p_data->custom) types.push_back(entry.first);
		for (const auto &entry : drag_targets) {
			if (entry.first && entry.first->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
				godot_javafx::macos_window_register_drag_types(entry.first->get_window_id(), types);
		}
	}
	// The dragging session is asynchronous; box the runtime so the completion
	// callback can deliver the effect record after this call returns, and fails
	// safe once the runtime stopped.
	auto box = std::make_unique<std::shared_ptr<godot_javafx::Runtime>>(runtime);
	bool started = handle && godot_javafx::macos_dnd::begin_source(*p_data, source->get_window_id(), handle,
			[](void *ctx, uint32_t effect) {
				std::unique_ptr<std::shared_ptr<godot_javafx::Runtime>> box(static_cast<std::shared_ptr<godot_javafx::Runtime> *>(ctx));
				const std::shared_ptr<godot_javafx::Runtime> &runtime = *box;
				if (runtime->status.load() != godot_javafx::RuntimeStatus::RUNNING) return;
				std::lock_guard<std::mutex> lock(runtime->host_mutex);
				if (runtime->input_events.size() >= 4096) runtime->fail("Glass input queue overflow on drag completion");
				else {
					runtime->input_events.push_back({ 20.0, double(effect), 0, 0, 0, 0, 0, 0, 0, 0 });
					runtime->queue.pulse_input();
				}
			}, box.get());
	if (started) box.release();
	else {
		ERR_PRINT("JavaFX macOS drag session could not start");
		if (runtime->status.load() == godot_javafx::RuntimeStatus::RUNNING) {
			std::lock_guard<std::mutex> lock(runtime->host_mutex);
			if (runtime->input_events.size() >= 4096) runtime->fail("Glass input queue overflow on drag completion");
			else {
				runtime->input_events.push_back({ 20.0, 0.0, 0, 0, 0, 0, 0, 0, 0, 0 });
				runtime->queue.pulse_input();
			}
		}
	}
#endif
}

String JavaFXHost::get_runtime_status() const {
	if (!runtime) return "idle";
	switch (runtime->status.load()) {
		case godot_javafx::RuntimeStatus::STARTING: return "starting";
		case godot_javafx::RuntimeStatus::RUNNING: return "running";
		case godot_javafx::RuntimeStatus::FINISHED: return "finished";
		case godot_javafx::RuntimeStatus::FAILED: return "failed";
	}
	return "failed";
}

String JavaFXHost::get_runtime_error() const {
	if (!runtime) return String();
	std::lock_guard<std::mutex> lock(runtime->error_mutex);
	return String::utf8(runtime->error.c_str());
}

int64_t JavaFXHost::get_backpressure_count() const {
	return runtime ? int64_t(runtime->queue.get_backpressure_count()) : 0;
}

JavaFXHost::~JavaFXHost() {
	stop_host();
	if (worker.joinable()) {
		// Never wait for Java application threads on the Godot main thread.
		// The fixture worker retains Runtime until the probe returns, even after the node
		// is removed. A finished worker can be joined without a Java callback.
		if (runtime->status.load() == godot_javafx::RuntimeStatus::FINISHED) worker.join();
		else worker.detach();
	}
}
