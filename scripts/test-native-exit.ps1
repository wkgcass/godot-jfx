#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log = "agentdir/logs/native-exit-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://native_exit.tscn --render-thread $RenderThread --quit-after 1500 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'NATIVE_EXIT_PASS' -or ([regex]::Matches($output,'NATIVE_EXIT_CYCLE ')).Count -ne 12 -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Native exit test failed: $log" }
    Write-Output "Native exit passed: $log"
} finally { Pop-Location }
