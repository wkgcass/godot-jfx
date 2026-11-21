#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',[switch]$Runtime,[switch]$NativeD3D,[ValidateSet('oracle','lk')][string]$Sample='oracle')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedCapture=$env:GODOT_JFX_MEDIA_CAPTURE;$savedJdk=$env:GODOT_JFX_JDK;$savedFile=$env:GODOT_JFX_MEDIA_FILE
Push-Location $root
try {
    if ($NativeD3D -and $PSBoundParameters.ContainsKey('Driver')) { throw 'Driver selects Godot. Omit it for the native JavaFX comparison.' }
    if($Runtime -and $NativeD3D){throw 'The isolated Godot project requires the Godot backend'}
    if ($NativeD3D) {
        foreach($library in @('jfxmedia.dll','glib-lite.dll','gstreamer-lite.dll','fxplugins.dll')){
            if(!(Test-Path "jfx/build/sdk/bin/$library")){throw "Build source Media SDK first; missing $library"}
        }
    }
    $relative = & python "$PSScriptRoot/setup-env.py" --sample-path $Sample.ToLowerInvariant()
    if ($LASTEXITCODE) { throw "Could not prepare playback input: $Sample" }
    $videoFile = Join-Path $root $relative
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media,javafx.swing -d artifacts/reference tests/reference/MediaVideoProbe.java
    if($LASTEXITCODE -ne 0){throw 'Media video probe compilation failed'}
    $env:GODOT_JFX_JDK=$Jdk;$env:GODOT_JFX_MEDIA_FILE=$videoFile
    $suffix=if($NativeD3D){'-d3d'}elseif($Runtime){'-runtime'}else{''}
    if ($Sample -eq 'lk') { $suffix += '-lk' }
    $env:GODOT_JFX_MEDIA_CAPTURE=Join-Path $root "artifacts/reference/media-video-$Driver$suffix.png"
    $log=Join-Path $root "agentdir/logs/media-video-$Driver$suffix.log"
    if($NativeD3D){
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media,javafx.swing --enable-native-access=javafx.graphics,javafx.media '-Dprism.order=d3d' -cp artifacts/reference MediaVideoProbe *> $log
    }elseif($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-media-video'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/media_video.gd'),(Join-Path $root 'tests/godot/media_video.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://media_video.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "Media video runtime import failed: $log.import"}
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread safe *> $log }
        finally {Pop-Location}
    }else{
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://media_video.tscn --render-thread safe *> $log
    }
    $code=$LASTEXITCODE;$output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'MEDIA_VIDEO_PROBE_PASS' -or $output -notmatch 'MEDIA_VIDEO_CONTROLS_PASS' -or (!$NativeD3D -and $output -notmatch 'GODOT_MEDIA_VIDEO_PASS') -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "Media video failed: $log"}
    Write-Output "Source Media video playback passed: $log"
} finally {$env:GODOT_JFX_MEDIA_CAPTURE=$savedCapture;$env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_MEDIA_FILE=$savedFile;Pop-Location}

