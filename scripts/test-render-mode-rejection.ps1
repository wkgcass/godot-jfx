[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log = 'artifacts/logs/render-mode-rejection.log'
    & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot --script res://render_mode_rejection.gd --rendering-method gl_compatibility --render-thread separate *> $log
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
