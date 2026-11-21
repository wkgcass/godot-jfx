#!/bin/sh
# macOS equivalent of test-shaders.ps1.
# Usage: test-shaders.sh [--driver metal|opengl]
set -u
cd "$(dirname "$0")/.."

DRIVER="metal"
while [ $# -gt 0 ]; do
    case "$1" in
        --driver) DRIVER="${2-}"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$DRIVER" in metal|opengl) ;; *) echo "expected --driver metal or opengl" >&2; exit 2 ;; esac

FIXTURE_LAUNCHER="$PWD/scripts/godot-fixture.py"
PY=".tools/pyenv/bin/python3"
[ -x "$PY" ] || PY="python3"
mkdir -p agentdir/logs artifacts/reference

# Generated Godot shader variants must cover the same set as the stock
# generation, and the SDK jar must package the current generated files.
# Windows compares against the D3D HLSL generation; the macOS build does not
# generate HLSL, so the stock ES2 GLSL generation is the reference set here.
"$PY" - <<'EOF'
import os, sys, zipfile
groups = [
    ('jsl-prism', 'com/sun/prism/godot/shaders', 'com/sun/prism/es2/glsl'),
    ('jsl-decora', 'com/sun/scenario/effect/impl/godot/shaders', 'com/sun/scenario/effect/impl/es2/glsl'),
]
gen = os.path.join('jfx/modules/javafx.graphics/build/gensrc')
jar = zipfile.ZipFile('jfx/build/sdk/lib/javafx.graphics.jar')
for name, gdir, hdir in groups:
    gpath = os.path.join(gen, name, gdir)
    hpath = os.path.join(gen, name, hdir)
    gs = {os.path.splitext(f)[0]: f for f in os.listdir(gpath) if f.endswith('.gdshader')}
    hs = {os.path.splitext(f)[0] for f in os.listdir(hpath) if f.endswith('.frag')}
    if not gs or not hs or sorted(gs) != sorted(hs):
        sys.exit('Godot shader variant coverage differs from existing ES2 generation: ' + name)
    for base in sorted(gs):
        fname = gs[base]
        try:
            packaged = jar.read(gdir + '/' + fname)
        except KeyError:
            sys.exit('Generated shader missing from SDK: ' + fname)
        with open(os.path.join(gpath, fname), 'rb') as fh:
            if packaged != fh.read():
                sys.exit('Stale SDK shader: ' + fname)
print('SHADER_COVERAGE_PASS')
EOF
[ $? -eq 0 ] || exit 1

LOG="agentdir/logs/godot-shaders-$DRIVER.log"
CODE=0
python3 "$FIXTURE_LAUNCHER" --driver "$DRIVER" --path tests/godot res://shaders.tscn \
    --quit-after 3000 >"$LOG" 2>&1 || CODE=$?
if [ "$CODE" -ne 0 ] \
    || ! python3 scripts/godot_driver.py --driver "$DRIVER" "$LOG" \
    || ! grep -q 'GODOT_SHADER_PASS count=' "$LOG" \
    || grep -qE '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' "$LOG"; then
    echo "Generated shader validation failed. See $LOG" >&2
    exit 1
fi
cp artifacts/reference/godot-generated-shader.png "artifacts/reference/godot-generated-shader-$DRIVER.png"
cp artifacts/reference/godot-shader-states.png "artifacts/reference/godot-shader-states-$DRIVER.png"
echo "Generated shader validation passed on $DRIVER. Log: $LOG"
