[CmdletBinding()]
param([string]$Jdk='D:\jdk-25.0.3+9',[ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',[switch]$Runtime,[switch]$NativeD3D)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedCapture=$env:GODOT_JFX_MEDIA_CAPTURE;$savedJdk=$env:GODOT_JFX_JDK;$savedFile=$env:GODOT_JFX_MEDIA_FILE
Push-Location $root
try {
    if($Runtime -and $NativeD3D){throw 'Choose either Godot Runtime or native D3D'}
    foreach($library in @('jfxmedia.dll','glib-lite.dll','gstreamer-lite.dll','fxplugins.dll')){
        if(!(Test-Path "jfx/build/sdk/bin/$library")){throw "Build source Media SDK first; missing $library"}
    }
    $videoFile=Join-Path $root 'artifacts/reference/media-oracle-sample.mp4'
    if(!(Test-Path $videoFile)){Invoke-WebRequest -Uri 'https://download.oracle.com/otndocs/products/javafx/oow2010-2.mp4' -OutFile $videoFile}
    if((Get-FileHash $videoFile -Algorithm SHA256).Hash -ne 'A6B3928991253A7828052612C8B6CEC25F5DE3648A361F92E5C2ECE9A37D7D34'){throw 'Video fixture checksum differs'}
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media,javafx.swing -d artifacts/reference tests/reference/MediaVideoProbe.java
    if($LASTEXITCODE -ne 0){throw 'Media video probe compilation failed'}
    $env:GODOT_JFX_JDK=$Jdk;$env:GODOT_JFX_MEDIA_FILE=$videoFile
    $suffix=if($NativeD3D){'-d3d'}elseif($Runtime){'-runtime'}else{''}
    $env:GODOT_JFX_MEDIA_CAPTURE=Join-Path $root "artifacts/reference/media-video-$Renderer$suffix.png"
    $log=Join-Path $root "artifacts/logs/media-video-$Renderer$suffix.log"
    if($NativeD3D){
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media,javafx.swing --enable-native-access=javafx.graphics,javafx.media '-Dprism.order=d3d' -cp artifacts/reference MediaVideoProbe *> $log
    }elseif($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-media-video'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.console.exe'),(Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.exe'),(Join-Path $root 'tests/godot/media_video.gd'),(Join-Path $root 'tests/godot/media_video.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://media_video.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "Media video runtime import failed: $log.import"}
        Push-Location $fixture
        try { & (Join-Path $fixture 'godot.windows.template_release.x86_64.console.exe') --rendering-method $Renderer --render-thread safe *> $log }
        finally {Pop-Location}
    }else{
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://media_video.tscn --rendering-method $Renderer --render-thread safe *> $log
    }
    $code=$LASTEXITCODE;$output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'MEDIA_VIDEO_PROBE_PASS' -or $output -notmatch 'MEDIA_VIDEO_CONTROLS_PASS' -or (!$NativeD3D -and $output -notmatch 'GODOT_MEDIA_VIDEO_PASS') -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "Media video failed: $log"}
    Write-Output "Source Media video playback passed: $log"
} finally {$env:GODOT_JFX_MEDIA_CAPTURE=$savedCapture;$env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_MEDIA_FILE=$savedFile;Pop-Location}

