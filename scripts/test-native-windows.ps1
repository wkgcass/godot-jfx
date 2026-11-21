#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $log = "agentdir/logs/native-windows-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://native_windows.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'NATIVE_WINDOWS_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Native windows test failed: $log" }
    Write-Output "Native windows passed: $log"
} finally { Pop-Location }
