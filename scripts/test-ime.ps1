#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [switch]$SpacedClick)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedSpacedClick = $env:GODOT_JFX_IME_SPACED_CLICK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/ImeProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'IME probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_IME_SPACED_CLICK = if ($SpacedClick) { '1' } else { '0' }
    $suffix = if ($SpacedClick) { "-spaced" } else { "" }
    $log = "agentdir/logs/ime-$Driver$suffix.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://ime.tscn --quit-after 4000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_IME_PASS' -or $output -notmatch 'IME_PROBE_PASS' -or $output -notmatch 'IME_MOUSE_ORDER_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception|java\.[a-z].*Exception)') { throw "IME probe failed: $log" }
    Write-Output "IME probe passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; $env:GODOT_JFX_IME_SPACED_CLICK = $savedSpacedClick; Pop-Location }
