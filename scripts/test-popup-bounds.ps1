[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/PopupBoundsProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Popup bounds probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "artifacts/logs/popup-bounds-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://popup_bounds.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_POPUP_BOUNDS_PASS' -or $output -notmatch 'POPUP_BOUNDS_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Popup bounds test failed: $log" }
    Copy-Item artifacts/reference/popup-bounds.png "artifacts/reference/popup-bounds-$Renderer-$RenderThread.png"
    Write-Output "Popup bounds passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }

