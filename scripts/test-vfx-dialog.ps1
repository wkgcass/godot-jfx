#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$InjectFailure)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedFailure = $env:GODOT_JFX_VFX_FAILURE
Push-Location $root
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxDialogProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX dialog observer compilation failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_VFX_FAILURE = if ($InjectFailure) { '1' } else { '0' }
    $suffix = if ($InjectFailure) { '-failure' } else { '' }
    $log = "agentdir/logs/vfx-dialog-$Driver-$RenderThread$suffix.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://vfx_dialog.tscn --render-thread $RenderThread --quit-after 20000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($InjectFailure) {
        $unexpected = @(Get-Content $log | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*(Exception|Error))|RejectedExecutionException|RenderJob.run: internal exception|Suppressed:|Caused by:' -and $_ -ne 'ERROR: Java application failed; see JVM exception in the host log' -and $_ -ne 'Exception in thread "main" java.lang.AssertionError: java.lang.AssertionError: INJECTED_VFX_FAILURE' -and $_ -ne 'Caused by: java.lang.AssertionError: INJECTED_VFX_FAILURE' })
        if ($result -ne 0 -or $output -notmatch 'GODOT_VFX_FAILURE_SHUTDOWN_PASS' -or $output -notmatch 'INJECTED_VFX_FAILURE' -or $unexpected.Count -ne 0) { throw "VFX failure shutdown test failed: $log" }
        Write-Output "VFX failure shutdown passed: $log"
        return
    }
    if ($result -ne 0 -or $output -notmatch 'GODOT_VFX_DIALOG_PASS' -or $output -notmatch 'VFX_DIALOG_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "VFX dialog test failed: $log" }
    foreach ($step in 0..4) { Copy-Item "artifacts/reference/vfx-dialog-$step.png" "artifacts/reference/vfx-dialog-$Driver-$RenderThread-$step.png" }
    Write-Output "VFX dialog passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; $env:GODOT_JFX_VFX_FAILURE = $savedFailure; Pop-Location }
