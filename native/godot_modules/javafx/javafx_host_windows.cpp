#include "javafx_host.h"

#ifdef WINDOWS_ENABLED

#include "windows_dnd.h"
#include "core/os/thread.h"
#include "core/object/callable_mp.h"
#include "servers/rendering/rendering_server.h"
#include "servers/display/display_server.h"
#include "platform/windows/display_server_windows.h"
#include <windows.h>
#include <vector>

// Main-thread half of identity-aware Glass transport. No JNI caller may invoke
// these directly: the host command consumer will own all mutations.
bool JavaFXHost::create_native_window(int64_t p_id, int64_t p_owner, const Rect2i &p_bounds, const String &p_title, int p_flags) {
	if (!Thread::is_main_thread() || !is_inside_tree() || p_id <= 0 || p_owner < -1 ||
			native_windows.count(p_id) || native_windows.size() >= 64 ||
			(p_owner > 0 && !native_windows.count(p_owner)) || p_flags < 0 || p_flags > 7 ||
			p_bounds.size.x <= 0 || p_bounds.size.y <= 0 || p_bounds.size.x > 8192 || p_bounds.size.y > 8192) return false;
	auto *window = memnew(JavaFXNativeWindow);
	window->set_title(p_title);
	window->set_flag(Window::FLAG_BORDERLESS, (p_flags & 1) != 0);
	window->set_flag(Window::FLAG_TRANSPARENT, (p_flags & 2) != 0);
	window->set_flag(Window::FLAG_POPUP, (p_flags & 4) != 0);
	window->set_size(p_bounds.size);
	window->set_position(p_bounds.position);
	// Owner -1 denotes the primary Stage mapped to the existing root Window.
	Node *parent = p_owner > 0 ? static_cast<Node *>(native_windows.at(p_owner).window) : this;
	parent->add_child(window);
	if (p_owner) window->set_transient(true);
	native_windows.emplace(p_id, NativeWindowEntry{window, p_owner});
	window->connect("window_input", callable_mp(this, &JavaFXHost::window_input).bind(p_id));
	window->connect("close_requested", callable_mp(this, &JavaFXHost::window_event).bind(9, p_id));
	window->connect("mouse_entered", callable_mp(this, &JavaFXHost::window_event).bind(7, p_id));
	window->connect("mouse_exited", callable_mp(this, &JavaFXHost::window_event).bind(8, p_id));
	window->connect("focus_entered", callable_mp(this, &JavaFXHost::window_event).bind(15, p_id));
	window->connect("focus_exited", callable_mp(this, &JavaFXHost::window_event).bind(16, p_id));
	return true;
}

bool JavaFXHost::refresh_native_owners(int64_t p_hidden_owner) {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	auto *display = DisplayServer::get_singleton();
	for (const auto &item : native_windows) {
		const auto &entry = item.second;
		if (!entry.owner || entry.window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) continue;
		Window *owner = entry.owner > 0 ? get_native_window(entry.owner) : get_window();
		ERR_FAIL_NULL_V(owner, false);
		HWND handle = reinterpret_cast<HWND>(display->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE, entry.window->get_window_id()));
		HWND owner_handle = nullptr;
		if (entry.owner != p_hidden_owner && owner->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID) {
			owner_handle = reinterpret_cast<HWND>(display->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE, owner->get_window_id()));
		}
		// Nonexclusive Godot transients do not establish HWND ownership.
		// Detach before an owner HWND is destroyed: Windows would otherwise
		// destroy owned HWNDs behind their still-live Godot Window objects.
		SetLastError(0);
		LONG_PTR previous = SetWindowLongPtr(handle, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner_handle));
		ERR_FAIL_COND_V(!previous && GetLastError() != 0, false);
	}
	return true;
}

bool JavaFXHost::configure_native_window(int64_t p_id, const Rect2i &p_bounds, bool p_visible) {
	if (!Thread::is_main_thread() || p_bounds.size.x <= 0 || p_bounds.size.y <= 0 ||
			p_bounds.size.x > 8192 || p_bounds.size.y > 8192) return false;
	auto *window = get_native_window(p_id);
	if (!window) return false;
	bool was_visible = window->is_visible();
	if (was_visible && !p_visible && !refresh_native_owners(p_id)) return false;
	window->set_size(p_bounds.size); window->set_position(p_bounds.position);
	window->set_visible(p_visible);
	startup_show(p_id, p_visible);
	if (p_visible && !was_visible && !refresh_native_owners()) return false;
	set_window_input_enabled(p_id, native_windows.at(p_id).input_enabled);
	if (p_visible && !was_visible) {
		const auto &entry = native_windows.at(p_id);
		window->set_ime_active(entry.ime_enabled);
		window->set_ime_position(entry.ime_position);
	}
	return true;
}

void JavaFXHost::set_window_input_enabled(int64_t p_id, bool p_enabled) {
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window) return;
	if (p_id) native_windows.at(p_id).input_enabled = p_enabled;
	if (window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return;
	HWND handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(
			DisplayServerEnums::WINDOW_HANDLE, window->get_window_id()));
	EnableWindow(handle, p_enabled);
}

bool JavaFXHost::is_window_input_enabled(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window) return false;
	if (window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return p_id && native_windows.at(p_id).input_enabled;
	HWND handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(
			DisplayServerEnums::WINDOW_HANDLE, window->get_window_id()));
	return IsWindowEnabled(handle) != FALSE;
}

void JavaFXHost::request_window_focus(Window *p_window) {
	p_window->grab_focus();
	HWND handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(
			DisplayServerEnums::WINDOW_HANDLE, p_window->get_window_id()));
	// Foreground activation can be denied by Windows. Still update the active
	// window of our own UI thread; SetActiveWindow does not grant foreground
	// rights to a background process. SetForegroundWindow alone may otherwise
	// leave the last active owned window selected instead of the requested owner.
	if (GetWindowThreadProcessId(handle,nullptr) == GetCurrentThreadId() && IsWindowEnabled(handle)) {
		SetActiveWindow(handle);
		SetFocus(handle);
	}
}

void JavaFXHost::restack_window(Window *p_window, bool p_front) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	if (!p_window || !p_window->is_visible()) return;
	HWND handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(
			DisplayServerEnums::WINDOW_HANDLE, p_window->get_window_id()));
	// Match Windows Glass without moving/resizing or activating a peer.
	ERR_FAIL_COND(!SetWindowPos(handle, p_front ? HWND_TOP : HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE));
}

bool JavaFXHost::is_window_above(int64_t p_id, int64_t p_other) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *first = p_id ? get_native_window(p_id) : get_window();
	Window *second = p_other ? get_native_window(p_other) : get_window();
	if (!first || !second || first == second) return false;
	auto *ds = DisplayServer::get_singleton();
	HWND first_handle = reinterpret_cast<HWND>(ds->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE, first->get_window_id()));
	HWND second_handle = reinterpret_cast<HWND>(ds->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE, second->get_window_id()));
	for (HWND current = GetWindow(second_handle, GW_HWNDPREV); current; current = GetWindow(current, GW_HWNDPREV)) {
		if (current == first_handle) return true;
	}
	return false;
}

bool JavaFXHost::is_window_visible(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window || window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return false;
	HWND handle = reinterpret_cast<HWND>(DisplayServer::get_singleton()->window_get_native_handle(
			DisplayServerEnums::WINDOW_HANDLE, window->get_window_id()));
	return IsWindowVisible(handle) != FALSE;
}

bool JavaFXHost::set_native_window_property(int64_t p_id, int p_property, int p_a, int p_b, const String &p_text) {
	if (!Thread::is_main_thread()) return false;
	auto *window = get_native_window(p_id);
	if (!window) return false;
	// Mode/style changes can replace a swap chain, just like show/hide.
	switch (p_property) {
		case 1: window->set_title(p_text); break;
		case 4: if (window->is_visible()) request_window_focus(window); break;
		case 6: window->set_mode(static_cast<Window::Mode>(p_a)); break;
		case 7: window->set_flag(Window::FLAG_RESIZE_DISABLED, p_a == 0); break;
		case 9: window->set_flag(Window::FLAG_ALWAYS_ON_TOP, p_a != 0); break;
		case 12: {
			Size2i maximum = window->get_max_size();
			if ((maximum.x && p_a > maximum.x) || (maximum.y && p_b > maximum.y)) return false;
			window->set_min_size(Size2i(p_a, p_b));
		} break;
		case 13: {
			Size2i minimum = window->get_min_size();
			if ((p_a && p_a < minimum.x) || (p_b && p_b < minimum.y)) return false;
			window->set_max_size(Size2i(p_a, p_b));
		} break;
		case 15: window->set_flag(Window::FLAG_BORDERLESS, p_a != 0); break;
		case 16: case 17: case 18: window_ime_command(p_id,p_property,p_a,p_b); break;
		case 19: set_window_input_enabled(p_id, p_a != 0); break;
		case 20: window->set_flag(Window::FLAG_NO_FOCUS, p_a == 0); break;
		case 22: case 23: restack_window(window, p_property == 23); break;
		default: return false;
	}
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

void JavaFXHost::destroy_native_window(int64_t p_id) {
	if (startup_active && startup_window_id == p_id) startup_cancel();
	ERR_FAIL_COND(!Thread::is_main_thread());
	auto entry = native_windows.find(p_id);
	if (entry == native_windows.end()) return;
	// Remove owned windows first; their pointers must not survive parent deletion.
	std::vector<int64_t> children;
	for (const auto &child : native_windows) if (child.second.owner == p_id) children.push_back(child.first);
	for (int64_t child : children) destroy_native_window(child);
	auto *window = entry->second.window;
	auto drag = drag_targets.find(window);
	if (drag != drag_targets.end()) {
		// Detach the delegate while the WindowData still exists; the delegate
		// userdata points at the TargetHandler owned by this host.
		if (window->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID)
			static_cast<DisplayServerWindows *>(DisplayServer::get_singleton())->window_set_drag_delegate(window->get_window_id(), nullptr, nullptr);
		drag_targets.erase(drag);
	}
	native_windows.erase(entry);
	if (window->get_parent()) window->get_parent()->remove_child(window);
	memdelete(window);
	held_buttons.erase(p_id);
}

#endif // WINDOWS_ENABLED
