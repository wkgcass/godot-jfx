[CmdletBinding()]
param(
    [ValidateSet('godot-editor', 'godot-runtime', 'jfx')]
    [string]$Target = 'godot-editor',
    [string]$Jdk = $env:JAVA_HOME,
    [string]$VisualStudio = $(if ($env:VSINSTALLDIR) { $env:VSINSTALLDIR } else { Join-Path $env:ProgramFiles 'Microsoft Visual Studio/2022/Community' }),
    [ValidateRange(1, 64)][int]$Jobs = 8,
    [switch]$WithJavaFXModule,
    [ValidateSet('yes', 'no')][string]$JavaFXRDDirect = 'yes'
)
$ErrorActionPreference = 'Stop'
if ($PSBoundParameters.ContainsKey('JavaFXRDDirect') -and ($Target -eq 'jfx' -or !$WithJavaFXModule)) {
    throw '-JavaFXRDDirect requires a Godot target with -WithJavaFXModule; the same JFX SDK supports both builds.'
}
$root = Split-Path $PSScriptRoot -Parent
$logs = Join-Path $root 'artifacts/logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$suffix = if ($WithJavaFXModule) { '-javafx' } else { '' }
if ($WithJavaFXModule) { $suffix += "-rd-$JavaFXRDDirect" }
$log = Join-Path $logs "$Target$suffix.log"
$saved = @{}
foreach ($name in @('JAVA_HOME', 'GRADLE_USER_HOME', 'VSCOMNTOOLS', 'VSINSTALLDIR')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location $root
try {
    if ($Target -eq 'jfx') {
        if (!(Test-Path "$Jdk/bin/javac.exe")) { throw "Missing JDK: $Jdk" }
        $env:JAVA_HOME = $Jdk
        $env:GRADLE_USER_HOME = Join-Path $root '.gradle-cache'
        $env:VSINSTALLDIR = $VisualStudio.Replace('/', '\').TrimEnd('\') + '\'
        $env:VSCOMNTOOLS = Join-Path $VisualStudio 'VC/Auxiliary/Build'
        Set-Location (Join-Path $root 'jfx')
        & .\gradlew.bat sdk --console=plain --no-daemon "--max-workers=$Jobs" *> $log
    } else {
        $python = Join-Path $root '.tools/python/Scripts/python.exe'
        if (!(Test-Path $python)) { throw 'Create .tools/python and install SCons 4.10.1 first.' }
        $deps = Join-Path $root '.tools/localappdata/Godot/build_deps'
        $godotTarget = if ($Target -eq 'godot-editor') { 'editor' } else { 'template_release' }
        $moduleArgs = @()
        if ($WithJavaFXModule) {
            if (!(Test-Path "$Jdk/include/jni.h")) { throw "Missing JDK JNI headers: $Jdk" }
            $env:JAVA_HOME = $Jdk
            $moduleArgs += "custom_modules=$(Join-Path $root 'native/godot_modules')"
            $moduleArgs += "javafx_rd_direct=$JavaFXRDDirect"
        }
        & $python -m SCons -C godot platform=windows arch=x86_64 "target=$godotTarget" msvc_version=14.3 "-j$Jobs" "accesskit_sdk_path=$deps/accesskit" "mesa_libs=$deps/mesa" "agility_sdk_path=$deps/agility_sdk" "pix_path=$deps/pix" @moduleArgs *> $log
    }
    $result = $LASTEXITCODE
    Set-Content -LiteralPath "$log.exitcode" -Value $result
    if ($result -ne 0) { throw "Build failed ($result). See $log" }
    Write-Output "Build succeeded. Log: $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) {
        if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}
