#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $log = "agentdir/logs/scene-views-$Driver.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://scene_views.tscn --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'SCENE_VIEW_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Scene view test failed. See $log" }
    Copy-Item artifacts/reference/godot-scene-view.png "artifacts/reference/godot-scene-view-$Driver.png"
    Write-Output "Scene view test passed: $log"
} finally { Pop-Location }
