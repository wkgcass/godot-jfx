#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',[ValidateSet('wav','mp3','aiff','all')][string]$Codec='wav',[switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedJdk=$env:GODOT_JFX_JDK;$savedFile=$env:GODOT_JFX_MEDIA_FILE
$savedExpect=$env:GODOT_JFX_MEDIA_EXPECT_MS;$savedTolerance=$env:GODOT_JFX_MEDIA_TOLERANCE_MS
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media -d artifacts/reference tests/reference/MediaAudioProbe.java
    if($LASTEXITCODE -ne 0){throw 'Media audio probe compilation failed'}
    [string[]]$codecs=if($Codec -eq 'all'){@('wav','mp3','aiff')}else{$Codec}
    $audioFiles=@(& python "$PSScriptRoot/prepare-audio-fixtures.py" @codecs)
    if($LASTEXITCODE -ne 0){throw 'Audio fixture preparation failed'}
    $expectMs=@{'wav'='2000';'mp3'='2000';'aiff'='2000'}
    # MP3 frames add encoder padding around the 2 s signal; allow for it.
    $toleranceMs=@{'wav'='50';'mp3'='300';'aiff'='50'}
    $env:GODOT_JFX_JDK=$Jdk
    $fixture=$null
    for($i=0; $i -lt $codecs.Count; $i++){
        $kind=$codecs[$i]
        $env:GODOT_JFX_MEDIA_FILE=Join-Path $root $audioFiles[$i]
        $env:GODOT_JFX_MEDIA_EXPECT_MS=$expectMs[$kind];$env:GODOT_JFX_MEDIA_TOLERANCE_MS=$toleranceMs[$kind]
        $suffix=if($Runtime){'-runtime'}else{''}
        $codecTag=if($kind -eq 'wav'){''}else{"-$kind"}
        $log=Join-Path $root "agentdir/logs/media-audio-$Driver$suffix$codecTag.log"
        if($Runtime){
            if(!$fixture){
                $fixture=Join-Path $root 'artifacts/runtime-media-audio'
                New-Item -ItemType Directory -Force $fixture | Out-Null
                Copy-Item -LiteralPath (Join-Path $root 'tests/godot/media_audio.gd'),(Join-Path $root 'tests/godot/media_audio.tscn') -Destination $fixture -Force
                $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://media_audio.tscn')
                [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
                & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
                if($LASTEXITCODE -ne 0){throw "Media audio runtime import failed: $log.import"}
            }
            Push-Location $fixture
            try { Invoke-GodotFixture -Driver $Driver --render-thread safe *> $log }
            finally {Pop-Location}
        }else{
            Invoke-GodotFixture -Driver $Driver --path tests/godot res://media_audio.tscn --render-thread safe *> $log
        }
        $code=$LASTEXITCODE;$output=Get-Content $log -Raw
        if($code -ne 0 -or $output -notmatch 'MEDIA_AUDIO_PROBE_PASS' -or $output -notmatch 'GODOT_MEDIA_AUDIO_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)|uncaught:'){throw "Media audio failed ($kind): $log"}
        Write-Output "Source Media audio playback passed ($kind): $log"
    }
} finally {
    $env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_MEDIA_FILE=$savedFile
    $env:GODOT_JFX_MEDIA_EXPECT_MS=$savedExpect;$env:GODOT_JFX_MEDIA_TOLERANCE_MS=$savedTolerance
    Pop-Location
}
