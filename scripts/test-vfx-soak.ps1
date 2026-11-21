#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,
    [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',
    [ValidateRange(1,20)][int]$Rounds=3,
    [ValidateRange(128,4096)][int]$HeapMiB=256)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$names=@('GODOT_JFX_JDK','GODOT_JFX_VFX_PAGES','GODOT_JFX_VFX_ROUNDS','GODOT_JFX_VFX_SOAK','GODOT_JFX_VFX_FREEZE','JAVA_TOOL_OPTIONS')
$saved=@{};foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$process=$null
Push-Location $root
try {
    $classpath='artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxNavigationProbe.java
    if($LASTEXITCODE -ne 0){throw 'VFX observer compilation failed'}
    $pages=(Select-String -Path vfx/src/test/java/io/vproxy/vfx/intro/IntroFXMain.java -Pattern 'mainScenes.add\(new').Count
    $env:GODOT_JFX_JDK=$Jdk;$env:GODOT_JFX_VFX_PAGES="$pages";$env:GODOT_JFX_VFX_ROUNDS="$Rounds"
    $env:GODOT_JFX_VFX_SOAK='1';$env:GODOT_JFX_VFX_FREEZE='0'
    $env:JAVA_TOOL_OPTIONS="$($saved['JAVA_TOOL_OPTIONS']) -Xmx${HeapMiB}m"
    $stem="vfx-soak-$Driver-$Rounds-heap$HeapMiB"
    $log=Join-Path $root "agentdir/logs/$stem.log"
    $err=Join-Path $root "agentdir/logs/$stem.stderr.log"
    # Sample the Java process that has loaded the engine DLL.
    $engine=Join-Path $Jdk 'bin/java.exe'
    $process=Start-GodotFixture -Driver $Driver -ArgumentList @('--path','tests/godot','res://vfx_soak.tscn','--render-thread','safe') -WorkingDirectory $root -Log $log -ErrorLog $err
    $samples=[Collections.Generic.List[object]]::new()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(!$process.WaitForExit(1000)) {
        $process.Refresh()
        $samples.Add(@{elapsed_ms=$watch.ElapsedMilliseconds;private_bytes=$process.PrivateMemorySize64;working_set=$process.WorkingSet64;handles=$process.HandleCount})
        if($watch.Elapsed.TotalSeconds -gt (120+$Rounds*$pages*8)){throw 'VFX soak process timeout'}
    }
    $process.WaitForExit()
    $output=[IO.File]::ReadAllText($log)+[IO.File]::ReadAllText($err)
    $native=@([regex]::Matches($output,'(?m)^VFX_SOAK_SAMPLE (\{[^\r\n]+\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json})
    $java=@([regex]::Matches($output,'VFX_SOAK_JAVA page=(\d+) heap_used=(\d+) gc_count=(\d+)') | ForEach-Object {@{page=[int]$_.Groups[1].Value;heap_used=[long]$_.Groups[2].Value;gc_count=[long]$_.Groups[3].Value}})
    $expected=1+$Rounds*2*($pages-1)
    $passed=$process.ExitCode -eq 0 -and $output -match 'VFX_SOAK_PASS' -and $native.Count -eq $expected -and $java.Count -eq $expected -and $output -notmatch '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|OutOfMemoryError|uncaught:'
    $report=@{navigation_and_cleanup_passed=$passed;memory_acceptance='requires trend analysis';sampled_process_id=$process.Id;sampled_executable=$engine;rounds=$Rounds;pages=$pages;forced_gc=$false;heap_limit_mib=$HeapMiB;process_samples=$samples.ToArray();native_samples=$native;java_samples=$java}
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root "artifacts/reference/$stem.json")
    if(!$passed){throw "VFX soak failed: $log / $err"}
    Write-Output "VFX soak navigation/cleanup passed; memory observations: artifacts/reference/$stem.json"
} finally {
    if($null -ne $process -and !$process.HasExited){$process.Kill();$process.WaitForExit()}
    if($null -ne $process){$process.Dispose()}
    foreach($name in $names){if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }}
    Pop-Location
}
