#include "javafx_host.h"

#ifdef LINUXBSD_ENABLED
#include "core/os/thread.h"
#include "servers/display/display_server.h"
#include "javafx_host_wayland.h"

bool JavaFXHost::configure_native_window(int64_t p_id, const Rect2i &p_bounds, bool p_visible) {
	if (!Thread::is_main_thread() || p_bounds.size.x <= 0 || p_bounds.size.y <= 0 ||
			p_bounds.size.x > 8192 || p_bounds.size.y > 8192) return false;
	auto *window = get_native_window(p_id);
	if (!window) return false;
	bool was_visible = window->is_visible();

	// A new surface needs a fresh drop target when the window is shown again.
	if (was_visible && !p_visible) remove_linux_drag_target(window);
	window->set_size(p_bounds.size); window->set_position(p_bounds.position);
	window->set_visible(p_visible);
	startup_show(p_id, p_visible);

	set_window_input_enabled(p_id, native_windows.at(p_id).input_enabled);
	if (p_visible && !was_visible) {
		const auto &entry = native_windows.at(p_id);
		if (entry.modal_hint) {
			DisplayServer::get_singleton()->window_set_exclusive(window->get_window_id(), true);
		}

		window->set_ime_active(entry.ime_enabled);
		window->set_ime_position(entry.ime_position);
	}
	return true;
}

void JavaFXHost::set_window_input_enabled(int64_t p_id, bool p_enabled) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window) return;
	if (p_id) native_windows.at(p_id).input_enabled = p_enabled;
	window->set_disable_input(!p_enabled);
}

bool JavaFXHost::is_window_input_enabled(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *window = p_id ? get_native_window(p_id) : get_window();
	return window && !window->is_input_disabled();
}

void JavaFXHost::request_window_focus(Window *p_window) {
	if (p_window && p_window->is_visible() && !p_window->is_input_disabled()) p_window->grab_focus();
}

void JavaFXHost::restack_window(Window *p_window, bool p_front) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	if (!p_window || !p_window->is_visible()) return;
	auto *display = DisplayServer::get_singleton();
	ERR_FAIL_COND_MSG(!p_front, "Wayland does not allow lowering a toplevel window.");
	display->window_move_to_foreground(p_window->get_window_id());
}

bool JavaFXHost::is_window_above(int64_t p_id, int64_t p_other) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *first = p_id ? get_native_window(p_id) : get_window();
	Window *second = p_other ? get_native_window(p_other) : get_window();
	if (!first || !second || first == second || !first->is_visible() || !second->is_visible()) return false;
	ERR_FAIL_V_MSG(false, "Wayland does not expose the stacking order of toplevel windows.");
}

bool JavaFXHost::is_window_visible(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *window = p_id ? get_native_window(p_id) : get_window();
	return window && window->is_visible() && window->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID &&
			godot_javafx::linux_window_visible(window->get_window_id());
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
		case 9: {
			auto &entry = native_windows.at(p_id);
			if (!entry.owner) {
				window->set_flag(Window::FLAG_ALWAYS_ON_TOP, p_a != 0);
				break;
			}
			ERR_FAIL_COND_V_MSG(p_a != 0, false, "Wayland does not support keeping an owned toplevel above other applications.");
		} break;
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
		case 29: window->start_drag(); break;
		case 22: case 23: restack_window(window, p_property == 23); break;
		default: return false;
	}
	return true;
}

void JavaFXHost::remove_linux_drag_target(Window *p_window) {
	auto target = drag_targets.find(p_window);
	if (target == drag_targets.end()) return;
	auto id = p_window->get_window_id();
	if (id != DisplayServerEnums::INVALID_WINDOW_ID) godot_javafx::linux_set_drag_target(id, nullptr);
	target->second->leave();
	drag_targets.erase(target);
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
	remove_linux_drag_target(window);
	native_windows.erase(entry);
	if (window->get_parent()) window->get_parent()->remove_child(window);
	memdelete(window);
	held_buttons.erase(p_id);
}
#endif
