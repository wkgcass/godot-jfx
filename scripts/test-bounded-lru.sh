#!/bin/sh
# macOS/Linux equivalent of test-bounded-lru.cmd (uses clang instead of MSVC).
set -e
cd "$(dirname "$0")/.."
mkdir -p artifacts/native-tests
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -O2 -I native/godot_modules/javafx \
    tests/native/bounded_lru_test.cpp tests/native/bounded_lru_allocations.cpp -o artifacts/native-tests/bounded_lru_test
artifacts/native-tests/bounded_lru_test
