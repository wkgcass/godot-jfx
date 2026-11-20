#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME, [ValidateSet('d3d','safe')][string]$Backend='safe', [switch]$Host120, [ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile', [ValidateSet(0,60,120,240)][int]$MailboxFps=0, [switch]$Trace)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk=$env:GODOT_JFX_JDK
$savedMailbox=$env:GODOT_JFX_BENCHMARK_MAILBOX
$savedTrace=$env:GODOT_JFX_BENCHMARK_TRACE
$savedCommands=$env:GODOT_JFX_PROFILE_COMMANDS
$savedOptions=$env:JAVA_TOOL_OPTIONS
try {
    $backendName=if($Backend -eq 'd3d'){'Native JavaFX / Windows Glass / D3D (comparison only)'}else{"Godot DLL / Glass-Godot / Prism-Godot / $Renderer / $Backend"}
    Write-Output "VFX frame backend: $backendName"
    $exports=@('--add-exports=javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports=javafx.graphics/com.sun.glass.ui=ALL-UNNAMED')
    $env:GODOT_JFX_BENCHMARK_TRACE=if ($Trace) {'1'} else {'0'}
    if ($Trace) { $env:GODOT_JFX_PROFILE_COMMANDS='1' }
    if ($MailboxFps -and ($Host120 -or $Backend -eq 'd3d' -or $Renderer -ne 'mobile')) { throw 'Mailbox diagnostic requires Vulkan Godot and excludes Host120' }
    $env:GODOT_JFX_BENCHMARK_MAILBOX=if ($MailboxFps) { '1' } else { '0' }
    $classpath='artifacts/reference;artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls @exports -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxFrameBenchmark.java
    if ($LASTEXITCODE -ne 0) { throw 'Benchmark compilation failed' }
    $env:JAVA_TOOL_OPTIONS="$savedOptions $($exports -join ' ')"
    if ($Host120 -and $Backend -eq 'd3d') { throw 'Host120 is a Godot scheduling diagnostic only' }
    $suffix=if ($Host120) { '-host120' } else { '' }
    if ($MailboxFps) { $suffix += "-mailbox$MailboxFps" }
    if ($Backend -ne 'd3d' -and $Renderer -ne 'mobile') { $suffix += "-$Renderer" }
    if ($Trace) { $suffix += '-trace' }
    $log="agentdir/logs/vfx-frame-benchmark-$Backend$suffix.log"
    if ($Backend -eq 'd3d') {
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing --enable-native-access=javafx.graphics,ALL-UNNAMED '-Dprism.order=d3d' -cp $classpath VfxFrameBenchmark *> $log
    } else {
        $env:GODOT_JFX_JDK=$Jdk
        $hostArgs=if ($Host120) { @('--disable-vsync','--max-fps','120') } else { @() }
        if ($MailboxFps) { $hostArgs=@('--max-fps',"$MailboxFps") }
        Invoke-GodotFixture --path tests/godot res://vfx_frame_benchmark.tscn --rendering-method $Renderer --render-thread $Backend @hostArgs *> $log
    }
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if ($code -ne 0 -or $output -notmatch 'VFX_FRAME_BENCHMARK_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:') { throw "Benchmark failed ($code): $log" }
    if ($Backend -ne 'd3d' -and $output -notmatch 'GODOT_VFX_FRAME_BENCHMARK_PASS') { throw "Host benchmark incomplete: $log" }
    $expected=if($Backend -eq 'd3d'){'VFX_FRAME_BACKEND glass=com.sun.glass.ui.win.WinApplication prism=com.sun.prism.d3d.D3DPipeline'}else{'VFX_FRAME_BACKEND glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline'}
    if(!$output.Contains($expected)){throw "Unexpected Glass/Prism backend: $log"}
    if ($Trace -and ($output -notmatch '(?m)^VFX_FRAME_TRACE_JAVA ' -or ($Backend -ne 'd3d' -and ($output -notmatch '(?m)^VFX_FRAME_TRACE_HOST ' -or $output -notmatch '(?m)^VFX_FRAME_TRACE_PHASES ' -or $output -notmatch 'profile_geometry_us' -or $output -notmatch 'profile_render_offscreen_us')))) { throw "Frame trace or native command profile missing; rebuild the host: $log" }
    if ($MailboxFps -and ($output -match 'Falling back to V-Sync' -or $output -notmatch 'VFX_FRAME_MEASUREMENT_VSYNC 3')) { throw "Mailbox mode was not active during measurement: $log" }
    $output -split "`r?`n" | Where-Object { $_ -match '^VFX_FRAME_' -and $_ -notmatch '^VFX_FRAME_TRACE_' }
} finally { $env:JAVA_TOOL_OPTIONS=$savedOptions; $env:GODOT_JFX_JDK=$savedJdk; $env:GODOT_JFX_BENCHMARK_MAILBOX=$savedMailbox; $env:GODOT_JFX_BENCHMARK_TRACE=$savedTrace; $env:GODOT_JFX_PROFILE_COMMANDS=$savedCommands; Pop-Location }
