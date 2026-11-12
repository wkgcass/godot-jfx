[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference | Out-Null
    & "$Jdk/bin/javac.exe" -encoding UTF-8 -d artifacts/reference tests/reference/PrismGodotDetectionProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Detection probe compilation failed' }
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp 'artifacts/reference;artifacts/vfx/dependencies/*' PrismGodotDetectionProbe
    if ($LASTEXITCODE -ne 0) { throw 'Prism Godot detection probe failed' }
} finally { Pop-Location }
