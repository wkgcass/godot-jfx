#Requires -Version 7.4.1
[CmdletBinding()]
param()
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log = 'agentdir/logs/render-mode-rejection.log'
    Invoke-GodotFixture --path tests/godot --script res://render_mode_rejection.gd --rendering-method gl_compatibility --render-thread separate *> $log
    $code = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    $expected = 'JavaFX hosting requires --render-thread safe; separate is unsupported.'
    if ($code -ne 0 -or $output -notmatch 'RENDER_MODE_REJECTION_PASS' -or !$output.Contains($expected)) {
        throw "Render mode rejection failed: $log"
    }
    $errors = @($output -split "`n" | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)' })
    if ($errors.Count -ne 1 -or !$errors[0].Contains($expected)) {
        throw "Unexpected diagnostics during rejection: $log"
    }
    Write-Output "Unsupported render mode rejected: $log"
} finally { Pop-Location }
