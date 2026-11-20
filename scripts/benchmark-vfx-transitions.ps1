#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME, [ValidateSet('safe')][string]$Backend='safe', [ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk=$env:GODOT_JFX_JDK
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    Write-Output "VFX transition backend: Godot DLL / Glass-Godot / Prism-Godot / $Renderer / $Backend"
    $exports=@('--add-exports=javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports=javafx.graphics/com.sun.glass.ui=ALL-UNNAMED')
    $classpath='artifacts/reference;artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls @exports -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/ThreadStackSampler.java tests/reference/VfxTransitionProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Transition probe compilation failed' }
    $env:GODOT_JFX_JDK=$Jdk
    $log="agentdir/logs/vfx-transition-$Renderer-$Backend.log"
    Invoke-GodotFixture --path tests/godot res://vfx_transition.tscn --rendering-method $Renderer --render-thread $Backend *> $log
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if ($code -ne 0 -or $output -notmatch 'VFX_TRANSITION_BENCHMARK_PASS' -or $output -notmatch 'GODOT_VFX_TRANSITION_PASS' -or $output -notmatch 'VFX_TRANSITION_RESOURCE_CLEANUP_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:') { throw "Transition benchmark failed ($code): $log" }
    $expected='VFX_TRANSITION_BACKEND glass=com.sun.glass.ui.godot.GodotApplication prism=com.sun.prism.godot.GODOTPipeline'
    if(!$output.Contains($expected)){throw "Unexpected Glass/Prism backend: $log"}
    if($output -notmatch '(?m)^VFX_TRANSITION_TARGET_SWITCHES ([0-9]+)\r?$' -or [long]$Matches[1] -le 0){throw "Missing or empty Prism target-switch diagnostic: $log"}
    $output -split "`r?`n" | Where-Object { $_ -match '^VFX_TRANSITION_' }
} finally { $env:GODOT_JFX_JDK=$savedJdk; Pop-Location }
