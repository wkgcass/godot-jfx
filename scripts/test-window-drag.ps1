[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/WindowDragProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Window drag probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = Join-Path $root "artifacts/logs/window_drag-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://window_drag.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 5400 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'WINDOW_DRAG_PROBE_PASS' -or $output -notmatch 'GODOT_WINDOW_DRAG_PASS' -or $output -notmatch 'DRAG_LAG_AVG' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Window drag test failed: $log" }
    $lag = [regex]::Match($output, 'DRAG_LAG_AVG (?<avg>[0-9.]+)').Groups['avg'].Value
    $worst = [regex]::Match($output, 'DRAG_LAG_MAX (?<max>[0-9]+)').Groups['max'].Value
    Write-Output "Window drag passed (avg lag $lag frames, max $worst): $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    Pop-Location
}
