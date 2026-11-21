#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $log = "agentdir/logs/render-targets-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://render_targets.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'RENDER_TARGET_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Render target test failed. See $log" }
    Copy-Item artifacts/reference/godot-render-targets.png "artifacts/reference/godot-render-targets-$Driver-$RenderThread.png"
    Write-Output "Render target test passed: $log"
} finally { Pop-Location }
