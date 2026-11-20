#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $source = 'jfx/modules/javafx.graphics/src/main/java/com/sun/glass/ui/godot'
    $patch = 'artifacts/pulse-stop-patch'
    New-Item -ItemType Directory -Force $patch,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --patch-module "javafx.graphics=$source" -d $patch "$source/GodotPulseScheduler.java"
    if ($LASTEXITCODE -ne 0) { throw 'Scheduler patch compilation failed' }
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --patch-module "javafx.graphics=$patch" --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -d artifacts/reference tests/reference/PulseStopProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Pulse stop probe compilation failed' }
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --patch-module "javafx.graphics=$patch" --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -cp artifacts/reference PulseStopProbe *> agentdir/logs/pulse-stop.log
    if ($LASTEXITCODE -ne 0 -or (Get-Content agentdir/logs/pulse-stop.log -Raw) -notmatch 'PULSE_STOP_PROBE_PASS') { throw 'Pulse stop failed: agentdir/logs/pulse-stop.log' }
    Write-Output 'Pulse stop passed: agentdir/logs/pulse-stop.log'
} finally { Pop-Location }
