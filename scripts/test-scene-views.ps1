[CmdletBinding()]
param([ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $log = "artifacts/logs/scene-views-$Renderer.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://scene_views.tscn --rendering-method $Renderer --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'SCENE_VIEW_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Scene view test failed. See $log" }
    Copy-Item artifacts/reference/godot-scene-view.png "artifacts/reference/godot-scene-view-$Renderer.png"
    Write-Output "Scene view test passed: $log"
} finally { Pop-Location }
