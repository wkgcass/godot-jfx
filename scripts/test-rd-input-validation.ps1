[CmdletBinding()]
param([ValidateSet('safe','separate')][string]$RenderThread='safe')
$ErrorActionPreference='Stop'
$savedRd=$env:GODOT_JFX_RD_DIRECT
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/logs | Out-Null
    $env:GODOT_JFX_RD_DIRECT='1'
    $log="artifacts/logs/rd-input-validation-$RenderThread.log"
    & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot --script res://rd_input_validation.gd --rendering-method mobile --render-thread $RenderThread --quit-after 1200 *> $log
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    $errors=@($output -split "`r?`n" | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' })
    $expected=@('ERROR: 3D Prism projection is not implemented.','ERROR: Invalid RD Prism geometry shape.','ERROR: Non-finite RD Prism vertex.','ERROR: Invalid RD Prism geometry shape.','ERROR: Invalid RD Prism geometry shape.')
    if ($code -ne 0 -or $output -notmatch 'RD_INPUT_VALIDATION_PASS cases=5' -or $errors.Count -ne $expected.Count) { throw "RD input validation failed: $log" }
    for ($i=0;$i -lt $expected.Count;$i++) {
        if ($errors[$i] -cne $expected[$i]) { throw "Unexpected rejection diagnostic: $($errors[$i]); see $log" }
    }
    Write-Output "RD input validation passed: $log"
} finally { $env:GODOT_JFX_RD_DIRECT=$savedRd; Pop-Location }
