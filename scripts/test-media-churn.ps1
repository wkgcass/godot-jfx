#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',[switch]$Runtime,[ValidateRange(24,240)][int]$Cycles=24,[switch]$NativeD3D,[ValidateSet(0,30,60)][int]$SettleSeconds=0,[switch]$HandleTypes,[switch]$AudioOnly,[switch]$Providers)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$savedJdk=$env:JAVA_HOME
$savedMedia=$env:GODOT_JFX_MEDIA_FILE
$savedOptions=$env:JAVA_TOOL_OPTIONS
$savedCycles=$env:GODOT_JFX_MEDIA_CYCLES
$savedSettle=$env:GODOT_JFX_MEDIA_SETTLE
$savedHandles=$env:GODOT_JFX_MEDIA_HANDLES
$savedAudioOnly=$env:GODOT_JFX_MEDIA_AUDIO_ONLY
$savedProviders=$env:GODOT_JFX_MEDIA_PROVIDERS
Push-Location $root
try {
    if ($NativeD3D -and $PSBoundParameters.ContainsKey('Driver')) { throw 'Driver selects Godot. Omit it for the native JavaFX comparison.' }
    if($Providers){$HandleTypes=$true}
    if($NativeD3D -and $Runtime){throw 'Choose native D3D or Godot Runtime'}
    $backend=if($NativeD3D){'Native JavaFX / Windows Glass / D3D (comparison only)'}elseif($Runtime){"Godot DLL (isolated project) / Glass-Godot / Prism-Godot / $Driver"}else{"Godot DLL / Glass-Godot / Prism-Godot / $Driver"}
    Write-Output "Media churn backend: $backend"
    if($AudioOnly){
        $relative = & python "$PSScriptRoot/prepare-audio-fixtures.py" churn
        if ($LASTEXITCODE) { throw 'PCM fixture preparation failed' }
    }else{
        $relative = & python "$PSScriptRoot/setup-env.py" --sample-path oracle
        if ($LASTEXITCODE) { throw "Invalid Oracle playback sample" }
    }
    $videoFile = Join-Path $root $relative
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media -d artifacts/reference tests/reference/CurrentProcessHandles.java tests/reference/CurrentProcessMemory.java tests/reference/MediaChurnProbe.java
    if($LASTEXITCODE -ne 0){throw 'Media churn compilation failed'}
    $env:JAVA_HOME=$Jdk
    $env:GODOT_JFX_MEDIA_FILE=$videoFile
    $env:JAVA_TOOL_OPTIONS="$savedOptions -Xmx256m --enable-native-access=ALL-UNNAMED"
    $env:GODOT_JFX_MEDIA_CYCLES="$Cycles"
    $env:GODOT_JFX_MEDIA_SETTLE="$SettleSeconds"
    $env:GODOT_JFX_MEDIA_PROVIDERS=if($Providers){'1'}else{'0'}
    $env:GODOT_JFX_MEDIA_HANDLES=if($HandleTypes){'1'}else{'0'}
    $env:GODOT_JFX_MEDIA_AUDIO_ONLY=if($AudioOnly){'1'}else{'0'}
    Write-Output ('Media churn fixture: '+$(if($AudioOnly){'PCM audio only'}else{'MP4 audio/video'}))
    $suffix=if($NativeD3D){'-d3d'}elseif($Runtime){'-runtime'}else{''}
    if($AudioOnly){$suffix+='-pcm'}
    $suffix+="-cycles$Cycles-process"
    if($SettleSeconds){$suffix+="-idle$SettleSeconds"}
    if($HandleTypes){$suffix+='-types'}
    if($Providers){$suffix+='-providers'}
    $log=Join-Path $root "agentdir/logs/media-churn-$Driver$suffix.log"
    # The Godot fixture owns its timeout and normal shutdown. No process manipulation.
    if($NativeD3D){
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.media --enable-native-access=javafx.graphics,javafx.media,ALL-UNNAMED '-Dprism.order=d3d' -cp artifacts/reference MediaChurnProbe *> $log
    }elseif($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-media-churn'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/media_churn.gd'),(Join-Path $root 'tests/godot/media_churn.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://media_churn.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "Media churn runtime import failed: $log.import"}
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread safe *> $log }
        finally {Pop-Location}
    }else{
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://media_churn.tscn --render-thread safe *> $log
    }
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    $native=@([regex]::Matches($output,'(?m)^MEDIA_CHURN_SAMPLE (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json})
    $java=@([regex]::Matches($output,'MEDIA_CHURN_JAVA cycle=(\d+) heap_used=(\d+) gc_count=(\d+)') | ForEach-Object {@{cycle=[int]$_.Groups[1].Value;heap_used=[long]$_.Groups[2].Value;gc_count=[long]$_.Groups[3].Value}})
    $samplePattern='cycle=(\d+) pid=(\d+) private_bytes=(\d+) working_set=(\d+) handles=(\d+) elapsed_ms=(\d+) java_threads=(\d+)'
    $convertSample={@{cycle=[int]$_.Groups[1].Value;pid=[long]$_.Groups[2].Value;private_bytes=[long]$_.Groups[3].Value;working_set=[long]$_.Groups[4].Value;handles=[long]$_.Groups[5].Value;elapsed_ms=[long]$_.Groups[6].Value;java_threads=[int]$_.Groups[7].Value}}
    $processSamples=@([regex]::Matches($output,"MEDIA_CHURN_PROCESS $samplePattern") | ForEach-Object $convertSample)
    $idleSamples=@([regex]::Matches($output,"MEDIA_CHURN_IDLE $samplePattern") | ForEach-Object $convertSample)
    $passed=$code -eq 0 -and $output -match 'MEDIA_CHURN_PROBE_PASS' -and ($NativeD3D -or ($output -match 'GODOT_MEDIA_CHURN_PASS' -and $native.Count -eq $Cycles)) -and $java.Count -eq $Cycles -and $processSamples.Count -eq $Cycles -and $idleSamples.Count -eq (1+$SettleSeconds/10) -and $output -notmatch '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|OutOfMemoryError|uncaught:'
    $aacStable=$null
    if($passed -and $Providers){
        & python (Join-Path $PSScriptRoot 'analyze-media-handles.py') $log --require-stable-aac > "$log.aac-check"
        $aacStable=$LASTEXITCODE -eq 0
    }
    $staticAvailable=@($native | Where-Object {$_.static_bytes -gt 0}).Count -gt 0
    @{aac_registration_stable=$aacStable;providers=[bool]$Providers;audio_only=[bool]$AudioOnly;handle_types=[bool]$HandleTypes;playback_and_cleanup_passed=$passed;resource_growth_acceptance='requires separate trend analysis';cycles=$Cycles;runtime=[bool]$Runtime;native_d3d=[bool]$NativeD3D;driver=$Driver;settle_seconds=$SettleSeconds;idle_samples=$idleSamples;forced_gc=$false;heap_limit_mib=256;process_memory_sampled=$true;process_samples=$processSamples;static_memory_available=$staticAvailable;native_samples=$native;java_samples=$java} | ConvertTo-Json -Depth 6 | Set-Content "artifacts/reference/media-churn-$Driver$suffix.json"
    if(!$passed){throw "Media churn failed: $log"}
    if($aacStable -eq $false){throw "Media churn retained AAC decoder registrations: $log.aac-check"}
    Write-Output "Media churn passed: $log"
}finally{
    $env:JAVA_HOME=$savedJdk
    $env:GODOT_JFX_MEDIA_FILE=$savedMedia
    $env:JAVA_TOOL_OPTIONS=$savedOptions
    $env:GODOT_JFX_MEDIA_CYCLES=$savedCycles
    $env:GODOT_JFX_MEDIA_SETTLE=$savedSettle
    $env:GODOT_JFX_MEDIA_HANDLES=$savedHandles
    $env:GODOT_JFX_MEDIA_AUDIO_ONLY=$savedAudioOnly
    $env:GODOT_JFX_MEDIA_PROVIDERS=$savedProviders
    Pop-Location
}
