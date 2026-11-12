[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/NestedMenuProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Nested menu probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "artifacts/logs/nested-menu-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://nested_menu.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_NESTED_MENU_PASS' -or $output -notmatch 'NESTED_MENU_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Nested menu test failed: $log" }
    Copy-Item artifacts/reference/nested-menu.png "artifacts/reference/nested-menu-$Renderer-$RenderThread.png"
    Write-Output "Nested menu passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }

