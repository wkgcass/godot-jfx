#!/bin/sh
# macOS/Linux equivalent of test-protocol.cmd (uses clang instead of MSVC).
set -e
cd "$(dirname "$0")/.."
mkdir -p artifacts/native-tests
clang++ -std=c++17 -Wall -Wextra -Werror -O2 -I native/godot_modules/javafx \
    tests/native/frame_protocol_test.cpp -o artifacts/native-tests/frame_protocol_test
artifacts/native-tests/frame_protocol_test
