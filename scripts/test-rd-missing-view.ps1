[CmdletBinding()]
param([ValidateSet('safe','separate')][string]$RenderThread='safe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$saved=$env:GODOT_JFX_RD_DIRECT
Push-Location $root
try {
    $env:GODOT_JFX_RD_DIRECT='1'
    $log="artifacts/logs/rd-missing-view-$RenderThread.log"
    & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://rd_missing_view.tscn --rendering-method mobile --render-thread $RenderThread --quit-after 120 *> $log
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    $expected='ERROR: RD-direct: sampled texture has no device view; binding white default.'
    $errors=@($output -split '\r?\n' | Where-Object {$_ -match '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)'})
    if($code -ne 0 -or $output -notmatch 'RD_MISSING_VIEW_PASS' -or $errors.Count -ne 1 -or $errors[0] -cne $expected){
        throw "Missing-view regression failed: $log"
    }
    Write-Output "Missing-view regression passed: $log"
} finally { $env:GODOT_JFX_RD_DIRECT=$saved; Pop-Location }
