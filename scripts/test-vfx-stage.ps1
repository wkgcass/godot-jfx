#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Abrupt)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedAbrupt = $env:GODOT_JFX_VFX_ABRUPT
Push-Location $root
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxStageProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX Stage observer compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_VFX_ABRUPT = if ($Abrupt) { '1' } else { $null }
    $suffix = if ($Abrupt) { '-abrupt' } else { '' }
    $log = "agentdir/logs/vfx-stage-$Driver-$RenderThread$suffix.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://vfx_stage.tscn --render-thread $RenderThread --quit-after 20000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($Abrupt) {
        if ($result -ne 0 -or $output -notmatch 'VFX_ABRUPT_EXIT_REQUESTED' -or $output -notmatch 'VFX_STAGE_ABRUPT_RETURNED' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error)|RenderJob.run: internal exception)|GodotHostStoppedException|uncaught:|Suppressed:') { throw "VFX abrupt exit failed: $log" }
        Write-Output "VFX abrupt exit passed: $log"
        return
    }
    if ($result -ne 0 -or $output -notmatch 'GODOT_VFX_STAGE_PASS' -or $output -notmatch 'VFX_STAGE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception|com\.sun\.javafx\.tk\.godot\.GodotHostStoppedException)') { throw "VFX Stage test failed: $log" }
    foreach ($step in 0..11) { Copy-Item "artifacts/reference/vfx-stage-$step.png" "artifacts/reference/vfx-stage-$Driver-$RenderThread-$step.png" }
    Write-Output "VFX Stage passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_VFX_ABRUPT = $savedAbrupt; Pop-Location }



