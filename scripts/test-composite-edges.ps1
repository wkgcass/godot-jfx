#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedOutput = $env:GODOT_JFX_EDGE_OUTPUT
Push-Location $root
try {
    $exports = @('--add-exports','javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.prism.paint=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics @exports -encoding UTF-8 -d artifacts/reference tests/reference/CompositeEdgeProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Edge probe compilation failed' }
    $reference = Join-Path $root 'artifacts/reference/composite-edges-d3d.txt'
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics @exports '-Dprism.order=d3d' "-Dedges.output=$reference" -cp artifacts/reference CompositeEdgeProbe *> agentdir/logs/composite-edges-d3d.log
    if ($LASTEXITCODE -ne 0 -or (Get-Content agentdir/logs/composite-edges-d3d.log -Raw) -notmatch 'COMPOSITE_EDGE_PROBE_PASS D3DPipeline') { throw 'D3D edge reference failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_EDGE_OUTPUT = Join-Path $root "artifacts/reference/composite-edges-$Driver-$RenderThread.txt"
    $log = "agentdir/logs/composite-edges-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://composite_edges.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_COMPOSITE_EDGES_PASS' -or $output -notmatch 'COMPOSITE_EDGE_PROBE_PASS GodotPipeline' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Edge probe failed: $log" }
    $expected = @(Get-Content $reference)
    $actual = @(Get-Content $env:GODOT_JFX_EDGE_OUTPUT)
    if ($expected.Count -ne 20 -or $actual.Count -ne 20) { throw 'Incomplete edge coverage' }
    $differences = @()
    for ($row=0; $row -lt 20; $row++) {
        $a = $actual[$row].Split(' ')
        $e = $expected[$row].Split(' ')
        if ($a.Length -ne 17 -or $e.Length -ne 17 -or $a[0] -ne $e[0]) { throw 'Edge case layout differs' }
        for ($pixel=1; $pixel -le 16; $pixel++) {
            $av = [Convert]::ToUInt32($a[$pixel],16); $ev = [Convert]::ToUInt32($e[$pixel],16)
            foreach ($shift in @(0,8,16,24)) {
                if ([Math]::Abs([int](($av -shr $shift) -band 255) - [int](($ev -shr $shift) -band 255)) -gt 2) {
                    $differences += "$($a[0]) pixel=$($pixel-1) actual=$($a[$pixel]) D3D=$($e[$pixel])"
                    break
                }
            }
        }
    }
    [IO.File]::WriteAllLines((Join-Path $root "$log.diff"), [string[]]$differences)
    if ($differences.Count -ne 0) { throw "Composite edge comparison has $($differences.Count) differing pixels; see $log.diff" }
    Write-Output "Composite edge D3D comparison passed: $log"
} finally { $env:JAVA_HOME=$savedJdk; $env:GODOT_JFX_EDGE_OUTPUT=$savedOutput; Pop-Location }
