#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Robot)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedRobot = $env:GODOT_JFX_PHYSICAL_DRAG_ROBOT
$savedCapture = $env:GODOT_JFX_PHYSICAL_DRAG_CAPTURE
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics,javafx.swing --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/PhysicalDragProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Physical drag probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_PHYSICAL_DRAG_ROBOT = if($Robot){'1'}else{'0'}
    $env:GODOT_JFX_PHYSICAL_DRAG_CAPTURE = Join-Path $root 'artifacts/reference/physical-drag-desktop.png'
    $log = Join-Path $root "agentdir/logs/physical_drag-$Driver-$RenderThread$(if($Robot){'-robot'}else{''}).log"
    # Default synthetic mode injects the gesture host-side and never touches
    # the OS cursor. -Robot restores the physical Glass-Robot drive: keep the
    # desktop idle and the test window in the foreground for that one.
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://physical_drag.tscn --render-thread $RenderThread --quit-after 3600 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'PHYSICAL_DRAG_PROBE_PASS' -or $output -notmatch 'GODOT_PHYSICAL_DRAG_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') { throw "Physical drag test failed: $log" }
    Write-Output "Physical drag passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; $env:GODOT_JFX_PHYSICAL_DRAG_ROBOT = $savedRobot; $env:GODOT_JFX_PHYSICAL_DRAG_CAPTURE = $savedCapture; Pop-Location }
