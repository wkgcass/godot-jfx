#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PWD/.gradle-cache}"
mkdir -p agentdir/logs
sh scripts/stage-godot-library.sh 2>&1 | tee agentdir/logs/stage-godot-library.log
./jfx/gradlew -p scripts/vfx-build stageRuntime shadowJar --console=plain 2>&1 | tee agentdir/logs/build-vfx.log
