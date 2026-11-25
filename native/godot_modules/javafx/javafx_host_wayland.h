#pragma once

#include "servers/display/display_server.h"

namespace godot_javafx {
namespace linux_dnd { struct TargetHandler; }
namespace unix_drag { struct SourceData; }
bool wayland_start_drag(DisplayServerEnums::WindowID id, const unix_drag::SourceData &data);
int wayland_drag_result(DisplayServerEnums::WindowID id, bool cancel);
void linux_release_startup_window(DisplayServerEnums::WindowID id);
void linux_set_root_visible(bool visible);
bool linux_window_visible(DisplayServerEnums::WindowID id);
bool linux_set_drag_target(DisplayServerEnums::WindowID id, linux_dnd::TargetHandler *target);
void linux_finish_ime(DisplayServerEnums::WindowID id, bool commit);
Dictionary linux_cursor_info();
String wayland_exported_parent(DisplayServerEnums::WindowID id);
Dictionary wayland_window_icon_info(DisplayServerEnums::WindowID id);
}
