#ifdef __linux__
#include "linux_dnd.h"
#else
#include "macos_dnd.h"
#endif
#include <iostream>
#include <stdexcept>

static void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
#include "dnd_jni_failure_test.h"

int main() {
    dnd_jni_test::check();
}
