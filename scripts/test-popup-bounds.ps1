#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/PopupBoundsProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Popup bounds probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $log = "agentdir/logs/popup-bounds-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://popup_bounds.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_POPUP_BOUNDS_PASS' -or $output -notmatch 'POPUP_BOUNDS_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Popup bounds test failed: $log" }
    Copy-Item artifacts/reference/popup-bounds.png "artifacts/reference/popup-bounds-$Driver-$RenderThread.png"
    Write-Output "Popup bounds passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; Pop-Location }

