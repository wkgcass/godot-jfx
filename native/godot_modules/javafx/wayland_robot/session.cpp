#include "session.h"
#include "mapped_file.h"
#include "platform/linuxbsd/wayland/key_mapping_xkb.h"
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <limits>
#include <linux/input-event-codes.h>
#include <poll.h>

namespace godot_javafx::wayland_robot {
namespace {
using Clock = std::chrono::steady_clock;
uint32_t timestamp() {
	return uint32_t(std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count());
}
const wl_output_listener output_events = {
	.geometry = [](void *data, wl_output *, int32_t x, int32_t y, int32_t, int32_t, int32_t, const char *, const char *, int32_t) {
		Output &o = *static_cast<Output *>(data);
		o.x = x; o.y = y;
	},
	.mode = [](void *data, wl_output *, uint32_t flags, int32_t w, int32_t h, int32_t) {
		if (flags & WL_OUTPUT_MODE_CURRENT) {
			Output &o = *static_cast<Output *>(data);
			o.width = w; o.height = h;
		}
	},
	.done = [](void *, wl_output *) {},
	.scale = [](void *, wl_output *, int32_t) {},
};
const zxdg_output_v1_listener layout_events = {
	.logical_position = [](void *d, zxdg_output_v1 *, int32_t x, int32_t y) {
		auto &o = *static_cast<Output *>(d); o.logical_x = x; o.logical_y = y;
	},
	.logical_size = [](void *d, zxdg_output_v1 *, int32_t w, int32_t h) {
		auto &o = *static_cast<Output *>(d); o.logical_width = w; o.logical_height = h;
	},
	.done = [](void *, zxdg_output_v1 *) {},
	.name = [](void *, zxdg_output_v1 *, const char *) {},
	.description = [](void *, zxdg_output_v1 *, const char *) {},
};
using Cursor = ext_image_copy_capture_cursor_session_v1;
const ext_image_copy_capture_cursor_session_v1_listener cursor_events = {
	.enter = [](void *d, Cursor *) { static_cast<Output *>(d)->inside = true; },
	.leave = [](void *d, Cursor *) {
		auto &o = *static_cast<Output *>(d); o.inside = false; o.positioned = false;
	},
	.position = [](void *d, Cursor *, int32_t x, int32_t y) {
		auto &o = *static_cast<Output *>(d); o.cursor_x = x; o.cursor_y = y; o.positioned = true;
	},
	.hotspot = [](void *, Cursor *, int32_t, int32_t) {},
};
}

void Session::global(void *data, wl_registry *r, uint32_t id, const char *name, uint32_t version) {
	Session &s = *static_cast<Session *>(data);
	auto bind = [&](const wl_interface &type, auto &field, uint32_t max_version) {
		if (strcmp(name, type.name) || field) return false;
		using T = typename std::remove_reference_t<decltype(field)>::element_type;
		field.reset(static_cast<T *>(wl_registry_bind(r, id, &type, std::min(version, max_version))));
		s.globals.push_back(id);
		return true;
	};
	if (!strcmp(name, wl_output_interface.name)) {
		if (s.mouse) s.invalidated = true;
		auto &output = s.outputs[id];
		bind(wl_output_interface, output.output, 2);
		wl_output_add_listener(output.output.get(), &output_events, &output);
	} else if (bind(wl_seat_interface, s.seat, 1)) {
		static const wl_seat_listener listener = {
			.capabilities = [](void *d, wl_seat *, uint32_t caps) { static_cast<Session *>(d)->seat_capabilities = caps; },
		};
		wl_seat_add_listener(s.seat.get(), &listener, &s);
	} else {
		bind(wl_shm_interface, s.shm, 1);
		bind(zxdg_output_manager_v1_interface, s.layouts, 2);
		bind(ext_output_image_capture_source_manager_v1_interface, s.sources, 1);
		bind(ext_image_copy_capture_manager_v1_interface, s.captures, 1);
		bind(zwlr_virtual_pointer_manager_v1_interface, s.pointers, 1);
		bind(zwp_virtual_keyboard_manager_v1_interface, s.keyboards, 1);
	}
}
void Session::removed(void *d, wl_registry *, uint32_t id) {
	auto &s = *static_cast<Session *>(d);
	if (std::find(s.globals.begin(), s.globals.end(), id) != s.globals.end()) s.invalidated = true;
}

void Session::wait(const std::function<bool()> &ready) {
	if (!wait_for(ready, 3000)) throw std::runtime_error("Wayland Robot compositor reply timed out");
}
bool Session::wait_for(const std::function<bool()> &ready, int timeout_ms) {
	auto deadline = Clock::now() + std::chrono::milliseconds(timeout_ms);
	auto *d = display.get();
	for (;;) {
		if (wl_display_dispatch_pending(d) < 0) throw std::runtime_error("Wayland Robot disconnected");
		if (invalidated) throw std::runtime_error("Wayland Robot seat or outputs changed");
		if (ready()) return true;
		int64_t remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - Clock::now()).count();
		if (remaining <= 0) return false;
		short flags = POLLIN;
		if (wl_display_flush(d) < 0) {
			if (errno != EAGAIN) throw std::runtime_error("Cannot flush Wayland Robot display");
			flags |= POLLOUT;
		}
		pollfd fd{wl_display_get_fd(d), flags, 0};
		int count = poll(&fd, 1, int(remaining));
		if (count < 0 && errno == EINTR) continue;
		if (count < 0 || fd.revents & (POLLERR | POLLHUP | POLLNVAL)) throw std::runtime_error("Wayland Robot connection failed");
		// This connection belongs exclusively to the Glass event thread.
		if ((fd.revents & POLLIN) && wl_display_dispatch(d) < 0) throw std::runtime_error("Cannot read Wayland Robot event");
	}
}
void Session::sync() {
	bool complete = false;
	std::unique_ptr<wl_callback, decltype(&wl_callback_destroy)> fence(wl_display_sync(display.get()), wl_callback_destroy);
	static const wl_callback_listener callback = {.done = [](void *d, wl_callback *, uint32_t) { *static_cast<bool *>(d) = true; }};
	wl_callback_add_listener(fence.get(), &callback, &complete);
	wait([&] { return complete; });
}

Session::Session() : display(wl_display_connect(nullptr)) {
	if (!display) throw std::runtime_error("Cannot connect to Wayland for desktop Robot");
	registry.reset(wl_display_get_registry(display.get()));
	static const wl_registry_listener listener = {global, removed};
	wl_registry_add_listener(registry.get(), &listener, this);
	sync();
	if (!pointers || !keyboards || !captures || !sources || !shm || !seat || !layouts || outputs.empty()) {
		throw Unsupported("Wayland Robot requires virtual pointer/keyboard, output layout and image-copy capture protocols");
	}
	sync();
	if (!(seat_capabilities & WL_SEAT_CAPABILITY_POINTER)) throw Unsupported("Wayland seat has no pointer");
	pointer.reset(wl_seat_get_pointer(seat.get()));
	mouse.reset(zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointers.get(), seat.get()));
	for (auto &entry : outputs) {
		auto &o = entry.second;
		o.layout.reset(zxdg_output_manager_v1_get_xdg_output(layouts.get(), o.output.get()));
		zxdg_output_v1_add_listener(o.layout.get(), &layout_events, &o);
		o.source.reset(ext_output_image_capture_source_manager_v1_create_source(sources.get(), o.output.get()));
		observe_cursor(o);

	}
	init_keyboard();
	sync();
}

void Session::observe_cursor(Output &o) {
	o.inside = false;
	o.positioned = false;
	o.cursor.reset(ext_image_copy_capture_manager_v1_create_pointer_cursor_session(captures.get(), o.source.get(), pointer.get()));
	ext_image_copy_capture_cursor_session_v1_add_listener(o.cursor.get(), &cursor_events, &o);
}

Output *Session::output_at(int x, int y) {
	Output *found = nullptr;
	for (auto &entry : outputs) {
		auto &o = entry.second;
		if (int64_t(x) - o.x >= 0 && int64_t(x) - o.x < o.width && int64_t(y) - o.y >= 0 && int64_t(y) - o.y < o.height) {
			if (found) throw Unsupported("Ambiguous Wayland physical output coordinates");
			found = &o;
		}
	}
	return found;
}

void Session::move(int x, int y) {
	sync();
	auto *o = output_at(x, y);
	if (!o) {
		double best = std::numeric_limits<double>::infinity();
		int nearest_x = x, nearest_y = y;
		for (auto &entry : outputs) {
			auto &v = entry.second;
			if (v.width <= 0 || v.height <= 0) continue;
			const int px = int(std::clamp<int64_t>(x, v.x, int64_t(v.x) + v.width - 1));
			const int py = int(std::clamp<int64_t>(y, v.y, int64_t(v.y) + v.height - 1));
			const double dx = double(x) - px, dy = double(y) - py;
			const double distance = dx * dx + dy * dy;
			if (distance < best) {
				best = distance;
				o = &v;
				nearest_x = px;
				nearest_y = py;
			}
		}
		if (!o) throw Unsupported("Wayland Robot has no active output");
		x = nearest_x;
		y = nearest_y;
	}
	int64_t left = INT32_MAX, top = INT32_MAX, right = INT32_MIN, bottom = INT32_MIN;
	for (const auto &entry : outputs) {
		const auto &v = entry.second;
		if (v.logical_width <= 0 || v.logical_height <= 0) throw Unsupported("Missing Wayland logical output size");
		left = std::min<int64_t>(left, v.logical_x); top = std::min<int64_t>(top, v.logical_y);
		right = std::max(right, int64_t(v.logical_x) + v.logical_width);
		bottom = std::max(bottom, int64_t(v.logical_y) + v.logical_height);
	}
	// Preserve sub-logical-pixel precision on scaled outputs.
	double lx = o->logical_x - left + (int64_t(x) - o->x + 0.5) * double(o->logical_width) / o->width;
	double ly = o->logical_y - top + (int64_t(y) - o->y + 0.5) * double(o->logical_height) / o->height;
	constexpr uint32_t span = 1u << 30;
	zwlr_virtual_pointer_v1_motion_absolute(mouse.get(), timestamp(), uint32_t(lx * span / (right-left)), uint32_t(ly * span / (bottom-top)), span, span);
	zwlr_virtual_pointer_v1_frame(mouse.get());
	sync();
	pending_motion = {{x, y}};
}
std::array<int, 2> Session::position() {
	sync();
	if (pending_motion) {
		const auto [x, y] = *pending_motion;
		auto *o = output_at(x, y);
		// Compositors publish the cursor hotspot on repaint, after acknowledging
		// the input request. A confined pointer may never reach the destination.
		if (o) wait_for([&] { return o->inside && o->positioned &&
				o->cursor_x == x - o->x && o->cursor_y == y - o->y; }, 150);
		pending_motion.reset();
	}
	// On startup the first enter/position pair can follow the registry
	// roundtrip. Observe it without disturbing a stationary pointer.
	wait_for([&] {
		return std::any_of(outputs.begin(), outputs.end(), [](const auto &entry) {
			return entry.second.inside && entry.second.positioned;
		});
	}, 1000);
	for (const auto &entry : outputs) {
		const auto &o = entry.second;
		if (o.inside && o.positioned) return {o.x + o.cursor_x, o.y + o.cursor_y};
	}
	throw Unsupported("Compositor has not reported a Wayland pointer position");
}
void Session::button(int button, bool pressed) {
	if (button < 1 || button > 5) throw std::invalid_argument("Invalid Wayland Robot mouse button");
	constexpr uint32_t buttons[] = {BTN_LEFT, BTN_MIDDLE, BTN_RIGHT, BTN_SIDE, BTN_EXTRA};
	zwlr_virtual_pointer_v1_button(mouse.get(), timestamp(), buttons[button-1], pressed ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
	zwlr_virtual_pointer_v1_frame(mouse.get());
	sync();
}
void Session::wheel(int amount) {
	if (!amount) return;
	auto t = timestamp();
	zwlr_virtual_pointer_v1_axis_source(mouse.get(), WL_POINTER_AXIS_SOURCE_WHEEL);
	zwlr_virtual_pointer_v1_axis_discrete(mouse.get(), t, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(std::clamp(double(amount)*10.0, -8388607.0, 8388607.0)), amount);
	zwlr_virtual_pointer_v1_frame(mouse.get());
	sync();
}

void Session::init_keyboard() {
	xkb.reset(xkb_context_new(XKB_CONTEXT_NO_FLAGS));
	xkb_rule_names names{}; names.rules = "evdev"; names.model = "pc105"; names.layout = "us";
	if (xkb) keymap.reset(xkb_keymap_new_from_names(xkb.get(), &names, XKB_KEYMAP_COMPILE_NO_FLAGS));
	if (keymap) state.reset(xkb_state_new(keymap.get()));
	if (!state) throw std::runtime_error("Cannot create Wayland Robot XKB keymap");
	std::unique_ptr<char, decltype(&free)> text(xkb_keymap_get_as_string(keymap.get(), XKB_KEYMAP_FORMAT_TEXT_V1), free);
	if (!text) throw std::bad_alloc();
	const size_t length = strlen(text.get()) + 1;
	MappedFile file(length);
	memcpy(file.data(), text.get(), length);
	keyboard.reset(zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboards.get(), seat.get()));
	zwp_virtual_keyboard_v1_keymap(keyboard.get(), WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, file.fd(), uint32_t(length));
}
void Session::key(int godot_key, bool pressed) {
	const auto code = KeyMappingXKB::get_xkb_keycode(Key(godot_key));
	if (code < 8) throw Unsupported("Key has no evdev mapping on the Wayland virtual keyboard");
	const auto changed = xkb_state_update_key(state.get(), code, pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
	zwp_virtual_keyboard_v1_key(keyboard.get(), timestamp(), code-8, pressed ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
	if (changed) {
		zwp_virtual_keyboard_v1_modifiers(keyboard.get(), xkb_state_serialize_mods(state.get(), XKB_STATE_MODS_DEPRESSED),
			xkb_state_serialize_mods(state.get(), XKB_STATE_MODS_LATCHED), xkb_state_serialize_mods(state.get(), XKB_STATE_MODS_LOCKED),
			xkb_state_serialize_layout(state.get(), XKB_STATE_LAYOUT_EFFECTIVE));
	}
	sync();
}
}
