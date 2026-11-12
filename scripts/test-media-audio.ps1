[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',[ValidateSet('wav','mp3','aiff','all')][string]$Codec='wav',[switch]$Runtime)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedJdk=$env:GODOT_JFX_JDK;$savedFile=$env:GODOT_JFX_MEDIA_FILE
$savedExpect=$env:GODOT_JFX_MEDIA_EXPECT_MS;$savedTolerance=$env:GODOT_JFX_MEDIA_TOLERANCE_MS
$savedEnv=@{};foreach($name in @('PATH','INCLUDE','LIB')){$savedEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$fixtureTools=@{Executable=$null}
Push-Location $root
function New-AudioFixture([string]$Kind) {
    # wav keeps the original Python one-liner; mp3/aiff come from the MSVC
    # fixture tool (Media Foundation encoder / hand-written AIFF container).
    if($Kind -eq 'wav'){
        $wave=Join-Path $root 'artifacts/reference/media-silence.wav'
        & python -c 'import wave,sys; w=wave.open(sys.argv[1],"wb"); w.setparams((1,2,44100,0,"NONE","not compressed")); w.writeframes(bytes(44100*2*2)); w.close()' $wave
        if($LASTEXITCODE -ne 0){throw 'PCM fixture generation failed'}
        return $wave
    }
    if(!$fixtureTools.Executable){
        $config=@{}
        Get-Content jfx/build/windows_tools.properties | ForEach-Object {
            $pair=$_ -split '=',2
            if($pair.Count -eq 2){$config[$pair[0]]=$pair[1]}
        }
        try {
            foreach($name in @('PATH','INCLUDE','LIB')){
                $value=$config["WINDOWS_VS_$name"]
                if(!$value){throw "Missing source-build toolchain setting: $name"}
                [Environment]::SetEnvironmentVariable($name,$value,'Process')
            }
            $target=Join-Path $root 'artifacts/reference/audio-fixture'
            New-Item -ItemType Directory -Force $target | Out-Null
            $exe=Join-Path $target 'make_audio_fixture.exe'
            $obj=Join-Path $target 'make_audio_fixture.obj'
            & cl.exe /nologo /std:c++17 /EHsc /O2 /W4 tests/native/make_audio_fixture.cpp "/Fe:$exe" "/Fo:$obj" /link mfplat.lib mfreadwrite.lib mfuuid.lib ole32.lib *> artifacts/logs/audio-fixture-build.log
            if($LASTEXITCODE -ne 0){throw 'Audio fixture compiler failed: artifacts/logs/audio-fixture-build.log'}
            $fixtureTools.Executable=$exe
        } finally {
            # Toolchain lookup paths must not leak into media playback or a
            # later fixture. The outer finally also protects early failures.
            foreach($name in @('PATH','INCLUDE','LIB')){
                if($null -eq $savedEnv[$name]){Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue}
                else{[Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process')}
            }
        }
    }
    $exe=$fixtureTools.Executable
    $output=Join-Path $root "artifacts/reference/media-tone.$Kind"
    & $exe $Kind $output *> "artifacts/logs/audio-fixture-$Kind.log"
    if($LASTEXITCODE -ne 0){throw "Audio fixture generation failed ($Kind): artifacts/logs/audio-fixture-$Kind.log"}
    $log=Get-Content "artifacts/logs/audio-fixture-$Kind.log" -Raw
    if($log -notmatch "MAKE_AUDIO_FIXTURE_PASS codec=$Kind rate=44100 seconds=2"){throw "Encoded fixture verification incomplete ($Kind)"}
    return $output
}
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    foreach($library in @('jfxmedia.dll','glib-lite.dll','gstreamer-lite.dll','fxplugins.dll')){
        if(!(Test-Path "jfx/build/sdk/bin/$library")){throw "Build source Media SDK first; missing $library"}
    }
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media -d artifacts/reference tests/reference/MediaAudioProbe.java
    if($LASTEXITCODE -ne 0){throw 'Media audio probe compilation failed'}
    $codecs=if($Codec -eq 'all'){@('wav','mp3','aiff')}else{@($Codec)}
    $expectMs=@{'wav'='2000';'mp3'='2000';'aiff'='2000'}
    # MP3 frames add encoder padding around the 2 s signal; allow for it.
    $toleranceMs=@{'wav'='50';'mp3'='300';'aiff'='50'}
    $env:GODOT_JFX_JDK=$Jdk
    $fixture=$null
    foreach($kind in $codecs){
        $mediaFile=New-AudioFixture $kind
        $env:GODOT_JFX_MEDIA_FILE=$mediaFile
        $env:GODOT_JFX_MEDIA_EXPECT_MS=$expectMs[$kind];$env:GODOT_JFX_MEDIA_TOLERANCE_MS=$toleranceMs[$kind]
        $suffix=if($Runtime){'-runtime'}else{''}
        $codecTag=if($kind -eq 'wav'){''}else{"-$kind"}
        $log=Join-Path $root "artifacts/logs/media-audio-$Renderer$suffix$codecTag.log"
        if($Runtime){
            if(!$fixture){
                $fixture=Join-Path $root 'artifacts/runtime-media-audio'
                New-Item -ItemType Directory -Force $fixture | Out-Null
                Copy-Item -LiteralPath (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.console.exe'),(Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.exe'),(Join-Path $root 'tests/godot/media_audio.gd'),(Join-Path $root 'tests/godot/media_audio.tscn') -Destination $fixture -Force
                $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://media_audio.tscn')
                [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
                & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
                if($LASTEXITCODE -ne 0){throw "Media audio runtime import failed: $log.import"}
            }
            Push-Location $fixture
            try { & (Join-Path $fixture 'godot.windows.template_release.x86_64.console.exe') --rendering-method $Renderer --render-thread safe *> $log }
            finally {Pop-Location}
        }else{
            & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://media_audio.tscn --rendering-method $Renderer --render-thread safe *> $log
        }
        $code=$LASTEXITCODE;$output=Get-Content $log -Raw
        if($code -ne 0 -or $output -notmatch 'MEDIA_AUDIO_PROBE_PASS' -or $output -notmatch 'GODOT_MEDIA_AUDIO_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)|uncaught:'){throw "Media audio failed ($kind): $log"}
        Write-Output "Source Media audio playback passed ($kind): $log"
    }
} finally {
    $env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_MEDIA_FILE=$savedFile
    $env:GODOT_JFX_MEDIA_EXPECT_MS=$savedExpect;$env:GODOT_JFX_MEDIA_TOLERANCE_MS=$savedTolerance
    foreach($name in @('PATH','INCLUDE','LIB')){
        if($null -eq $savedEnv[$name]){Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue}
        else{[Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process')}
    }
    Pop-Location
}
