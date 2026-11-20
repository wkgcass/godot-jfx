#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/NativeImeProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'IME probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/native-ime-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://native_ime.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 4000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_NATIVE_IME_PASS' -or $output -notmatch 'NATIVE_IME_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception|java\.[a-z].*Exception)') { throw "IME probe failed: $log" }
    Write-Output "IME probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }

