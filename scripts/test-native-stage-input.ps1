#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/NativeStageInputProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Native Stage probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/native-stage-input-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://native_stage_input.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_NATIVE_STAGE_INPUT_PASS' -or $output -notmatch 'NATIVE_STAGE_INPUT_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Native Stage test failed: $log" }
    Write-Output "Native Stage passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }




