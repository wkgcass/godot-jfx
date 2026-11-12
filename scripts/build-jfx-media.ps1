[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME, [string]$Msys=$(if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { 'D:\msys64' }), [ValidateRange(1,32)][int]$Jobs=8, [string]$VisualStudio=$(if ($env:VSINSTALLDIR) { $env:VSINSTALLDIR } else { Join-Path $env:ProgramFiles 'Microsoft Visual Studio/2022/Community' }))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$names=@('JAVA_HOME','GRADLE_USER_HOME','VSCOMNTOOLS','VSINSTALLDIR','PATH','MSYS2_ARG_CONV_EXCL')
$saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location $root
try {
    & (Join-Path $PSScriptRoot 'build-makedepend.ps1') -Msys $Msys
    foreach($tool in @('make.exe','cygpath.exe','sh.exe')){
        if(!(Test-Path -LiteralPath (Join-Path $Msys "usr/bin/$tool"))){throw "Missing existing MSYS tool: $tool"}
    }
    $properties=Join-Path $root 'jfx/build/windows_tools.properties'
    if(!(Test-Path -LiteralPath $properties)){throw 'Build the default source JFX SDK first to configure MSVC'}
    $vsPath=(Get-Content -LiteralPath $properties | Where-Object {$_.StartsWith('WINDOWS_VS_PATH=')}) -replace '^WINDOWS_VS_PATH=',''
    if(!$vsPath){throw 'Missing configured MSVC PATH'}
    $env:JAVA_HOME=$Jdk
    $env:GRADLE_USER_HOME=Join-Path $root '.gradle-cache'
    $env:VSINSTALLDIR = $VisualStudio.Replace('/', '\').TrimEnd('\') + '\'
    $env:VSCOMNTOOLS=Join-Path $VisualStudio 'VC/Auxiliary/Build'
    # MSVC link.exe must precede MSYS coreutils' unrelated link.exe.
    $env:PATH=(Join-Path $root '.tools/makedepend/bin')+';'+$vsPath+';'+(Join-Path $Msys 'usr/bin')
    # Upstream Makefiles already use cygpath for MSVC paths. A second MSYS
    # conversion corrupts concatenated -FoD:/... and -out:D:/... arguments.
    $env:MSYS2_ARG_CONV_EXCL='*'
    # A failed upstream makedepend recipe leaves only its marker behind. Do not
    # let a later incremental build silently accept that incomplete dependency file.
    $dep=Join-Path $root 'jfx/modules/javafx.media/build/native/win/Release/obj/jfxmedia-jni/Depend.mak'
    if((Test-Path -LiteralPath $dep) -and ([IO.File]::ReadAllText($dep).Trim() -eq '# makedepend')){
        Remove-Item -LiteralPath $dep
    }
    Push-Location jfx
    try { & ./gradlew.bat sdk -PCOMPILE_MEDIA=true -PCOMPILE_WEBKIT=false "-PWINDOWS_VS_PATH=$env:PATH" --console=plain --no-daemon "--max-workers=$Jobs" *> ../artifacts/logs/jfx-media-native.log; $code=$LASTEXITCODE }
    finally {Pop-Location}
    Set-Content artifacts/logs/jfx-media-native.log.exitcode $code
    if($code -ne 0){throw 'Native Media build failed: artifacts/logs/jfx-media-native.log'}
    foreach($library in @('jfxmedia.dll','glib-lite.dll','gstreamer-lite.dll','fxplugins.dll')){
        if(!(Test-Path -LiteralPath (Join-Path $root "jfx/build/sdk/bin/$library"))){throw "Media SDK library missing: $library"}
    }
    if((Get-Content -LiteralPath $dep -Raw) -notmatch '\.obj:'){throw 'Media dependency scan did not produce object dependencies'}
    Write-Output 'Source Media SDK build passed; playback/rendering acceptance still required'
} finally {
    foreach($name in $names){if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }}
    Pop-Location
}
