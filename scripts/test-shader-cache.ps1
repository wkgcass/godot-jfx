#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedInstanceUniforms = $env:GODOT_JFX_INSTANCE_UNIFORMS
$env:GODOT_JFX_INSTANCE_UNIFORMS = "1"
Push-Location $root
try {
    $log = "agentdir/logs/shader-cache-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://shader_cache.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'SHADER_CACHE_PASS' -or $output -notmatch 'SAMPLER_MATERIAL_COLLISION_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Shader cache test failed. See $log" }
    Write-Output "Shader cache test passed: $log"
} finally { $env:GODOT_JFX_INSTANCE_UNIFORMS = $savedInstanceUniforms; Pop-Location }
