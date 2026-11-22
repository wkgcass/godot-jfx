#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/HostLifetimeProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Host lifetime probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path $root "agentdir/logs/host-lifetime-$Driver-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-host-lifetime'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/host_lifetime.tscn'), (Join-Path $root 'tests/godot/host_lifetime_test.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://host_lifetime.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'), $project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Runtime fixture import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread --quit-after 10000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://host_lifetime.tscn --render-thread $RenderThread --quit-after 10000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_HOST_LIFETIME_PASS' -or $output -notmatch 'HOST_LIFETIME_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Host lifetime test failed: $log" }
    Write-Output "Host lifetime passed: $log"
} finally { $env:JAVA_HOME = $savedJdk; Pop-Location }

