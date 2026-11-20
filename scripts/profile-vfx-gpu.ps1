#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('safe')][string]$RenderThread='safe',[switch]$Host120)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk=$env:GODOT_JFX_JDK
$savedProfile=$env:GODOT_JFX_PROFILE_COMMANDS
$savedOptions=$env:JAVA_TOOL_OPTIONS
try {
    $exports=@('--add-exports=javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports=javafx.graphics/com.sun.glass.ui=ALL-UNNAMED')
    $classpath='artifacts/reference;artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls @exports -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxFrameBenchmark.java
    if ($LASTEXITCODE -ne 0) { throw 'Profiling probe compilation failed' }
    $fixture=Join-Path (Get-Location) 'artifacts/vfx-gpu-profile'
    New-Item -ItemType Directory -Force $fixture | Out-Null
    Copy-Item tests/godot/vfx_frame_benchmark.gd,tests/godot/vfx_frame_benchmark.tscn -Destination $fixture -Force
    $project=[IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://vfx_frame_benchmark.tscn')
    $project += "`n[debug]`nsettings/profiler/max_timestamp_query_elements=8192`n"
    [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
    $importLog = Join-Path (Get-Location) "agentdir/logs/vfx-gpu-profile-import.log"
    & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> $importLog
    if ($LASTEXITCODE) { throw "GPU profile fixture import failed: $importLog" }
    $env:JAVA_TOOL_OPTIONS="$savedOptions $($exports -join ' ')"
    $env:GODOT_JFX_JDK=$Jdk
    $env:GODOT_JFX_PROFILE_COMMANDS='1'
    $suffix=if($Host120){'-host120'}else{''}
    $log="agentdir/logs/vfx-gpu-profile-$RenderThread$suffix.log"
    $hostArgs=if($Host120){@('--disable-vsync','--max-fps','120')}else{@()}
    Invoke-GodotFixture --path $fixture --rendering-method mobile --render-thread $RenderThread --gpu-profile @hostArgs *> $log
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'GODOT_VFX_FRAME_BENCHMARK_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') {throw "GPU profiling failed (native exit $code): $log"}
    Write-Output "GPU/host profile captured (instrumented, not acceptance FPS): $log"
} finally {$env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_PROFILE_COMMANDS=$savedProfile;$env:JAVA_TOOL_OPTIONS=$savedOptions;Pop-Location}
