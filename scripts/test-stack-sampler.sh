#!/bin/sh
set -e
cd "$(dirname "$0")/.."
JDK="${JAVA_HOME:-$PWD/.tools/jdk-25/Contents/Home}"
if [ ! -x "$JDK/bin/javac" ]; then
    echo "javac not found under $JDK" >&2
    exit 1
fi
mkdir -p artifacts/reference agentdir/logs
"$JDK/bin/javac" -encoding UTF-8 -d artifacts/reference tests/reference/ThreadStackSampler.java tests/reference/ThreadStackSamplerProbe.java
"$JDK/bin/java" -cp artifacts/reference ThreadStackSamplerProbe > agentdir/logs/stack-sampler.log 2>&1 || {
    echo "Stack sampler probe failed: agentdir/logs/stack-sampler.log" >&2
    exit 1
}
if ! grep -q 'THREAD_STACK_SAMPLER_PASS' agentdir/logs/stack-sampler.log; then
    echo "Stack sampler probe failed: agentdir/logs/stack-sampler.log" >&2
    exit 1
fi
echo 'Stack sampler probe passed'
