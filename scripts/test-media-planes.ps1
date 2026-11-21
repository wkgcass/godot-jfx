#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedJdk=$env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -d artifacts/reference tests/reference/MediaPlanesProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Media planes compilation failed' }
    $env:GODOT_JFX_JDK=$Jdk
    $log=Join-Path $root "agentdir/logs/media-planes-$Driver.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://media_planes.tscn --render-thread safe --quit-after 3000 *> $log
    $result=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'MEDIA_PLANES_PROBE_PASS' -or $output -notmatch 'GODOT_MEDIA_PLANES_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Media planes failed: $log" }
    Write-Output "Media planes passed: $log"
} finally { $env:GODOT_JFX_JDK=$savedJdk; Pop-Location }
