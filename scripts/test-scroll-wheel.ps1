#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics,javafx.controls --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/ScrollWheelProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Scroll wheel probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = Join-Path $root "agentdir/logs/scroll_wheel-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://scroll_wheel.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 2400 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'SCROLL_WHEEL_PROBE_PASS' -or $output -notmatch 'GODOT_SCROLL_WHEEL_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:') { throw "Scroll wheel test failed: $log" }
    $scrollResult = [regex]::Match($output, '(?m)^SCROLL_RESULT events=3 pixels=(?<px>[0-9.]+) expected=[0-9.]+\r?$')
    if (!$scrollResult.Success) { throw "Missing three-notch scroll measurement: $log" }
    $delta = $scrollResult.Groups['px'].Value
    Write-Output "Scroll wheel passed (3 notches = $delta px): $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
