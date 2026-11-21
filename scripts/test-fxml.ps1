#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.fxml --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/FXMLProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'FXML probe compilation failed' }
    New-Item -ItemType Directory -Force artifacts/reference/fxml | Out-Null
    Copy-Item tests/reference/fxml/* -Destination artifacts/reference/fxml -Force
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path (Get-Location) "agentdir/logs/fxml-$Driver-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-fxml'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'tests/godot/fxml.gd', 'tests/godot/fxml.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://fxml.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "FXML runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://fxml.tscn --render-thread $RenderThread *> $log
    }
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_FXML_PASS' -or $output -notmatch 'FXML_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "FXML failed: $log" }
    foreach ($step in 0..3) { Copy-Item "artifacts/reference/fxml-$step.png" "artifacts/reference/fxml-$Driver-$RenderThread$suffix-$step.png" }
    Write-Output "FXML passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
