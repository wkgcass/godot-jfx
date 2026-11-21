#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/NodeShaderProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Node shader probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/node-shaders-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://node_shaders.tscn --render-thread $RenderThread --quit-after 4000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_NODE_SHADER_PASS' -or $output -notmatch 'NODE_SHADER_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "Node shader probe failed. See $log" }
    Copy-Item artifacts/reference/godot-node-shaders.png "artifacts/reference/godot-node-shaders-$Driver-$RenderThread.png"
    Write-Output "Node shader probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }

