#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',
    [switch]$CachePressure
)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$savedPressure=$env:GODOT_JFX_MESH_CACHE_PRESSURE
$savedMeshCache=$env:GODOT_JFX_MESH_CACHE
$root = Split-Path $PSScriptRoot -Parent
$suffix=if($CachePressure){'-cache-pressure'}else{''}
$log = Join-Path $root "agentdir/logs/mesh-transform-$Driver$suffix.log"
New-Item -ItemType Directory -Force (Join-Path $root 'agentdir/logs') | Out-Null
Push-Location $root
try {
    $env:GODOT_JFX_MESH_CACHE_PRESSURE=if($CachePressure){'1'}else{'0'}
    if($CachePressure){$env:GODOT_JFX_MESH_CACHE='1'}
    # Frame limit prevents an unhandled GDScript error from hanging the test.
    # Exit zero alone is insufficient: an explicit PASS is required below.
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://mesh_transform_probe.tscn --quit-after 300 *> $log
    $result = $LASTEXITCODE
    Assert-GodotDriver $Driver $log
    $output = Get-Content -LiteralPath $log -Raw
    if ($CachePressure -and ($output -notmatch 'SHARED_TARGET_MESH_CACHE_PASS' -or $output -notmatch 'SHARED_TARGET_MESH_RELEASE_PASS')) { throw "Shared target cache check missing: $log" }
    if ($result -ne 0 -or $output -notmatch 'MESH_TRANSFORM_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:)') {
        throw "Mesh transform probe failed or never completed (exit $result). See $log"
    }
    Write-Output "Mesh transform probe passed on $Driver. Log: $log"
} finally {
    $env:GODOT_JFX_MESH_CACHE_PRESSURE=$savedPressure
    $env:GODOT_JFX_MESH_CACHE=$savedMeshCache
    Pop-Location
}
