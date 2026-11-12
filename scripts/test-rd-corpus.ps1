[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/logs | Out-Null
    $log='artifacts/logs/rd-corpus.log'
    & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://rd_corpus_spike.tscn --rendering-method mobile --quit-after 30000 *> $log
    $code=$LASTEXITCODE; $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'RD_CORPUS_SUMMARY exact=262 edge=0 deferred=0 failed=0' -or $output -notmatch 'RD_CORPUS_SPIKE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)'){throw "RD shader corpus failed: $log"}
    Write-Output 'RD shader corpus passed: 262 shaders within 2/255 per channel'
} finally { Pop-Location }
