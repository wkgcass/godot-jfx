#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [string]$Jdk = $env:JAVA_HOME,
    [ValidateSet('mobile','gl_compatibility')][string]$Renderer = 'mobile',
    [ValidateSet('safe')][string]$RenderThread = 'safe',
    [switch]$FullUploads
)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$saved = @{}
foreach ($name in @('GODOT_JFX_JDK','GODOT_JFX_REGION_UPLOAD','GODOT_JFX_PROFILE_COMMANDS')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxMenuPerformanceProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Menu performance probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_REGION_UPLOAD = if ($FullUploads) { '0' } else { $null }
    $env:GODOT_JFX_PROFILE_COMMANDS = '1'
    $mode = if ($FullUploads) { 'full' } else { 'default' }
    $log = "agentdir/logs/vfx-menu-$Renderer-$RenderThread-$mode.log"
    Invoke-GodotFixture --path tests/godot res://vfx_menu_performance.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    $code = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($code -ne 0 -or $output -notmatch 'VFX_MENU_PERFORMANCE_PASS' -or $output -notmatch 'GODOT_VFX_MENU_PERFORMANCE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError') {
        throw "Menu performance probe failed: $log"
    }
    Select-String -LiteralPath $log -Pattern '^MENU_PERF ' | ForEach-Object { $_.Line }
    Write-Output "Menu performance profile captured (pulse timing, not physical display FPS): $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
