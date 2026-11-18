[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [switch]$StopFromHost, [switch]$Encoded, [switch]$Textures, [switch]$PrismTextures, [switch]$ShaderStates, [switch]$PrismContext,
    [ValidateSet('gl_compatibility', 'mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread='safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedStop = $env:GODOT_JFX_TEST_STOP
$savedEncoded = $env:GODOT_JFX_TEST_ENCODED
$savedTextures = $env:GODOT_JFX_TEST_TEXTURES
$savedContext = $env:GODOT_JFX_TEST_CONTEXT
$savedShaderStates = $env:GODOT_JFX_TEST_SHADER_STATES
$savedPrismTextures = $env:GODOT_JFX_TEST_PRISM_TEXTURES
if (($Textures -and $PrismTextures) -or (($Textures -or $PrismTextures) -and ($Encoded -or $StopFromHost))) { throw 'Texture probes are separate modes.' }
$suffix = if ($StopFromHost) { '-host-stop' } else { '' }
if ($Encoded) { $suffix += '-encoded' }
if ($Textures) { $suffix += '-textures' }
if ($PrismTextures) { $suffix += '-prism-textures' }
if ($ShaderStates) { if ($Textures -or $PrismTextures -or $Encoded -or $StopFromHost) { throw 'Shader probe is a separate mode.' }; $suffix += '-shaders' }
if ($PrismContext) { if ($Textures -or $PrismTextures -or $Encoded -or $StopFromHost -or $ShaderStates) { throw 'Context probe is a separate mode.' }; $suffix += '-context' }
if ($Renderer -ne 'gl_compatibility') { $suffix += "-$Renderer" }
$log = Join-Path $root "artifacts/logs/m2-bridge$suffix.log"
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/BridgeProbe.java tests/reference/BridgeStopProbe.java tests/reference/RenderCommandsProbe.java tests/reference/TextureCommandsProbe.java tests/reference/PrismTextureProbe.java tests/reference/ShaderCommandsProbe.java tests/reference/PrismContextProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'BridgeProbe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_TEST_STOP = if ($StopFromHost) { '1' } else { '0' }
    $env:GODOT_JFX_TEST_ENCODED = if ($Encoded) { '1' } else { '0' }
    $env:GODOT_JFX_TEST_TEXTURES = if ($Textures) { '1' } else { '0' }
    $env:GODOT_JFX_TEST_CONTEXT = if ($PrismContext) { '1' } else { '0' }
    $env:GODOT_JFX_TEST_SHADER_STATES = if ($ShaderStates) { '1' } else { '0' }
    $env:GODOT_JFX_TEST_PRISM_TEXTURES = if ($PrismTextures) { '1' } else { '0' }
    Invoke-GodotFixture --path tests/godot res://bridge.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'M2_BRIDGE_PASS' -or $output -notmatch 'BRIDGE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "Bridge test failed or incomplete (exit $result). See $log"
    }
    if ($StopFromHost -and $output -notmatch 'BRIDGE_STOP_PASS') { throw 'Host stop was not observed by Java' }
    if ($Encoded -and $output -notmatch 'ENCODER_BACKPRESSURE_OBSERVED') { throw 'Native backpressure was not exercised' }
    if ($Textures) {
        Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-texture-versions.png') -Destination (Join-Path $root "artifacts/reference/godot-texture-versions-$Renderer.png")
    }
    if ($PrismTextures) {
        Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-prism-textures.png') -Destination (Join-Path $root "artifacts/reference/godot-prism-textures-$Renderer.png")
    }
    if ($ShaderStates) {
        Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-shader-bridge.png') -Destination (Join-Path $root "artifacts/reference/godot-shader-bridge-$Renderer.png")
    }
    if ($PrismContext) {
        Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-prism-context.png') -Destination (Join-Path $root "artifacts/reference/godot-prism-context-$Renderer.png")
    }
    Write-Output "M2 bridge test passed. Log: $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    $env:GODOT_JFX_TEST_STOP = $savedStop
    $env:GODOT_JFX_TEST_ENCODED = $savedEncoded
    $env:GODOT_JFX_TEST_TEXTURES = $savedTextures
    $env:GODOT_JFX_TEST_PRISM_TEXTURES = $savedPrismTextures
    $env:GODOT_JFX_TEST_CONTEXT = $savedContext
    $env:GODOT_JFX_TEST_SHADER_STATES = $savedShaderStates
    Pop-Location
}
