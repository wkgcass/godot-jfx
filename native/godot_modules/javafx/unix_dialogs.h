#pragma once

#include <jni.h>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

// File-dialog service with the same queueing contract as the Windows backend.
// NSOpenPanel/NSSavePanel are presented on the AppKit main thread (which is
// the Godot main thread) via beginSheetModalForWindow/beginWithCompletionHandler,
// so the host loop keeps running while a chooser is open. The Cocoa half lives
// in macos_dialogs.mm; this header stays Objective-C free because the host's
// JNI translation unit is plain C++.
namespace godot_javafx::unix_dialogs {
struct Request {
	int64_t owner = -1;
	int mode = 0, selected = 0; // open, multi-open, save, directory
	std::u16string folder, filename, title;
	std::vector<std::u16string> names, patterns, files;
	std::string error;
#ifdef LINUXBSD_ENABLED
	std::string exported_parent;
#endif
	std::atomic<bool> cancel{ false }, done{ false };
	bool started = false;
};

class Service;

// Cocoa panel lifecycle (macos_dialogs.mm). present() runs on the AppKit main
// thread, retains the panel until its completion handler fires, and returns
// the panel identity. abort() cancels a presented panel (its completion
// handler reports the cancellation); detach() drops the Service back-reference
// before the service dies while a panel dismissal is still in flight.
void *panel_present(const std::shared_ptr<Request> &p_request, Service *p_service, void *p_owner);
void panel_abort(void *p_panel);
void panel_detach(Service *p_service);
#ifdef LINUXBSD_ENABLED
void panel_pump();
#endif

class Service {
	std::mutex mutex;
	std::shared_ptr<Request> active;
	void *panel = nullptr; // Cocoa panel identity; touched on the main thread only.
	std::thread hook_worker; // Module test hook driver (GODOT_JFX_DIALOG_HOOK).
	bool stopped = false;

	// Physical UI automation (real keystrokes on a native panel) is a robot
	// concern and needs accessibility permissions. Tests instead enable a
	// module hook that drives the same submit/poll/cancel contract without
	// AppKit: GODOT_JFX_DIALOG_HOOK=1 completes requests deterministically.
	// Titles carry " case N": case 4 auto-cancels, case 5 and the host-stop
	// mode (GODOT_JFX_DIALOG_READY set) stay open until cancelled.
	static bool hook_enabled() {
		const char *hook = std::getenv("GODOT_JFX_DIALOG_HOOK");
		return hook && hook[0] == '1' && hook[1] == 0;
	}

	static int hook_case(const Request &r) {
		const std::u16string marker = u" case ";
		const size_t at = r.title.rfind(marker);
		if (at == std::u16string::npos) return -1;
		int value = 0;
		for (size_t i = at + marker.size(); i < r.title.size() && r.title[i] >= u'0' && r.title[i] <= u'9'; ++i)
			value = value * 10 + int(r.title[i] - u'0');
		return value;
	}

	// Windows drives the real dialog's filename box, whose multi-selection is
	// a space-separated list of quoted names; mirror that parsing here.
	static std::vector<std::u16string> hook_selection(const Request &r) {
		std::vector<std::u16string> names;
		std::u16string current;
		bool quoted = false;
		auto flush = [&]() {
			if (current.empty()) return;
			names.push_back(current);
			current.clear();
		};
		for (char16_t c : r.filename) {
			if (c == u'"') { quoted = !quoted; continue; }
			if (c == u' ' && !quoted) { flush(); continue; }
			current += c;
		}
		flush();
		return names;
	}

	void run_hook(const std::shared_ptr<Request> &r) {
		const char *ready = std::getenv("GODOT_JFX_DIALOG_READY");
		if (ready && *ready) {
			if (FILE *file = std::fopen(ready, "w")) {
				std::fputs("native-dialog-observed", file);
				std::fclose(file);
			}
		}
		// The physical driver waits before answering a dialog; keep the request
		// open briefly so the probe observes the FX loop ticking meanwhile.
		const int dialog_case = hook_case(*r);
		const bool wait_for_cancel = dialog_case == 5 || (ready && *ready);
		// Cancellation-driven cases stay open until dialogCancel (or stop())
		// arrives; the bound only guards against a wedged probe.
		const int limit = wait_for_cancel ? 30000 : 600;
		for (int waited = 0; waited < limit; waited += 10) {
			if (r->cancel.load(std::memory_order_acquire)) break;
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
		try {
			if (r->cancel.load(std::memory_order_acquire) || wait_for_cancel || dialog_case == 4) {
				r->selected = -1;
			} else {
				const std::u16string base = r->folder;
				auto join = [&base](const std::u16string &name) {
					if (base.empty() || (!name.empty() && name[0] == u'/')) return name;
					return base + (base.back() == u'/' ? u"" : u"/") + name;
				};
				if (r->mode == 3) {
					if (!base.empty()) r->files.push_back(base);
					else r->selected = -1;
				} else if (r->mode == 1) {
					for (const auto &name : hook_selection(*r)) r->files.push_back(join(name));
					if (r->files.empty()) r->selected = -1;
				} else {
					if (!r->filename.empty()) r->files.push_back(join(r->filename));
					else r->selected = -1;
				}
				if (r->selected != -1 && r->names.empty()) r->selected = -1;
			}
		} catch (const std::bad_alloc &) {
			r->error = "Dialog hook allocation failed";
		}
		r->done.store(true, std::memory_order_release);
	}

public:
	~Service() { stop(); }
	void submit(std::shared_ptr<Request> request) {
		std::lock_guard<std::mutex> lock(mutex);
		if (stopped) throw std::runtime_error("File-dialog service stopped");
		if (active) throw std::runtime_error("A file dialog is already open");
		active = std::move(request);
	}
	std::shared_ptr<Request> pending() {
		std::lock_guard<std::mutex> lock(mutex);
		return active && !active->started ? active : nullptr;
	}
	// Main thread (AppKit). owner is the NSWindow * of a live owner window.
	void start(const std::shared_ptr<Request> &r, void *owner, bool valid_owner) {
		{
			std::lock_guard<std::mutex> lock(mutex);
			if (active != r || r->started) return;
			r->started = true;
			if (stopped || !valid_owner || r->cancel.load()) {
				r->selected = -1;
				r->done.store(true);
				return;
			}
		}
		if (hook_enabled()) {
			try {
				hook_worker = std::thread(&Service::run_hook, this, r);
			} catch (const std::exception &e) {
				r->error = e.what();
				r->done.store(true);
			}
			return;
		}
		try {
			void *created = panel_present(r, this, owner);
			std::lock_guard<std::mutex> lock(mutex);
			panel = created;
		} catch (const std::exception &e) {
			r->error = e.what();
			r->done.store(true);
		}
	}
	// Main thread, every frame: dismiss a presented panel once cancellation is
	// requested from the FX thread (dialogCancel is not an AppKit thread).
	void pump() {
#ifdef LINUXBSD_ENABLED
		panel_pump();
#endif
		std::shared_ptr<Request> r;
		void *target = nullptr;
		{
			std::lock_guard<std::mutex> lock(mutex);
			r = active;
			target = panel;
		}
		if (r && r->started && target && r->cancel.load(std::memory_order_acquire)) panel_abort(target);
	}
	void cancel() {
		std::lock_guard<std::mutex> lock(mutex);
		if (active) active->cancel.store(true);
	}
	// Called by the Cocoa completion handler on the main thread.
	void panel_closed(void *p_panel) {
		std::lock_guard<std::mutex> lock(mutex);
		if (panel == p_panel) panel = nullptr;
	}
	std::shared_ptr<Request> take_result() {
		std::shared_ptr<Request> result;
		{
			std::lock_guard<std::mutex> lock(mutex);
			if (!active || !active->done.load(std::memory_order_acquire)) return nullptr;
			result = active;
			active.reset();
		}
		if (hook_worker.joinable()) hook_worker.join();
		return result;
	}
	void stop() {
		std::shared_ptr<Request> r;
		void *target = nullptr;
		{
			std::lock_guard<std::mutex> lock(mutex);
			stopped = true;
			r = active;
			target = panel;
			if (r) {
				r->cancel.store(true);
				if (!r->started) {
					r->selected = -1;
					r->done.store(true);
				}
			}
		}
		// stop() normally runs on the Godot main thread (stop_host), where the
		// Cocoa abort is safe; the destructor's later call finds panel cleared.
		if (target) {
			panel_abort(target);
			panel_detach(this);
		}
		if (hook_worker.joinable()) hook_worker.join();
	}
};
inline void fail(JNIEnv *env, const char *type, const char *message) {
	jclass cls = env->FindClass(type);
	if (cls) { env->ThrowNew(cls, message); env->DeleteLocalRef(cls); }
}
inline std::u16string string(JNIEnv *env, jstring value) {
	if (!value) return {};
	jsize n = env->GetStringLength(value);
	if (n > 32768) throw std::invalid_argument("Dialog string exceeds 32768 characters");
	const jchar *data = env->GetStringChars(value, nullptr);
	if (!data) throw std::runtime_error("Cannot copy dialog string");
	std::u16string result;
	try { result.assign(reinterpret_cast<const char16_t *>(data), size_t(n)); }
	catch (...) { env->ReleaseStringChars(value, data); throw; }
	env->ReleaseStringChars(value, data);
	if (result.find(u'\0') != std::u16string::npos) throw std::invalid_argument("Dialog string contains NUL");
	return result;
}
inline void submit(JNIEnv *env, Service &service, jlong owner, jint mode, jstring folder, jstring filename, jstring title, jobjectArray filters, jint selected) {
	try {
		if (owner < -1 || mode < 0 || mode > 3) throw std::invalid_argument("Invalid dialog mode/owner");
		auto r = std::make_shared<Request>();
		r->owner = owner; r->mode = mode; r->selected = selected;
		r->folder = string(env, folder); r->filename = string(env, filename); r->title = string(env, title);
		jsize n = filters ? env->GetArrayLength(filters) : 0;
		if (n % 2 || n > 256 || (n && (selected < 0 || selected >= n / 2))) throw std::invalid_argument("Invalid dialog filters");
		for (jsize i = 0; i < n; ++i) {
			auto text = static_cast<jstring>(env->GetObjectArrayElement(filters, i));
			auto value = string(env, text);
			env->DeleteLocalRef(text);
			if (value.empty()) throw std::invalid_argument("Empty dialog filter");
			(i % 2 ? r->patterns : r->names).push_back(std::move(value));
		}
		service.submit(std::move(r));
	} catch (const std::invalid_argument &e) { if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalArgumentException", e.what()); }
	catch (const std::exception &e) { if (!env->ExceptionCheck()) fail(env, "java/lang/IllegalStateException", e.what()); }
}
inline jobjectArray poll(JNIEnv *env, Service &service) {
	auto r = service.take_result();
	if (!r) return nullptr;
	if (!r->error.empty()) { fail(env, "java/lang/IllegalStateException", r->error.c_str()); return nullptr; }
	jclass type = env->FindClass("java/lang/String");
	if (!type) return nullptr;
	jobjectArray result = env->NewObjectArray(static_cast<jsize>(r->files.size() + 1), type, nullptr);
	env->DeleteLocalRef(type);
	if (!result) return nullptr;
	std::u16string index;
	try { const std::string ascii = std::to_string(r->selected); index.assign(ascii.begin(), ascii.end()); }
	catch (const std::bad_alloc &) { fail(env, "java/lang/OutOfMemoryError", "Dialog result allocation failed"); return nullptr; }
	for (size_t i = 0; i <= r->files.size(); ++i) {
		const auto &value = i ? r->files[i - 1] : index;
		jstring text = env->NewString(reinterpret_cast<const jchar *>(value.data()), static_cast<jsize>(value.size()));
		if (!text) return nullptr;
		env->SetObjectArrayElement(result, static_cast<jsize>(i), text);
		env->DeleteLocalRef(text);
		if (env->ExceptionCheck()) return nullptr;
	}
	return result;
}
}
