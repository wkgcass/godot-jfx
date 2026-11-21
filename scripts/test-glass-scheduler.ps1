#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$log = Join-Path $root 'agentdir/logs/m2-glass-scheduler.log'
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/GlassSchedulerProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'GlassSchedulerProbe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://scheduler.tscn --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'M2_GLASS_SCHEDULER_PASS' -or $output -notmatch 'GLASS_SCHEDULER_PASS:' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "Glass scheduler test failed or incomplete (exit $result). See $log"
    }
    Write-Output "Glass scheduler test passed. Log: $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    Pop-Location
}
