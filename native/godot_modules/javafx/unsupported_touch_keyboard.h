#pragma once

// AppKit and the Wayland host have no touch-keyboard request API.
namespace godot_javafx::unsupported_touch_keyboard {
inline bool request() { return false; }
inline bool release() { return false; }
}
