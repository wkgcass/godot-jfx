#include "javafx_host.h"
#include "native_window_transport.h"
#include "core/os/thread.h"
#include "core/object/callable_mp.h"

bool JavaFXHost::create_native_window(int64_t p_id, int64_t p_owner, const Rect2i &p_bounds, const String &p_title, int p_flags) {
	if (!Thread::is_main_thread() || !is_inside_tree() || p_id <= 0 || p_owner < -1 ||
			native_windows.count(p_id) || native_windows.size() >= 64 ||
			(p_owner > 0 && !native_windows.count(p_owner)) || !godot_javafx::valid_native_window_flags(p_flags, p_owner) ||
			p_bounds.size.x <= 0 || p_bounds.size.y <= 0 || p_bounds.size.x > 8192 || p_bounds.size.y > 8192) return false;
	auto *window = memnew(JavaFXNativeWindow);
	window->set_title(p_title);
	window->set_flag(Window::FLAG_BORDERLESS, (p_flags & 1) != 0);
	window->set_flag(Window::FLAG_TRANSPARENT, (p_flags & 2) != 0);
	window->set_flag(Window::FLAG_POPUP, (p_flags & 4) != 0);
	if (p_flags & 8) window->set_flag(Window::FLAG_POPUP_WM_HINT, true);
	window->set_size(p_bounds.size);
	window->set_position(p_bounds.position);
	// Owner -1 denotes the primary Stage mapped to the existing root Window.
	Node *parent = p_owner > 0 ? static_cast<Node *>(native_windows.at(p_owner).window) : this;
	parent->add_child(window);
	if (p_owner) window->set_transient(true);
	native_windows.emplace(p_id, NativeWindowEntry{window, p_owner, bool(p_flags & godot_javafx::NATIVE_WINDOW_MODAL_HINT)});
	window->connect("window_input", callable_mp(this, &JavaFXHost::window_input).bind(p_id));
	window->connect("close_requested", callable_mp(this, &JavaFXHost::window_event).bind(9, p_id));
	window->connect("mouse_entered", callable_mp(this, &JavaFXHost::window_event).bind(7, p_id));
	window->connect("mouse_exited", callable_mp(this, &JavaFXHost::window_event).bind(8, p_id));
	window->connect("focus_entered", callable_mp(this, &JavaFXHost::window_event).bind(15, p_id));
	window->connect("focus_exited", callable_mp(this, &JavaFXHost::window_event).bind(16, p_id));
	return true;
}

JavaFXNativeWindow *JavaFXHost::get_native_window(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), nullptr);
	auto entry = native_windows.find(p_id);
	return entry == native_windows.end() ? nullptr : entry->second.window;
}

Dictionary JavaFXHost::get_native_window_info(int64_t p_id) const {
	Dictionary result;
	auto *window = get_native_window(p_id);
	if (!window) return result;
	result["id"] = p_id;
	result["owner"] = native_windows.at(p_id).owner;
	result["native_id"] = window->get_window_id();
	result["position"] = window->get_position();
	result["size"] = window->get_size();
	result["visible"] = window->is_visible();
	result["focused"] = window->has_focus();
	result["mode"] = window->get_mode();
	result["ime_enabled"] = native_windows.at(p_id).ime_enabled;
	result["ime_position"] = native_windows.at(p_id).ime_position;
	return result;
}
