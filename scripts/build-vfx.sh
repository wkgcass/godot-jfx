#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/macos-jdk.sh"
cd "$(dirname "$0")/.."
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PWD/.gradle-cache}"
mkdir -p agentdir/logs
sh scripts/stage-godot-library.sh 2>&1 | tee agentdir/logs/stage-godot-library.log
./jfx/gradlew -p scripts/vfx-build stageRuntime shadowJar --console=plain 2>&1 | tee agentdir/logs/build-vfx.log
