#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Transform, [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedTransform = $env:GODOT_JFX_TEST_VIEW_TRANSFORM
Push-Location $root
try {
    if($Transform){
        & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing -d artifacts/reference tests/reference/TransformClipReference.java
        if($LASTEXITCODE -ne 0){throw 'Transform clip reference compilation failed'}
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing --enable-native-access=javafx.graphics '-Dprism.order=d3d' -cp artifacts/reference TransformClipReference *> agentdir/logs/transform-clip-d3d.log
        if($LASTEXITCODE -ne 0 -or (Get-Content agentdir/logs/transform-clip-d3d.log -Raw) -notmatch 'TRANSFORM_CLIP_REFERENCE_PASS'){throw 'D3D transform clip reference failed'}
    }
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/GodotViewProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'GodotView probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_TEST_VIEW_TRANSFORM = if($Transform){'1'}else{'0'}
    $suffix = ''
    if($Transform){$suffix += '-transform'}
    if($Runtime){$suffix += '-runtime'}
    $log = Join-Path $root "agentdir/logs/godot-view-$Driver$suffix.log"
    if($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-godot-view'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        foreach($file in @('godot_view.tscn','godot_view_test.gd','embedded_scene.tscn','embedded_scene.gd')){
            Copy-Item -LiteralPath (Join-Path $root "tests/godot/$file") -Destination $fixture -Force
        }
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://godot_view.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "GodotView runtime import failed: $log.import"}
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread --quit-after 4000 *> $log }
        finally { Pop-Location }
    }else{
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://godot_view.tscn --render-thread $RenderThread --quit-after 4000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_VIEW_PASS' -or $output -notmatch 'GODOT_VIEW_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "GodotView probe failed. See $log" }
    Copy-Item artifacts/reference/godot-view.png "artifacts/reference/godot-view-$Driver$suffix.png"
    Write-Output "GodotView probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_TEST_VIEW_TRANSFORM = $savedTransform; Pop-Location }
