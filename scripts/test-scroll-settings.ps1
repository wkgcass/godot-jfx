[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $options = @('--module-path',(Get-GodotJfxTestModulePath),'--add-modules','javafx.graphics',
        '--add-exports','javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" @options -encoding UTF-8 -d artifacts/reference tests/reference/ScrollSettingsProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Scroll settings probe compilation failed' }
    & "$Jdk/bin/java.exe" @options -cp artifacts/reference ScrollSettingsProbe *> artifacts/logs/scroll-settings.log
    if ($LASTEXITCODE -ne 0 -or (Get-Content artifacts/logs/scroll-settings.log -Raw) -notmatch '^SCROLL_SETTINGS_PASS') {
        throw 'Scroll settings failed: artifacts/logs/scroll-settings.log'
    }
    Write-Output 'Scroll settings codec passed'
} finally { Pop-Location }
