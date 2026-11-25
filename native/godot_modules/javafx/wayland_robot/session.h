#pragma once

#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "ext-image-copy-capture-v1.h"
#include "ext-image-capture-source-v1.h"
#include "virtual-keyboard-unstable-v1.h"
#include "wlr-virtual-pointer-unstable-v1.h"
#include "xdg-output-unstable-v1.h"
#include <array>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <stdexcept>
#include <vector>

namespace godot_javafx::wayland_robot {
inline void release(wl_output *p) { wl_output_destroy(p); }
inline void release(zxdg_output_v1 *p) { zxdg_output_v1_destroy(p); }
inline void release(ext_image_capture_source_v1 *p) { ext_image_capture_source_v1_destroy(p); }
inline void release(ext_image_copy_capture_cursor_session_v1 *p) { ext_image_copy_capture_cursor_session_v1_destroy(p); }
inline void release(wl_display *p) { wl_display_disconnect(p); }
inline void release(wl_registry *p) { wl_registry_destroy(p); }
inline void release(wl_seat *p) { wl_seat_destroy(p); }
inline void release(wl_pointer *p) { wl_pointer_destroy(p); }
inline void release(wl_shm *p) { wl_shm_destroy(p); }
inline void release(zxdg_output_manager_v1 *p) { zxdg_output_manager_v1_destroy(p); }
inline void release(ext_output_image_capture_source_manager_v1 *p) { ext_output_image_capture_source_manager_v1_destroy(p); }
inline void release(ext_image_copy_capture_manager_v1 *p) { ext_image_copy_capture_manager_v1_destroy(p); }
inline void release(zwlr_virtual_pointer_manager_v1 *p) { zwlr_virtual_pointer_manager_v1_destroy(p); }
inline void release(zwp_virtual_keyboard_manager_v1 *p) { zwp_virtual_keyboard_manager_v1_destroy(p); }
inline void release(zwlr_virtual_pointer_v1 *p) { zwlr_virtual_pointer_v1_destroy(p); }
inline void release(zwp_virtual_keyboard_v1 *p) { zwp_virtual_keyboard_v1_destroy(p); }
inline void release(xkb_context *p) { xkb_context_unref(p); }
inline void release(xkb_keymap *p) { xkb_keymap_unref(p); }
inline void release(xkb_state *p) { xkb_state_unref(p); }
template <typename T> struct Deleter {
	void operator()(T *p) const { release(p); }
};
template <typename T> using Owned = std::unique_ptr<T, Deleter<T>>;

struct Unsupported : std::runtime_error { using std::runtime_error::runtime_error; };

struct Output {
	Owned<wl_output> output;
	Owned<zxdg_output_v1> layout;
	Owned<ext_image_capture_source_v1> source;
	Owned<ext_image_copy_capture_cursor_session_v1> cursor;
	int x = 0, y = 0, width = 0, height = 0;
	int logical_x = 0, logical_y = 0, logical_width = 0, logical_height = 0;
	int cursor_x = 0, cursor_y = 0;
	bool inside = false, positioned = false;
};

class Session {
	Owned<wl_display> display;
	Owned<wl_registry> registry;
	Owned<wl_seat> seat;
	Owned<wl_pointer> pointer;
	Owned<wl_shm> shm;
	Owned<zxdg_output_manager_v1> layouts;
	Owned<ext_output_image_capture_source_manager_v1> sources;
	Owned<ext_image_copy_capture_manager_v1> captures;
	Owned<zwlr_virtual_pointer_manager_v1> pointers;
	Owned<zwp_virtual_keyboard_manager_v1> keyboards;
	Owned<zwlr_virtual_pointer_v1> mouse;
	Owned<zwp_virtual_keyboard_v1> keyboard;
	Owned<xkb_context> xkb;
	Owned<xkb_keymap> keymap;
	Owned<xkb_state> state;
	std::map<uint32_t, Output> outputs;
	std::vector<uint32_t> globals;
	bool invalidated = false;
	std::optional<std::array<int, 2>> pending_motion;
	uint32_t seat_capabilities = 0;

	static void global(void *, wl_registry *, uint32_t, const char *, uint32_t);
	static void removed(void *, wl_registry *, uint32_t);
	void init_keyboard();
	void observe_cursor(Output &o);
	void sync();
	bool wait_for(const std::function<bool()> &ready, int timeout_ms);
	void wait(const std::function<bool()> &ready);
	Output *output_at(int x, int y);
public:
	Session();
	void move(int x, int y);
	std::array<int, 2> position();
	void button(int button, bool pressed);
	void wheel(int amount);
	void key(int godot_key, bool pressed);
	std::vector<int32_t> capture(int x, int y, int width, int height);
};
}
