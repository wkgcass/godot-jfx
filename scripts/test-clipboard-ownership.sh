#!/bin/sh
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
jdk="$JAVA_HOME"
mkdir -p artifacts/native-tests
clang++ -std=c++17 -fobjc-arc -framework AppKit -framework UniformTypeIdentifiers -O2 \
    -I native/godot_modules/javafx -I "$jdk/include" -I "$jdk/include/darwin" \
    tests/native/macos_clipboard_ownership_test.mm native/godot_modules/javafx/macos_clipboard.mm \
    -o artifacts/native-tests/macos_clipboard_ownership_test
exec artifacts/native-tests/macos_clipboard_ownership_test
