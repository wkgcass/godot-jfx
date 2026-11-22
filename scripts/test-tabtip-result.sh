#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p artifacts/native-tests
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I native/godot_modules/javafx \
    tests/native/macos_tabtip_test.cpp -o artifacts/native-tests/macos_tabtip_test
exec artifacts/native-tests/macos_tabtip_test
