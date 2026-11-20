[CmdletBinding()]
param(
    [ValidateSet('godot-editor', 'godot-library', 'jfx', 'jfx-media')]
    [string]$Target = 'godot-library',
    [string]$Jdk = $env:JAVA_HOME,
    [string]$VisualStudio = $(if ($env:VSINSTALLDIR) { $env:VSINSTALLDIR } else { Join-Path $env:ProgramFiles 'Microsoft Visual Studio/2022/Community' }),
    [ValidateRange(1, 64)][int]$Jobs = 8,
    [switch]$Clean,
    [string]$Msys = $(if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { 'D:\msys64' })
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native-output.ps1"
$root = Split-Path $PSScriptRoot -Parent
$logs = Join-Path $root 'artifacts/logs'
if ($Target -eq 'jfx-media' -and $Clean) { throw 'Use -Target jfx -Clean to clean the OpenJFX build, including Media.' }
New-Item -ItemType Directory -Force $logs | Out-Null
$action = if ($Clean) { 'Clean' } else { 'Build' }
$log = Join-Path $logs $(if ($Clean) { "clean-$Target.log" } elseif ($Target -eq 'jfx-media') { 'jfx-media-native.log' } else { "$Target.log" })
$buildJfx = $Target -in 'jfx', 'jfx-media'
$saved = @{}
foreach ($name in @('JAVA_HOME', 'ANT_HOME', 'GRADLE_USER_HOME', 'VSCOMNTOOLS', 'VSINSTALLDIR')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
if ($buildJfx -and !$Clean) {
    $saved['PATH'] = $env:PATH
    $saved['MSYS2_ARG_CONV_EXCL'] = $env:MSYS2_ARG_CONV_EXCL
}
Push-Location $root
try {
    if ($buildJfx) {
        if (!(Test-Path "$Jdk/bin/javac.exe")) { throw "Missing JDK: $Jdk" }
        $env:JAVA_HOME = $Jdk
        if (!$env:ANT_HOME) { $env:ANT_HOME = Join-Path $root '.tools/apache-ant-1.10.15' }
        $env:GRADLE_USER_HOME = Join-Path $root '.gradle-cache'
        $env:VSINSTALLDIR = $VisualStudio.Replace('/', '\').TrimEnd('\') + '\'
        $env:VSCOMNTOOLS = Join-Path $VisualStudio 'VC/Auxiliary/Build'
        [string[]]$gradleArgs = if ($Clean) { @('cleanAll', '--no-problems-report') } else { @('sdk') }
        if (!$Clean) {
            & "$PSScriptRoot/build-makedepend.ps1" -Msys $Msys
            foreach ($tool in 'make.exe', 'cygpath.exe', 'sh.exe') {
                if (!(Test-Path -LiteralPath (Join-Path $Msys "usr/bin/$tool"))) { throw "Missing existing MSYS tool: $tool" }
            }
            # Resolve the x64 compiler before starting Gradle, including on a fresh checkout.
            $vsEnv = & $env:ComSpec /d /c 'call "%VSCOMNTOOLS%\vcvars64.bat" >nul && set PATH'
            $vsPath = ($vsEnv -match '^PATH=') -replace '^PATH=', ''
            if ($LASTEXITCODE -ne 0 -or !$vsPath) { throw "Could not initialize the x64 MSVC toolchain in $VisualStudio" }
            $scanner = Join-Path $root '.tools/makedepend/bin'
            $msysBin = Join-Path $Msys 'usr/bin'
            # Gradle launches make; make must find MSVC link.exe ahead of MSYS link.exe.
            $env:PATH = "$scanner;$vsPath;$msysBin"
            $env:MSYS2_ARG_CONV_EXCL = '*'
            $gradleArgs += '-PCOMPILE_MEDIA=true', '-PCOMPILE_WEBKIT=false', "-PWINDOWS_VS_PATH=$env:PATH"
            # Retry incomplete dependency scans left by an earlier failed Make recipe.
            $dep = Join-Path $root 'jfx/modules/javafx.media/build/native/win/Release/obj/jfxmedia-jni/Depend.mak'
            if ((Test-Path -LiteralPath $dep) -and [IO.File]::ReadAllText($dep).Trim() -eq '# makedepend') {
                Remove-Item -LiteralPath $dep
            }
        }
        Set-Location (Join-Path $root 'jfx')
        Invoke-NativeOutput .\gradlew.bat @gradleArgs --console=plain --no-daemon "--max-workers=$Jobs" | Out-File -Encoding utf8 -LiteralPath $log
    } else {
        $python = Join-Path $root '.tools/python/Scripts/python.exe'
        if (!(Test-Path $python)) { throw 'Create .tools/python and install SCons 4.10.1 first.' }
        $deps = Join-Path $root '.tools/localappdata/Godot/build_deps'
        $godotTarget = if ($Target -eq 'godot-editor') { 'editor' } else { 'template_release' }
        $moduleArgs = @()
        if ($Clean) { $moduleArgs += '--clean' }
        if ($Target -eq 'godot-library') {
            $moduleArgs += @('library_type=shared_library', 'disable_path_overrides=no', 'extra_suffix=library', 'windows_subsystem=console')

            if (!(Test-Path "$Jdk/include/jni.h")) { throw "Missing JDK JNI headers: $Jdk" }
            $env:JAVA_HOME = $Jdk
            $moduleArgs += "custom_modules=$(Join-Path $root 'native/godot_modules')"
        }
        Invoke-NativeOutput $python -m SCons -C godot platform=windows arch=x86_64 "target=$godotTarget" msvc_version=14.3 "-j$Jobs" "accesskit_sdk_path=$deps/accesskit" "mesa_libs=$deps/mesa" "agility_sdk_path=$deps/agility_sdk" "pix_path=$deps/pix" @moduleArgs | Out-File -Encoding utf8 -LiteralPath $log
    }
    $result = $LASTEXITCODE
    Set-Content -LiteralPath "$log.exitcode" -Value $result
    if ($result -ne 0) { throw "$action failed ($result). See $log" }
    if ($buildJfx -and !$Clean) {
        foreach ($library in 'jfxmedia.dll', 'glib-lite.dll', 'gstreamer-lite.dll', 'fxplugins.dll') {
            if (!(Test-Path -LiteralPath "$root/jfx/build/sdk/bin/$library")) { throw "Media SDK library missing: $library" }
        }
        if ((Get-Content -LiteralPath $dep -Raw) -notmatch '\.obj:') { throw 'Media dependency scan did not produce object dependencies' }
    }
    Write-Output "$action succeeded. Log: $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) {
        if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}
