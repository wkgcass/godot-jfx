[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe', [switch]$Robot)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedRobot = $env:GODOT_JFX_PHYSICAL_DRAG_ROBOT
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics,javafx.swing --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/PhysicalDragProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Physical drag probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_PHYSICAL_DRAG_ROBOT = if($Robot){'1'}else{'0'}
    $log = Join-Path $root "artifacts/logs/physical_drag-$Renderer-$RenderThread$(if($Robot){'-robot'}else{''}).log"
    # Default synthetic mode injects the gesture host-side and never touches
    # the OS cursor. -Robot restores the physical Glass-Robot drive: keep the
    # desktop idle and the test window in the foreground for that one.
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://physical_drag.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 3600 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'PHYSICAL_DRAG_PROBE_PASS' -or $output -notmatch 'GODOT_PHYSICAL_DRAG_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') { throw "Physical drag test failed: $log" }
    Write-Output "Physical drag passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_PHYSICAL_DRAG_ROBOT = $savedRobot; Pop-Location }
