#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p artifacts/native-tests
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -O2 -I native/godot_modules/javafx \
    tests/native/unsupported_touch_keyboard_test.cpp -o artifacts/native-tests/unsupported_touch_keyboard_test
exec artifacts/native-tests/unsupported_touch_keyboard_test
