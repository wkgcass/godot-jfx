#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread='safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log="agentdir/logs/texture-lookup-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://texture_lookup.tscn --render-thread $RenderThread *> $log
    $output=Get-Content $log -Raw
    if($LASTEXITCODE -ne 0 -or $output -notmatch 'TEXTURE_LOOKUP_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') {throw "Texture lookup failed: $log"}
    Write-Output ($output -split "`n" | Where-Object {$_ -match 'TEXTURE_LOOKUP_PASS'})
} finally {Pop-Location}
