#!/bin/sh
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
jdk="$JAVA_HOME"
mkdir -p artifacts/native-tests
clang++ -std=c++17 -fobjc-arc -framework AppKit -O2 -I native/godot_modules/javafx \
    -I "$jdk/include" -I "$jdk/include/darwin" tests/native/macos_drag_image_test.mm \
    -o artifacts/native-tests/macos_drag_image_test
exec artifacts/native-tests/macos_drag_image_test
