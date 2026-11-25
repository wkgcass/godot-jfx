#include "unsupported_touch_keyboard.h"
#include <cstdio>

int main() {
    using namespace godot_javafx::unsupported_touch_keyboard;
    if (request() || release()) return 1;
#ifdef __APPLE__
    std::puts("MACOS_TABTIP_UNSUPPORTED_PASS");
#else
    std::puts("WAYLAND_TOUCH_KEYBOARD_UNSUPPORTED_PASS");
#endif
}
