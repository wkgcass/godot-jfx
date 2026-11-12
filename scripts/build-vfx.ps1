[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJava = $env:JAVA_HOME
$savedGradle = $env:GRADLE_USER_HOME
try {
    if (!(Test-Path "$root/jfx/build/sdk/lib/javafx.controls.jar")) { throw 'Build the source OpenJFX SDK first.' }
    $env:JAVA_HOME = $Jdk
    $env:GRADLE_USER_HOME = "$root/.gradle-cache"
    New-Item -ItemType Directory -Force "$root/artifacts/logs" | Out-Null
    & "$root/jfx/gradlew.bat" -p "$PSScriptRoot/vfx-build" stageRuntime --console=plain --no-daemon --max-workers=4 *> "$root/artifacts/logs/vfx-build.log"
    if ($LASTEXITCODE -ne 0) { throw 'VFX source build failed. See artifacts/logs/vfx-build.log' }
    Write-Output 'VFX sources built against the local OpenJFX SDK: artifacts/vfx'
} finally { $env:JAVA_HOME = $savedJava; $env:GRADLE_USER_HOME = $savedGradle }
