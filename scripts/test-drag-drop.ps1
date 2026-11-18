[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Robot)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedRobot = $env:GODOT_JFX_ROBOT_DRAG
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/DragDropProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Drag/drop probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_ROBOT_DRAG = if($Robot){'1'}else{'0'}
    $suffix = if($Robot){'-robot'}else{''}
    $log = "artifacts/logs/drag-drop-$Renderer-$RenderThread$suffix.log"
    Invoke-GodotFixture --path tests/godot res://drag_drop.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_DRAG_DROP_PASS' -or $output -notmatch 'DRAG_DROP_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Drag/drop test failed: $log" }
    Write-Output "Drag/drop passed: $log"
} finally { $env:GODOT_JFX_ROBOT_DRAG = $savedRobot; $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }




