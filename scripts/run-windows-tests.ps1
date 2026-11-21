#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [ValidateSet('NonRobot', 'Robot')][string]$Group = 'NonRobot',
    [string]$ResultDirectory,
    [switch]$List,
    [ValidateSet('all','d3d12','vulkan','opengl')][string]$Driver = 'd3d12',
    [ValidateSet('All','Default','Variants')][string]$Cases = 'All',
    [string[]]$Test
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native-output.ps1"
$root = Split-Path $PSScriptRoot -Parent
$desktop = 'test-robot','test-native-ime','test-file-dialog','test-drag-drop-external','test-hover-demo','test-virtual-keyboard'
$optionalRobot = 'test-drag-drop','test-physical-drag','test-hover-flicker','test-vfx-table-scroll'
if ($Group -eq 'NonRobot') {
    $tests = Get-ChildItem -Path (Join-Path $PSScriptRoot 'test-*') -File | Where-Object {
        $_.Extension -in '.ps1','.cmd' -and $_.BaseName -notin $desktop
    } | Sort-Object @{Expression={ switch ($_.BaseName) { 'test-startup' {0} 'test-vfx-soak' {2} default {1} } }},Name
    $tests = @($tests) + @(foreach ($name in 'test-godot-library','test-shadow-jar','test-vfx-demo-jar') {
        Get-Item -LiteralPath "$PSScriptRoot/$name.py"
    })
} else {
    # The system can decline to dismiss TabTip. Run that desktop interaction last.
    $robotCases = @($desktop | Where-Object { $_ -ne 'test-virtual-keyboard' }) + $optionalRobot + 'test-virtual-keyboard'
    $tests = foreach ($name in $robotCases) { Get-Item -LiteralPath "$PSScriptRoot/$name.ps1" }
}
if ($Test) {
    foreach ($name in $Test) { if ($name -notin $tests.BaseName) { throw "Unknown test in $Group group: $name" } }
    $tests = @($tests | Where-Object BaseName -in $Test)
}

$drivers = if ($Driver -eq 'all') { 'd3d12','vulkan','opengl' } else { $Driver.ToLowerInvariant() }
$variants = @{
    'test-bridge' = '-Encoded','-StopFromHost','-Textures','-PrismTextures','-ShaderStates','-PrismContext'
    'test-drag-drop-ole-inject' = '-Timeout'
    'test-failure-shutdown' = '-Probe FailureApplicationProbe'
    'test-file-dialog' = '-StopHost'
    'test-godot-view' = '-Transform'
    'test-ime' = '-SpacedClick'
    'test-media-audio' = '-Codec mp3','-Codec aiff'
    'test-media-churn' = '-AudioOnly'
    'test-media-video' = '-Sample lk'
    'test-mesh-transform' = '-CachePressure'
    'test-native-churn' = '-Kind Idle','-Kind SubViewport','-Kind JavaFXNativeWindow'
    'test-pacing-cap' = '-Mode restore','-Mode override'
    'test-queued-texture-update' = '-BatchBoundary','-ViewportState'
    'test-readback' = '-Snapshot','-SnapshotStress','-StopDuringRead'
    'test-scene-textures' = '-Resize','-MissingScene'
    'test-vfx-animation' = '-TimingOnly'
    'test-vfx-dialog' = '-InjectFailure'
    'test-vfx-intro' = '-FreezeFusion -PageLimit 3'
    'test-vfx-loading' = '-Cancel'
    'test-vfx-stage' = '-Abrupt'
}
$plan = foreach ($entry in $tests) {
    $name = $entry.BaseName
    if ($name -eq 'test-render-mode-rejection') {
        if ('opengl' -notin $drivers) {
            if ($name -in $Test) { throw "$name requires -Driver opengl or all" }
        } elseif ($Cases -ne 'Variants') {
            [pscustomobject]@{Entry=$entry; Driver='opengl'; Variant=''; Arguments=@('-Driver','opengl')}
        }
        continue
    }
    $parameters = if ($entry.Extension -eq '.ps1') { (Get-Command $entry.FullName).Parameters }
    $hasDriver = $parameters -and $parameters.ContainsKey('Driver')
    $baseArgs = @()
    if ($name -in 'test-godot-library','test-shadow-jar') {
        $baseArgs = @('--runtime', (Join-Path $root 'artifacts/godot-library'))
    }
    if ($name -eq 'test-godot-library') {
        if ($Cases -ne 'Variants') {
            $lifecycleArgs = $baseArgs + @('--group','lifecycle')
            if ('opengl' -in $drivers) { $lifecycleArgs += '--driver','opengl' }
            elseif ('vulkan' -in $drivers) { $lifecycleArgs += '--driver','vulkan' }
            [pscustomobject]@{Entry=$entry; Driver=''; Variant=''; Arguments=$lifecycleArgs}
        }
        $baseArgs += '--group','render'
    }
    if ($Group -eq 'Robot' -and $name -in ($optionalRobot + 'test-hover-demo' + 'test-virtual-keyboard') -and $name -ne 'test-vfx-table-scroll') {
        $baseArgs += '-Robot'
    }
    if ($name -eq 'test-vfx-intro') { $baseArgs += '-AllPages' }
    if ($hasDriver -or $entry.Extension -eq '.py') {
        $modes = @()
        if ($Cases -ne 'Variants') { $modes += '' }
        if ($Cases -ne 'Default') {
            if ($variants.ContainsKey($name)) { $modes += $variants[$name] }
            if ($parameters -and $parameters.ContainsKey('Runtime')) { $modes += '-Runtime' }
        }
        foreach ($mode in $modes) {
            foreach ($backend in $drivers) {
                $arguments = $baseArgs
                if ($mode) { $arguments += $mode.Split(' ') }
                if ($entry.Extension -eq '.py') { $arguments += '--driver',$backend }
                if ($hasDriver) {
                    $arguments += '-Driver',$backend
                }
                [pscustomobject]@{Entry=$entry; Driver=$backend; Variant=$mode; Arguments=$arguments}
            }
        }
    } elseif ($Cases -ne 'Variants') {
        [pscustomobject]@{Entry=$entry; Driver=''; Variant=''; Arguments=$baseArgs}
    }
}
if ($List) {
    foreach ($case in $plan) { "$($case.Entry.BaseName) $($case.Driver) $($case.Arguments -join ' ')".TrimEnd() }
    return
}
if (!$ResultDirectory) { $ResultDirectory = Join-Path $root "agentdir/logs/windows-$Group-$(Get-Date -Format yyyyMMdd-HHmmss)" }
$ResultDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultDirectory)
New-Item -ItemType Directory -Force $ResultDirectory,(Join-Path $root 'artifacts/reference') | Out-Null
$results = @()
$previousDragMode = $env:GODOT_JFX_DRAG_MODE
try {
    foreach ($case in $plan) {
        $entry = $case.Entry
        $name = $entry.BaseName
        $arguments = $case.Arguments
        $env:GODOT_JFX_DRAG_MODE = if ($Group -eq 'Robot' -and $name -eq 'test-vfx-table-scroll') { 'robot' }
        $label = if ($case.Driver) { "$name-$($case.Driver)" } else { $name }
        if ($case.Variant) { $label += $case.Variant.Replace(' ','-').Replace('--','-') }
        $log = Join-Path $ResultDirectory "$label.log"
        $program = $entry.FullName
        if ($entry.Extension -eq '.py') {
            $program = 'python'
            $arguments = @($entry.FullName) + $arguments
        } elseif ($entry.Extension -eq '.ps1') {
            $program = Join-Path $PSHOME 'pwsh.exe'
            $arguments = @('-NoProfile', '-File', $entry.FullName) + $arguments
        }
        $start = [datetime]::UtcNow
        Invoke-NativeOutput $program @arguments | Out-File -Encoding utf8 -LiteralPath $log
        $code = $LASTEXITCODE
        if ($case.Driver -and $entry.Extension -eq '.ps1') {
            # Fixtures reuse output names. Preserve each pass before the next driver writes them.
            $evidence = Join-Path $ResultDirectory $label
            $caseLogs = @()
            foreach ($directory in 'agentdir/logs','artifacts/reference') {
                $base = Join-Path $root $directory
                $items = if ($directory -eq 'agentdir/logs') { Get-ChildItem $base -File }
                         else { Get-ChildItem $base -File -Recurse -Include '*.png','*.json','*.csv' }
                foreach ($item in $items) {
                    if ($item.LastWriteTimeUtc -lt $start) { continue }
                    $dest = Join-Path $evidence ([IO.Path]::Combine($directory,[IO.Path]::GetRelativePath($base,$item.FullName)))
                    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
                    Copy-Item -LiteralPath $item.FullName -Destination $dest
                    if ($directory -eq 'agentdir/logs' -and $item.Extension -eq '.log' -and $item.FullName -ne $log) {
                        $caseLogs += $dest
                    }
                }
            }
            Invoke-NativeOutput python "$PSScriptRoot/godot_driver.py" --driver $case.Driver --case-logs @caseLogs |
                Add-Content -LiteralPath $log
            if ($LASTEXITCODE) { $code = 1 }
        }
        $results += [pscustomobject]@{Test=$name;Group=$Group;Driver=$case.Driver;Arguments=$case.Arguments -join ' ';Exit=$code;Seconds=[math]::Round(([datetime]::UtcNow-$start).TotalSeconds,1);Log=$log}
        $results | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $ResultDirectory 'results.csv')
        Write-Output "$label ($code) $log"
    }
} finally {
    $env:GODOT_JFX_DRAG_MODE = $previousDragMode
}
if ($results.Where({$_.Exit -ne 0})) { exit 1 }
