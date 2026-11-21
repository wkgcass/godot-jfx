#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12'
)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$log = Join-Path $root "agentdir/logs/m1-$Driver.log"
New-Item -ItemType Directory -Force (Join-Path $root 'artifacts/reference') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $root 'agentdir/logs') | Out-Null
Push-Location $root
try {
    # Frame limit prevents an unhandled GDScript error from hanging the test.
    # Exit zero alone is insufficient: an explicit PASS is required below.
    Invoke-GodotFixture -Driver $Driver --path tests/godot --quit-after 300 *> $log
    $result = $LASTEXITCODE
    Assert-GodotDriver $Driver $log
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'M1_RESULT PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:)') {
        throw "M1 failed or never completed (exit $result). See $log"
    }
    Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-m1.png') -Destination (Join-Path $root "artifacts/reference/godot-m1-$Driver.png")
    Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-prism-vertices.png') -Destination (Join-Path $root "artifacts/reference/godot-prism-vertices-$Driver.png")
    Write-Output "M1 passed on $Driver. Log: $log"
} finally {
    Pop-Location
}
