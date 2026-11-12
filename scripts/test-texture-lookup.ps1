[CmdletBinding()]
param([ValidateSet('gl_compatibility','mobile')][string]$Renderer='mobile', [ValidateSet('safe','separate')][string]$RenderThread='separate')
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log="artifacts/logs/texture-lookup-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://texture_lookup.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    $output=Get-Content $log -Raw
    if($LASTEXITCODE -ne 0 -or $output -notmatch 'TEXTURE_LOOKUP_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') {throw "Texture lookup failed: $log"}
    Write-Output ($output -split "`n" | Where-Object {$_ -match 'TEXTURE_LOOKUP_PASS'})
} finally {Pop-Location}
