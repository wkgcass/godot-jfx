#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [string]$Jdk = $env:JAVA_HOME,
    [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',
    [ValidateSet('safe')][string]$RenderThread = 'safe'
)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$saved = @{}
foreach ($name in @('JAVA_HOME','GODOT_JFX_PROFILE_COMMANDS')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxLoadingPerfProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Loading performance probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_PROFILE_COMMANDS = '1'
    $log = "agentdir/logs/vfx-loading-perf-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://vfx_loading_perf.tscn --render-thread $RenderThread *> $log
    $code = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($code -ne 0 -or $output -notmatch 'VFX_LOADING_PERF_PASS' -or $output -notmatch 'GODOT_VFX_LOADING_PERF_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError') {
        throw "Loading performance probe failed: $log"
    }
    Select-String -LiteralPath $log -Pattern '^LOADING_PERF ' | ForEach-Object { $_.Line }
    Write-Output "Loading performance profile captured (pulse timing, not physical display FPS): $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
