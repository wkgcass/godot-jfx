#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/WindowCompositionProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Window composition probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $log = "agentdir/logs/window-composition-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://window_composition.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_WINDOW_COMPOSITION_PASS' -or $output -notmatch 'WINDOW_COMPOSITION_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Window composition test failed: $log" }
    foreach ($stage in 0..5) { Copy-Item "artifacts/reference/window-composition-$stage.png" "artifacts/reference/window-composition-$Driver-$RenderThread-$stage.png" }
    Write-Output "Window composition passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; Pop-Location }
