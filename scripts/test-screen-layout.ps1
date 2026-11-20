[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $modulePath = Get-GodotJfxTestModulePath
    $exports = @('--add-exports','javafx.graphics/com.sun.glass.ui=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" --module-path $modulePath --add-modules javafx.graphics @exports -d artifacts/reference tests/reference/ScreenLayoutProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Screen layout probe compilation failed' }
    & "$Jdk/bin/java.exe" --module-path $modulePath --add-modules javafx.graphics @exports -cp artifacts/reference ScreenLayoutProbe *> artifacts/logs/screen-layout.log
    if ($LASTEXITCODE -ne 0 -or (Get-Content artifacts/logs/screen-layout.log -Raw) -notmatch 'SCREEN_LAYOUT_PROBE_PASS') { throw 'Screen layout probe failed: artifacts/logs/screen-layout.log' }
    Write-Output 'Screen layout passed: artifacts/logs/screen-layout.log'
} finally { Pop-Location }
