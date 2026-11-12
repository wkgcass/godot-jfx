[CmdletBinding()]
param([ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe','separate')][string]$RenderThread = 'separate')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log = "artifacts/logs/native-exit-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://native_exit.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 1500 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'NATIVE_EXIT_PASS' -or ([regex]::Matches($output,'NATIVE_EXIT_CYCLE ')).Count -ne 12 -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Native exit test failed: $log" }
    Write-Output "Native exit passed: $log"
} finally { Pop-Location }
