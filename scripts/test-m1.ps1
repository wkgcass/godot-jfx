#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [ValidateSet('gl_compatibility', 'mobile')]
    [string]$Renderer = 'gl_compatibility'
)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$log = Join-Path $root "agentdir/logs/m1-$Renderer.log"
New-Item -ItemType Directory -Force (Join-Path $root 'artifacts/reference') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $root 'agentdir/logs') | Out-Null
Push-Location $root
try {
    # Frame limit prevents an unhandled GDScript error from hanging the test.
    # Exit zero alone is insufficient: an explicit PASS is required below.
    Invoke-GodotFixture --path tests/godot --rendering-method $Renderer --quit-after 300 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'M1_RESULT PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:)') {
        throw "M1 failed or never completed (exit $result). See $log"
    }
    Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-m1.png') -Destination (Join-Path $root "artifacts/reference/godot-m1-$Renderer.png")
    Copy-Item -LiteralPath (Join-Path $root 'artifacts/reference/godot-prism-vertices.png') -Destination (Join-Path $root "artifacts/reference/godot-prism-vertices-$Renderer.png")
    Write-Output "M1 passed on $Renderer. Log: $log"
} finally {
    Pop-Location
}
