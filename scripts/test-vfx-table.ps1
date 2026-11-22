#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:JAVA_HOME
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxTableProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX table probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path (Get-Location) "agentdir/logs/vfx-table-$Driver-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-vfx-table'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'tests/godot/vfx_table.gd', 'tests/godot/vfx_table.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://vfx_table.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "VFX table runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://vfx_table.tscn --render-thread $RenderThread *> $log
    }
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_VFX_TABLE_PASS' -or $output -notmatch 'VFX_TABLE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "VFX table failed: $log" }
    foreach ($step in 0..7) { Copy-Item "artifacts/reference/vfx-table-$step.png" "artifacts/reference/vfx-table-$Driver-$RenderThread$suffix-$step.png" }
    Write-Output "VFX table passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; Pop-Location }
