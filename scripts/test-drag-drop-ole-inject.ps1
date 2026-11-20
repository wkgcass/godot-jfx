#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Timeout)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedTimeout = $env:GODOT_JFX_OLE_TIMEOUT
$suffix = if($Timeout){'-timeout'}else{''}
$log = Join-Path $root "agentdir/logs/ole-inject-$Renderer-$RenderThread$suffix.log"
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/OleInjectProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'OleInjectProbe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_OLE_TIMEOUT = if($Timeout){'1'}else{'0'}
    Invoke-GodotFixture --path tests/godot res://ole_inject.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if($Timeout -and $output -notmatch 'OLE_TIMEOUT_CANCEL_PASS'){throw "OLE timeout checks failed: $log"}
    if ($result -ne 0 -or $output -notmatch 'GODOT_OLE_INJECT_PASS' -or $output -notmatch 'OLE_INJECT_PROBE_PASS' -or $output -notmatch 'OLE_INJECT_DROP ok=True' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "OLE inject test failed or incomplete (exit $result). See $log"
    }
    Write-Output "OLE inject test passed. Log: $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    $env:GODOT_JFX_OLE_TIMEOUT = $savedTimeout
    Pop-Location
}
