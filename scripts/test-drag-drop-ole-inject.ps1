#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Timeout)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedTimeout = $env:GODOT_JFX_OLE_TIMEOUT
$suffix = if($Timeout){'-timeout'}else{''}
$log = Join-Path $root "agentdir/logs/ole-inject-$Driver-$RenderThread$suffix.log"
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/OleInjectProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'OleInjectProbe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_OLE_TIMEOUT = if($Timeout){'1'}else{'0'}
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://ole_inject.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if($Timeout -and $output -notmatch 'OLE_TIMEOUT_CANCEL_PASS'){throw "OLE timeout checks failed: $log"}
    if ($result -ne 0 -or $output -notmatch 'GODOT_OLE_INJECT_PASS' -or $output -notmatch 'OLE_INJECT_PROBE_PASS' -or $output -notmatch 'OLE_INJECT_DROP ok=True' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "OLE inject test failed or incomplete (exit $result). See $log"
    }
    Write-Output "OLE inject test passed. Log: $log"
} finally {
    $env:JAVA_HOME = $savedJdk
    $env:GODOT_JFX_OLE_TIMEOUT = $savedTimeout
    Pop-Location
}
