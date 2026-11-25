#!/bin/sh
set -eu
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
jdk="$JAVA_HOME"
flags=
case "$#" in
    0) ;;
    1) [ "$1" = --asan ] || exit 2; flags=-fsanitize=address ;;
    *) exit 2 ;;
esac
mkdir -p artifacts/native-tests
case "$(uname -s)" in Linux) jni=linux ;; Darwin) jni=darwin ;; *) exit 2 ;; esac
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -O2 -pthread $flags -I native/godot_modules/javafx \
    -I "$jdk/include" -I "$jdk/include/$jni" tests/native/unix_dnd_lifetime_test.cpp \
    -o artifacts/native-tests/unix_dnd_lifetime_test
exec artifacts/native-tests/unix_dnd_lifetime_test
