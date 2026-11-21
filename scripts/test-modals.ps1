#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/ModalProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Modal probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/modals-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://modals.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_MODALS_PASS' -or $output -notmatch 'MODAL_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Modal test failed: $log" }
    Copy-Item artifacts/reference/modal-nested.png "artifacts/reference/modal-nested-$Driver-$RenderThread.png"
    Write-Output "Modals passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
