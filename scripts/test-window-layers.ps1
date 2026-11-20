#Requires -Version 7.4.1
[CmdletBinding()]
param([ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $log = "agentdir/logs/window-layers-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://window_layers.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'WINDOW_LAYERS_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Window layers failed: $log" }
    Copy-Item artifacts/reference/window-layers.png "artifacts/reference/window-layers-$Renderer-$RenderThread.png"
    Write-Output "Window layers passed: $log"
} finally { Pop-Location }
