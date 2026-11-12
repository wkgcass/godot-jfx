[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe','separate')][string]$RenderThread = 'safe', [switch]$Profile, [ValidateRange(3,30)][int]$Sweeps = 3)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
$savedProfile = $env:GODOT_JFX_PROFILE_COMMANDS
$savedSweeps = $env:GODOT_JFX_TABLE_SWEEPS
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    $exports = @('--add-exports=javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports=javafx.graphics/com.sun.glass.ui=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls @exports -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/ThreadStackSampler.java tests/reference/VfxTableScrollProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Table scroll probe compilation failed' }
    $env:GODOT_JFX_TABLE_SWEEPS = [string]$Sweeps
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_PROFILE_COMMANDS = if ($Profile) { '1' } else { $null }
    $log = Join-Path (Get-Location) "artifacts/logs/vfx-table-scroll-$Renderer-$RenderThread$(if ($Sweeps -ne 3) { "-sweeps$Sweeps" }).log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_table_scroll.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_VFX_TABLE_SCROLL_PASS' -or $output -notmatch 'VFX_TABLE_SCROLL_PROBE_PASS' -or $output -notmatch 'VFX_TABLE_SCROLL_STATS' -or $output -notmatch 'VFX_TABLE_SCROLL_IDLE_STATS' -or $output -notmatch '(?m)^VFX_TABLE_SCROLL pulses=' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "VFX table scroll failed: $log" }
    $expected='VFX_TABLE_SCROLL_BACKEND glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline'
    if (-not $output.Contains($expected)) { throw "Unexpected Glass/Prism backend: $log" }
    $output -split "`r?`n" | Where-Object { $_ -match '^VFX_TABLE_SCROLL' }
    Write-Output "VFX table scroll passed: $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    $env:GODOT_JFX_PROFILE_COMMANDS = $savedProfile
    $env:GODOT_JFX_TABLE_SWEEPS = $savedSweeps
    Pop-Location
}
