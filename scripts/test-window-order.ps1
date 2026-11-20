#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/WindowOrderProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Window order probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/window-order-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://window_order.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_WINDOW_ORDER_PASS' -or $output -notmatch 'WINDOW_ORDER_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Window order test failed: $log" }
    foreach ($stage in 0..9) { Copy-Item "artifacts/reference/window-order-$stage.png" "artifacts/reference/window-order-$Renderer-$RenderThread-$stage.png" }
    Write-Output "Window order passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
