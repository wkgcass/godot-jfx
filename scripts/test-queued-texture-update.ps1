#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$BatchBoundary, [switch]$ViewportState)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedOffscreen = $env:GODOT_JFX_DIRECT_OFFSCREEN
$savedBoundary = $env:GODOT_JFX_TEST_BATCH_BOUNDARY
$savedViewport = $env:GODOT_JFX_TEST_VIEWPORT_STATE
$savedInstance = $env:GODOT_JFX_INSTANCE_UNIFORMS
$savedJvm = $env:JAVA_TOOL_OPTIONS
$env:GODOT_JFX_DIRECT_OFFSCREEN = '1'
Push-Location $root
try {
    if ($BatchBoundary -and $ViewportState) { throw 'Choose one fixture mode' }
    $env:GODOT_JFX_TEST_VIEWPORT_STATE = if($ViewportState){'1'}else{'0'}
    if($ViewportState){$env:GODOT_JFX_INSTANCE_UNIFORMS='1'}
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    $env:GODOT_JFX_TEST_BATCH_BOUNDARY = if($BatchBoundary){'1'}else{'0'}
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/QueuedTextureUpdateProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Queued texture update probe compilation failed' }
    if($BatchBoundary){$env:JAVA_TOOL_OPTIONS="$savedJvm --add-opens=javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED"}
    $env:JAVA_HOME = $Jdk
    $log = "agentdir/logs/queued-texture-update-$Driver-$RenderThread$(if($BatchBoundary){'-boundary'})$(if($ViewportState){'-viewport-state'}).log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://queued_texture_update.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($output -notmatch '(?m)^SAME_PASS_SAMPLER_REVISION_PASS pixels=128\r?$') { throw 'Same-pass sampler revision check incomplete' }
    if ($output -notmatch 'PARTIAL_TEXTURE_UPDATE_PASS') { throw 'Partial texture update check incomplete' }
    if($ViewportState -and $output -notmatch 'VIEWPORT_STATE_PASS'){throw 'Viewport state check incomplete'}
    if($BatchBoundary -and ($output -notmatch 'BATCH_BOUNDARY_PIXELS_PASS' -or $output -notmatch 'BATCH_BYTE_BOUNDARY_PIXELS_PASS')){throw "Batch boundary pixel check incomplete: $log"}
    if ($result -ne 0 -or $output -notmatch 'GODOT_QUEUED_TEXTURE_UPDATE_PASS' -or $output -notmatch 'QUEUED_TEXTURE_UPDATE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Queued texture update test failed: $log" }
    Write-Output "Queued texture update passed: $log"
} finally { $env:GODOT_JFX_TEST_VIEWPORT_STATE=$savedViewport; $env:GODOT_JFX_INSTANCE_UNIFORMS=$savedInstance; $env:JAVA_TOOL_OPTIONS=$savedJvm; $env:GODOT_JFX_TEST_BATCH_BOUNDARY=$savedBoundary; $env:GODOT_JFX_DIRECT_OFFSCREEN=$savedOffscreen; $env:JAVA_HOME = $savedJdk; Pop-Location }
