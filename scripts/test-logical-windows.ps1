#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/LogicalWindowProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Logical window probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/logical-windows-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://logical_windows.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_LOGICAL_WINDOWS_PASS' -or $output -notmatch 'LOGICAL_WINDOW_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Logical window test failed: $log" }
    Copy-Item artifacts/reference/logical-windows-initial.png "artifacts/reference/logical-windows-$Driver-$RenderThread.png"
    Write-Output "Logical windows passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
