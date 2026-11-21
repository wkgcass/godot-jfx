#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Snapshot, [switch]$StopDuringRead, [switch]$Runtime, [switch]$SnapshotStress)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedSnapshot = $env:GODOT_JFX_SNAPSHOT
$savedSnapshotStress = $env:GODOT_JFX_SNAPSHOT_STRESS
if ($SnapshotStress) { $Snapshot = $true }
$savedReadbackStop = $env:GODOT_JFX_READBACK_STOP
if ($Snapshot -and $StopDuringRead) { throw 'Snapshot and stop probes are separate modes' }
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/ReadbackProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Readback probe compilation failed' }
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics -encoding UTF-8 -d artifacts/reference tests/reference/SnapshotProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Snapshot compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_SNAPSHOT = if ($Snapshot) { '1' } else { '0' }
    $env:GODOT_JFX_SNAPSHOT_STRESS = if ($SnapshotStress) { '1' } else { '0' }
    $env:GODOT_JFX_READBACK_STOP = if ($StopDuringRead) { '1' } else { '0' }
    $suffix = if ($Snapshot) { '-snapshot' } else { '' }
    if ($SnapshotStress) { $suffix += '-stress' }
    if ($StopDuringRead) { $suffix += '-stop' }
    if ($Runtime) { $suffix += '-runtime' }
    $log = Join-Path $root "agentdir/logs/readback-$Driver-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-readback'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/readback.tscn'), (Join-Path $root 'tests/godot/readback.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://readback.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Readback runtime fixture import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread --quit-after 3000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://readback.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($StopDuringRead -and $output -notmatch 'READBACK_STOP_OBSERVED_PENDING_REQUEST') { throw 'Pending readback stop was not exercised' }
    if ($result -ne 0 -or $output -notmatch 'READBACK_PROBE_PASS' -or $output -notmatch 'GODOT_READBACK_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Readback test failed: $log" }
    Write-Output "Readback passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_SNAPSHOT = $savedSnapshot; $env:GODOT_JFX_SNAPSHOT_STRESS = $savedSnapshotStress; $env:GODOT_JFX_READBACK_STOP = $savedReadbackStop; Pop-Location }

