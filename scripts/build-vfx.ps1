#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native-output.ps1"
$root = Split-Path $PSScriptRoot -Parent
$savedJava = $env:JAVA_HOME
$savedGradle = $env:GRADLE_USER_HOME
try {
    if (!(Test-Path "$root/jfx/build/sdk/lib/javafx.controls.jar")) { throw 'Build the source OpenJFX SDK first.' }
    $env:JAVA_HOME = $Jdk
    $env:GRADLE_USER_HOME = "$root/.gradle-cache"
    New-Item -ItemType Directory -Force "$root/agentdir/logs" | Out-Null
    & "$PSScriptRoot/stage-godot-library.ps1" -Jdk $Jdk
    Invoke-NativeOutput "$root/jfx/gradlew.bat" -p "$PSScriptRoot/vfx-build" stageRuntime shadowJar --console=plain --no-daemon --max-workers=4 | Out-File -Encoding utf8 -LiteralPath "$root/agentdir/logs/vfx-build.log"
    if ($LASTEXITCODE -ne 0) { throw 'VFX source build failed. See agentdir/logs/vfx-build.log' }
    Write-Output 'VFX Demo JAR: artifacts/vfx/libs/vfx-demo.jar'
} finally { $env:JAVA_HOME = $savedJava; $env:GRADLE_USER_HOME = $savedGradle }
