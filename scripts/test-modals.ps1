#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/ModalProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Modal probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/modals-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://modals.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_MODALS_PASS' -or $output -notmatch 'MODAL_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Modal test failed: $log" }
    Copy-Item artifacts/reference/modal-nested.png "artifacts/reference/modal-nested-$Renderer-$RenderThread.png"
    Write-Output "Modals passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
