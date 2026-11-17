#include "javafx_host.h"
#include "javafx_host_macos.h"
#include "macos_custom_format.h"

#include "core/os/thread.h"
#include "core/object/callable_mp.h"
#include "servers/display/display_server.h"
#include "platform/macos/display_server_macos.h"

#import <AppKit/AppKit.h>

#include <vector>

// Main-thread half of identity-aware Glass transport. No JNI caller may invoke
// these directly: the host command consumer will own all mutations. Cocoa
// calls run on the Godot main thread, which owns every hosted NSWindow.

static NSWindow *macos_window_handle(DisplayServerEnums::WindowID p_id) {
	const int64_t handle = DisplayServer::get_singleton()->window_get_native_handle(DisplayServerEnums::WINDOW_HANDLE, p_id);
	return (__bridge NSWindow *)(void *)handle;
}

void godot_javafx::macos_set_window_visible(void *p_ns_window, bool p_visible) {
	NSWindow *window = (__bridge NSWindow *)p_ns_window;
	if (!window) return;
	if (p_visible) [window orderFront:nil];
	else [window orderOut:nil];
}

void godot_javafx::macos_release_startup_window(DisplayServerEnums::WindowID p_window) {
	static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton())->release_javafx_startup_window(p_window);
}

void godot_javafx::macos_commit_ime_composition(DisplayServerEnums::WindowID p_window) {
	static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton())->window_commit_ime_composition(p_window);
}

bool godot_javafx::macos_window_set_drag_delegate(DisplayServerEnums::WindowID p_window, void *p_delegate, void *p_userdata) {
	auto *display = static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton());
	return display->window_set_drag_delegate(p_window,
			reinterpret_cast<DisplayServerMacOSDragDelegate>(p_delegate), p_userdata) == OK;
}

void godot_javafx::macos_window_register_drag_types(DisplayServerEnums::WindowID p_window, const std::vector<std::u16string> &p_types) {
	auto *display = static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton());
	Vector<String> types;
	for (const std::u16string &type : p_types) {
		// Custom formats register as their UTI twin: AppKit dragging
		// destinations (like NSPasteboardItem writers) reject the raw MIME.
		const std::u16string registered = custom_format::valid_name(type) ? custom_format::uti_type(type) : type;
		types.push_back(String::utf16(reinterpret_cast<const char16_t *>(registered.data()), int(registered.size())));
	}
	display->window_register_drag_types(p_window, types);
}

void godot_javafx::macos_window_set_drag_start_handler(DisplayServerEnums::WindowID p_window, void *p_handler, void *p_userdata) {
	auto *display = static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton());
	display->window_set_drag_start_handler(p_window,
			reinterpret_cast<DisplayServerMacOSDragStartHandler>(p_handler), p_userdata);
}

// Focus emulation helper: AppKit would move key status to the next visible
// window, but the window server refuses app activation in this environment.
// Walk the owner chain to the first visible window, falling back to the root.
Window *JavaFXHost::visible_focus_fallback(int64_t p_owner) const {
	int64_t next = p_owner;
	while (next > 0) {
		auto entry = native_windows.find(next);
		if (entry == native_windows.end()) break;
		Window *candidate = entry->second.window;
		if (candidate && candidate->is_visible() && candidate->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID) return candidate;
		next = entry->second.owner;
	}
	Window *root = get_window();
	if (root && root->is_visible() && root->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID) return root;
	return nullptr;
}

bool godot_javafx::macos_cursor_info(int32_t &r_width, int32_t &r_height, int32_t &r_hotspot_x, int32_t &r_hotspot_y,
		uint32_t &r_center_argb, bool &r_native_null) {
	@autoreleasepool {
		r_native_null = false;
		NSCursor *current = [NSCursor currentCursor];
		if (!current) {
			r_native_null = true;
			return true;
		}
		NSImage *image = [current image];
		if (!image) {
			// System cursors own no readable image; there is still a cursor.
			return false;
		}
		NSPoint hotspot = [current hotSpot];
		NSBitmapImageRep *bitmap = nil;
		for (NSImageRep *rep in [image representations]) {
			if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
				bitmap = (NSBitmapImageRep *)rep;
				break;
			}
		}
		if (!bitmap) {
			// Vector-backed cursor: rasterize at the image's point size.
			NSSize size = [image size];
			if (size.width < 1 || size.height < 1 || size.width > 256 || size.height > 256) return false;
			bitmap = [[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:nullptr
								  pixelsWide:NSInteger(size.width)
								  pixelsHigh:NSInteger(size.height)
							   bitsPerSample:8
							 samplesPerPixel:4
									hasAlpha:YES
									isPlanar:NO
							  colorSpaceName:NSDeviceRGBColorSpace
								 bytesPerRow:NSInteger(size.width) * 4
								bitsPerPixel:32];
			if (!bitmap) return false;
			[NSGraphicsContext saveGraphicsState];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
			[image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
			[NSGraphicsContext restoreGraphicsState];
		}
		const NSInteger width = [bitmap pixelsWide], height = [bitmap pixelsHigh];
		if (width < 1 || height < 1 || width > 256 || height > 256) return false;
		const uint8_t *pixels = [bitmap bitmapData];
		if (!pixels) return false;
		bool any_alpha = false;
		for (NSInteger i = 0; i < width * height; ++i) {
			if (pixels[size_t(i) * 4 + 3] != 0) { any_alpha = true; break; }
		}
		if (!any_alpha) {
			// A fully transparent cursor shows nothing, matching the Windows
			// null-cursor state the readback contract reports as native_null.
			r_native_null = true;
			return true;
		}
		r_width = int32_t(width);
		r_height = int32_t(height);
		r_hotspot_x = int32_t(llround(hotspot.x));
		r_hotspot_y = int32_t(llround(hotspot.y));
		const uint8_t *center = pixels + (size_t(height / 2) * size_t(width) + size_t(width / 2)) * 4;
		r_center_argb = (uint32_t(center[3]) << 24) | (uint32_t(center[0]) << 16) | (uint32_t(center[1]) << 8) | uint32_t(center[2]);
		return true;
	}
}

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
	for (const auto &item : native_windows) {
		const auto &entry = item.second;
		if (!entry.owner || entry.window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) continue;
		Window *owner = entry.owner > 0 ? get_native_window(entry.owner) : get_window();
		ERR_FAIL_NULL_V(owner, false);
		NSWindow *handle = macos_window_handle(entry.window->get_window_id());
		if (!handle) continue;
		// A fullscreen NSWindow (AppKit or emulated) cannot be a child window;
		// it was detached for the transition and is re-attached by
		// poll_fullscreen_reattach().
		if (entry.window->get_mode() == Window::MODE_FULLSCREEN || entry.window->get_mode() == Window::MODE_EXCLUSIVE_FULLSCREEN) continue;
		NSWindow *owner_handle = nullptr;
		if (entry.owner != p_hidden_owner && owner->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID) {
			owner_handle = macos_window_handle(owner->get_window_id());
		}
		// Nonexclusive Godot transients do not establish NSWindow parenting.
		// Detach before an owner NSWindow is destroyed: AppKit would otherwise
		// order out child windows behind their still-live Godot Window objects.
		NSWindow *parent = [handle parentWindow];
		if (parent == owner_handle) continue;
		if (parent) [parent removeChildWindow:handle];
		if (owner_handle) [owner_handle addChildWindow:handle ordered:NSWindowAbove];
	}
	return true;
}

void JavaFXHost::poll_fullscreen_reattach() {
	if (fullscreen_reattach.empty()) return;
	std::vector<int64_t> done;
	for (int64_t id : fullscreen_reattach) {
		auto entry = native_windows.find(id);
		if (entry == native_windows.end()) {
			done.push_back(id);
			continue;
		}
		Window *window = entry->second.window;
		const Window::Mode mode = window->get_mode();
		if (mode == Window::MODE_FULLSCREEN || mode == Window::MODE_EXCLUSIVE_FULLSCREEN) continue;
		if (window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) {
			done.push_back(id);
			continue;
		}
		NSWindow *handle = macos_window_handle(window->get_window_id());
		if (!handle) {
			done.push_back(id);
			continue;
		}
		// The exit animation still owns the window's space.
		if (([handle styleMask] & NSWindowStyleMaskFullScreen) != 0) continue;
		[handle setCollectionBehavior:NSWindowCollectionBehaviorFullScreenAuxiliary];
		done.push_back(id);
	}
	if (done.empty()) return;
	for (int64_t id : done) fullscreen_reattach.erase(id);
	refresh_native_owners();
}

bool JavaFXHost::configure_native_window(int64_t p_id, const Rect2i &p_bounds, bool p_visible) {
	if (!Thread::is_main_thread() || p_bounds.size.x <= 0 || p_bounds.size.y <= 0 ||
			p_bounds.size.x > 8192 || p_bounds.size.y > 8192) return false;
	auto *window = get_native_window(p_id);
	if (!window) return false;
	bool was_visible = window->is_visible();
	bool was_focused = was_visible && window->has_focus();
	if (was_visible && !p_visible && !refresh_native_owners(p_id)) return false;
	window->set_size(p_bounds.size);
	window->set_position(p_bounds.position);
	window->set_visible(p_visible);
	startup_show(p_id, p_visible);
	if (p_visible && !was_visible && !refresh_native_owners()) return false;
	set_window_input_enabled(p_id, native_windows.at(p_id).input_enabled);
	if (p_visible && !was_visible) {
		const auto &entry = native_windows.at(p_id);
		window->set_ime_active(entry.ime_enabled);
		window->set_ime_position(entry.ime_position);
	}
	if (was_focused && !p_visible && ![NSApp isActive]) {
		// AppKit moves key status to another window on hide; when focus is
		// emulated (the window server refuses app activation) transfer it to
		// the nearest visible owner or the root window explicitly.
		const auto &entry = native_windows.at(p_id);
		Window *fallback = visible_focus_fallback(entry.owner);
		if (fallback) {
			static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton())->window_set_logical_focus(fallback->get_window_id());
		}
	}
	return true;
}

void JavaFXHost::set_window_input_enabled(int64_t p_id, bool p_enabled) {
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window) return;
	if (p_id) native_windows.at(p_id).input_enabled = p_enabled;
	if (window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return;
	// Route through the display server: the platform owns the per-frame
	// mouse-passthrough sweep and must treat this as an explicit override.
	static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton())->window_set_ignore_mouse_events(window->get_window_id(), !p_enabled);
}

bool JavaFXHost::is_window_input_enabled(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window) return false;
	if (window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return p_id && native_windows.at(p_id).input_enabled;
	NSWindow *handle = macos_window_handle(window->get_window_id());
	return handle && ![handle ignoresMouseEvents];
}

void JavaFXHost::request_window_focus(Window *p_window) {
	p_window->grab_focus();
	NSWindow *handle = macos_window_handle(p_window->get_window_id());
	if (!handle) return;
	[handle makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
}

void JavaFXHost::restack_window(Window *p_window, bool p_front) {
	ERR_FAIL_COND(!Thread::is_main_thread());
	if (!p_window || !p_window->is_visible()) return;
	NSWindow *handle = macos_window_handle(p_window->get_window_id());
	ERR_FAIL_COND(!handle);
	// Match Glass restack semantics without moving/resizing or activating a peer.
	[handle orderWindow:(p_front ? NSWindowAbove : NSWindowBelow) relativeTo:0];
}

bool JavaFXHost::is_window_above(int64_t p_id, int64_t p_other) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *first = p_id ? get_native_window(p_id) : get_window();
	Window *second = p_other ? get_native_window(p_other) : get_window();
	if (!first || !second || first == second) return false;
	NSWindow *first_handle = macos_window_handle(first->get_window_id());
	NSWindow *second_handle = macos_window_handle(second->get_window_id());
	if (!first_handle || !second_handle) return false;
	// orderedWindows is front-to-back and only lists on-screen windows.
	for (NSWindow *current in [NSApp orderedWindows]) {
		if (current == first_handle) return true;
		if (current == second_handle) return false;
	}
	return false;
}

bool JavaFXHost::is_window_visible(int64_t p_id) const {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	Window *window = p_id ? get_native_window(p_id) : get_window();
	if (!window || window->get_window_id() == DisplayServerEnums::INVALID_WINDOW_ID) return false;
	NSWindow *handle = macos_window_handle(window->get_window_id());
	return handle && [handle isVisible];
}

bool JavaFXHost::set_native_window_property(int64_t p_id, int p_property, int p_a, int p_b, const String &p_text) {
	if (!Thread::is_main_thread()) return false;
	auto *window = get_native_window(p_id);
	if (!window) return false;
	// Mode/style changes can replace a swap chain, just like show/hide.
	switch (p_property) {
		case 1: window->set_title(p_text); break;
		case 4: if (window->is_visible()) request_window_focus(window); break;
		case 6: {
			// An NSWindow attached as a child of its owner cannot enter
			// fullscreen. Detach it before the transition and re-attach it once
			// the exit animation completes (poll_fullscreen_reattach).
			const Window::Mode target = static_cast<Window::Mode>(p_a);
			const bool to_fullscreen = target == Window::MODE_FULLSCREEN || target == Window::MODE_EXCLUSIVE_FULLSCREEN;
			const bool from_fullscreen = window->get_mode() == Window::MODE_FULLSCREEN || window->get_mode() == Window::MODE_EXCLUSIVE_FULLSCREEN;
			if (to_fullscreen) {
				if (window->get_window_id() != DisplayServerEnums::INVALID_WINDOW_ID) {
					if (NSWindow *handle = macos_window_handle(window->get_window_id())) {
						NSWindow *parent = [handle parentWindow];
						if (parent) {
							[parent removeChildWindow:handle];
						}
						[handle setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
					}
				}
				if (!from_fullscreen) fullscreen_reattach.insert(p_id);
			}
			window->set_mode(target);
		} break;
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
		case 16: case 17: case 18: window_ime_command(p_id, p_property, p_a, p_b); break;
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
	const int64_t owner = entry->second.owner;
	const bool was_focused = window->has_focus();
	// The delegate userdata points at the TargetHandler owned by drag_targets;
	// erase it before the WindowData holding the delegate pointer dies with
	// the Window.
	drag_targets.erase(window);
	native_windows.erase(entry);
	if (window->get_parent()) window->get_parent()->remove_child(window);
	memdelete(window);
	held_buttons.erase(p_id);
	fullscreen_reattach.erase(p_id);
	if (was_focused && ![NSApp isActive]) {
		// Focus is emulated while the window server refuses app activation;
		// return it to the nearest visible owner or the root window like
		// AppKit would.
		Window *fallback = visible_focus_fallback(owner);
		if (fallback) {
			static_cast<DisplayServerMacOS *>(DisplayServer::get_singleton())->window_set_logical_focus(fallback->get_window_id());
		}
	}
}
