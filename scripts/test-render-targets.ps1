[CmdletBinding()]
param([ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $log = "artifacts/logs/render-targets-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://render_targets.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'RENDER_TARGET_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Render target test failed. See $log" }
    Copy-Item artifacts/reference/godot-render-targets.png "artifacts/reference/godot-render-targets-$Renderer-$RenderThread.png"
    Write-Output "Render target test passed: $log"
} finally { Pop-Location }
