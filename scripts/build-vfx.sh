#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PWD/.gradle-cache}"
sh scripts/stage-godot-library.sh
./jfx/gradlew -p scripts/vfx-build stageRuntime shadowJar --console=plain
