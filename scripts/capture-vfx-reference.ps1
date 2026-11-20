#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateRange(1,1000)][int]$PageLimit = 1000, [switch]$FreezeFusion)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    $classpath = 'artifacts/reference;artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxReference.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX reference compilation failed' }
    $freeze = $FreezeFusion.IsPresent.ToString().ToLowerInvariant()
    $suffix = if ($FreezeFusion) { '-frozen' } else { '' }
    $logPath = "agentdir/logs/vfx-reference$suffix.log"
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing --enable-native-access=javafx.graphics,ALL-UNNAMED '-Dprism.order=d3d' "-Dvfx.reference.pages=$PageLimit" "-Dvfx.freeze.fusion=$freeze" -cp $classpath VfxReference *> $logPath
    $log = Get-Content $logPath -Raw
    if ($LASTEXITCODE -ne 0 -or $log -notmatch 'VFX_REFERENCE_PASS' -or $log -match '(?m)^(Exception|java\.[a-z].*Exception)') { throw "VFX D3D reference failed: $logPath" }
    Write-Output "VFX D3D reference captured: artifacts/reference/vfx-pages-d3d$suffix"
} finally { Pop-Location }
