#include "macos_tabtip.h"
#include <cstdio>

int main() {
    using namespace godot_javafx::macos_tabtip;
    if (request() || release()) return 1;
    std::puts("MACOS_TABTIP_UNSUPPORTED_PASS");
}
