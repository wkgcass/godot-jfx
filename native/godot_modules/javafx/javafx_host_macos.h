#pragma once

#include "servers/display/display_server.h"

#include <string>
#include <vector>

// Cocoa helpers shared between the platform-dispatched host code
// (javafx_host.cpp, javafx_startup.cpp) and the macOS native-window
// implementation (javafx_host_macos.mm). Declared without Objective-C types
// so plain C++ translation units can call them.
namespace godot_javafx {
// Shows/hides the root NSWindow (orderFront:/orderOut:). Godot forbids
// hiding its root Window through Window::set_visible, matching the Windows
// backend's ShowWindow path.
void macos_set_window_visible(void *p_ns_window, bool p_visible);
// DisplayServerMacOS::release_javafx_startup_window, reachable from C++.
void macos_release_startup_window(DisplayServerEnums::WindowID p_window);
// DisplayServerMacOS::window_commit_ime_composition, reachable from C++.
void macos_commit_ime_composition(DisplayServerEnums::WindowID p_window);
// Inspects the current NSCursor for the custom-cursor readback used by
// JavaFXHost::refresh_custom_cursor_info. Reports the pixel dimensions,
// hotspot and premultiplied center pixel of the cursor image; r_native_null
// mirrors the Windows GetCursor() == nullptr case (no cursor, or a fully
// transparent image). Returns false when AppKit state cannot be read.
bool macos_cursor_info(int32_t &r_width, int32_t &r_height, int32_t &r_hotspot_x, int32_t &r_hotspot_y,
		uint32_t &r_center_argb, bool &r_native_null);
// DisplayServerMacOS::window_set_drag_delegate, reachable from C++ translation
// units that cannot include the AppKit-backed display_server_macos.h. The
// delegate/userdata arguments are type-erased for the same reason.
bool macos_window_set_drag_delegate(DisplayServerEnums::WindowID p_window, void *p_delegate, void *p_userdata);
// Registers extra pasteboard types on a window's content view so inbound
// drags carrying them reach the drag delegate.
void macos_window_register_drag_types(DisplayServerEnums::WindowID p_window, const std::vector<std::u16string> &p_types);
// DisplayServerMacOS::window_set_drag_start_handler, type-erased for C++
// translation units. See DisplayServerMacOSDragStartHandler for the contract.
void macos_window_set_drag_start_handler(DisplayServerEnums::WindowID p_window, void *p_handler, void *p_userdata);
}
