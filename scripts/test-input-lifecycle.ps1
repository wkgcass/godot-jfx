[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/InputLifecycleProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Input lifecycle probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "artifacts/logs/input-lifecycle-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://input_lifecycle.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_INPUT_LIFECYCLE_PASS' -or $output -notmatch 'INPUT_LIFECYCLE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Input lifecycle test failed: $log" }
    Write-Output "Input lifecycle passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }

