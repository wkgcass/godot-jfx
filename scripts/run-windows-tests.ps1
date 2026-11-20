#Requires -Version 7.4.1
[CmdletBinding()]
param(
    [ValidateSet('NonRobot', 'Robot')][string]$Group = 'NonRobot',
    [string]$ResultDirectory,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/native-output.ps1"
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
if ($List) { $tests.BaseName; return }
if (!$ResultDirectory) { $ResultDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) "agentdir/logs/windows-$Group-$(Get-Date -Format yyyyMMdd-HHmmss)" }
$ResultDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultDirectory)
New-Item -ItemType Directory -Force -Path $ResultDirectory | Out-Null
$results = @()
$previousDragMode = $env:GODOT_JFX_DRAG_MODE
try {
    foreach ($test in $tests) {
        $name = $test.BaseName
        $arguments = @()
        $env:GODOT_JFX_DRAG_MODE = $null
        if ($Group -eq 'Robot') {
            if ($name -eq 'test-vfx-table-scroll') { $env:GODOT_JFX_DRAG_MODE = 'robot' }
            elseif ($name -in ($optionalRobot + 'test-hover-demo' + 'test-virtual-keyboard')) { $arguments = @('-Robot') }
        }
        $log = Join-Path $ResultDirectory "$name.log"
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $program = $test.FullName
        if ($test.Extension -eq '.py') {
            if ($name -ne 'test-vfx-demo-jar') {
                $arguments = @('--runtime', (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/godot-library'))
            }
            $program = 'python'
            $arguments = @($test.FullName) + $arguments
        } elseif ($test.Extension -eq '.ps1') {
            $program = Join-Path $PSHOME 'pwsh.exe'
            $arguments = @('-NoProfile', '-File', $test.FullName) + $arguments
        }
        Invoke-NativeOutput $program @arguments | Out-File -Encoding utf8 -LiteralPath $log
        $code = $LASTEXITCODE
        $results += [pscustomobject]@{Test=$name;Group=$Group;Exit=$code;Seconds=[math]::Round($timer.Elapsed.TotalSeconds,1)}
        $results | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $ResultDirectory 'results.csv')
        Write-Output "$name ($code) $log"
    }
} finally {
    $env:GODOT_JFX_DRAG_MODE = $previousDragMode
}
if ($results.Where({$_.Exit -ne 0})) { exit 1 }
