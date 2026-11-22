#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
jdk=${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}
flags=
case "$#" in
    0) ;;
    1) [ "$1" = --asan ] || exit 2; flags=-fsanitize=address ;;
    *) exit 2 ;;
esac
mkdir -p artifacts/native-tests
clang++ -std=c++17 -Wall -Wextra -Werror -O2 $flags -I native/godot_modules/javafx \
    -I "$jdk/include" -I "$jdk/include/darwin" tests/native/macos_dnd_lifetime_test.cpp \
    -o artifacts/native-tests/macos_dnd_lifetime_test
exec artifacts/native-tests/macos_dnd_lifetime_test
