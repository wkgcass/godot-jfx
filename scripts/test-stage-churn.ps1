[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('gl_compatibility','mobile')][string]$Renderer='mobile',[ValidateSet('safe')][string]$RenderThread='safe',[ValidateRange(6,1000)][int]$Cycles=36,[ValidateRange(0,4096)][int]$HeapMiB=0)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk=$env:GODOT_JFX_JDK
$savedCycles=$env:GODOT_JFX_CHURN_CYCLES
$savedOptions=$env:JAVA_TOOL_OPTIONS
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED -d artifacts/reference tests/reference/StageChurnProbe.java
    if($LASTEXITCODE -ne 0) {throw 'Stage churn probe compilation failed'}
    $env:GODOT_JFX_JDK=$Jdk
    $env:GODOT_JFX_CHURN_CYCLES="$Cycles"
    if($HeapMiB -gt 0) {$env:JAVA_TOOL_OPTIONS="$savedOptions -Xmx${HeapMiB}m"}
    $suffix="-$Cycles-heap$HeapMiB"
    $log="artifacts/logs/stage-churn-$Renderer-$RenderThread$suffix.log"
    Invoke-GodotFixture --path tests/godot res://stage_churn.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    $output=Get-Content $log -Raw
    if($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_STAGE_CHURN_PASS' -or $output -notmatch 'STAGE_CHURN_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') {throw "Stage churn failed: $log"}
    $javaSamples=@([regex]::Matches($output,'STAGE_CHURN_JAVA cycle=(\d+) heap_used=(\d+) gc_count=(\d+) collected_stages=(\d+)') | ForEach-Object {
        @{cycle=[int]$_.Groups[1].Value;heap_used=[long]$_.Groups[2].Value;gc_count=[long]$_.Groups[3].Value;collected_stages=[int]$_.Groups[4].Value}
    })
    if($javaSamples.Count -ne $Cycles) {throw 'Stage churn Java sample count differs'}
    $report=Get-Content artifacts/reference/stage-churn.json -Raw | ConvertFrom-Json
    $nativeSamples=@([regex]::Matches($output,'(?m)^STAGE_CHURN_RESOURCES (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json})
    if($nativeSamples.Count -ne $Cycles+1) {throw 'Stage churn native sample count differs'}
    $report | Add-Member -NotePropertyMembers @{samples=$nativeSamples; java_samples=$javaSamples; heap_limit_mib=$HeapMiB} -Force
    $report | ConvertTo-Json -Depth 8 | Set-Content "artifacts/reference/stage-churn-$Renderer-$RenderThread$suffix.json"
    Write-Output "Stage churn passed: $log"
} finally {$env:GODOT_JFX_JDK=$savedJdk;$env:GODOT_JFX_CHURN_CYCLES=$savedCycles;$env:JAVA_TOOL_OPTIONS=$savedOptions;Pop-Location}
