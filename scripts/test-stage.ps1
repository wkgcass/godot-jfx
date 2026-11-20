#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/StageProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Stage probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/stage-$Renderer.log"
    Invoke-GodotFixture --path tests/godot res://stage.tscn --rendering-method $Renderer --quit-after 4000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_STAGE_PASS' -or $output -notmatch 'STAGE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "Stage probe failed. See $log" }
    Copy-Item artifacts/reference/godot-stage.png "artifacts/reference/godot-stage-$Renderer.png"
    Copy-Item artifacts/reference/godot-stage-interaction.png "artifacts/reference/godot-stage-interaction-$Renderer.png"
    Write-Output "Stage probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
