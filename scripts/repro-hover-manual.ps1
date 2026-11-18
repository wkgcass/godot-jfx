[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('mobile','gl_compatibility')][string]$Renderer = 'mobile', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$NoSample, [string]$LogPath)
# Manual hover-freeze capture: starts the VFX demo with HOVER_TAP (Java event
# faucet + FX_GAP/FX_TASK stall probes) and HOVER_SAMPLE (per-frame luma under
# the cursor). The user reproduces the defect by hand and closes the window;
# this script then prints diagnostic timings and constant-luma sample runs.
# -LogPath analyzes an existing log without starting the demo or changing settings.
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$existingLog = if ($LogPath) { (Resolve-Path -LiteralPath $LogPath).Path } else { $null }
Push-Location $root
$saved = @{}
$settings = @{
    GODOT_JFX_JDK = $Jdk
    GODOT_JFX_DEMO_SMOKE = '0'
    GODOT_JFX_HOVER_TAP = '1'
    GODOT_JFX_HOVER_SAMPLE = $(if ($NoSample) { '0' } else { '1' })
}
try {
    $code = $null
    if ($existingLog) {
        $log = $existingLog
    } else {
        foreach ($key in $settings.Keys) {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
        }
        New-Item -ItemType Directory -Force artifacts/logs | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $log = Join-Path $root "artifacts/logs/hover-manual-$stamp.log"
        Write-Output "Starting the VFX demo with hover instrumentation. Close its window when done. Log: $log"
        Invoke-GodotFixture --path tests/godot res://vfx_demo.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
        $code = $LASTEXITCODE
    }
    $output = Get-Content -LiteralPath $log -Raw
    $gap = [regex]::Matches($output, 'HOVER_TAP t=[0-9.]+ms FX_GAP take=\d+ms queued=\d+')
    $task = [regex]::Matches($output, 'HOVER_TAP t=[0-9.]+ms FX_TASK run=\d+ms.*')
    $hostGap = [regex]::Matches($output, 'HOVER_TAP t=[0-9.]+ms HOST_GAP.*')
    $hostPhase = [regex]::Matches($output, 'HOVER_TAP t_abs=[0-9.]+ms HOST_PHASE.*')
    Write-Output "== HOST_GAP (host main loop stalled) hits: $($hostGap.Count)"
    foreach ($m in $hostGap | Select-Object -First 30) { Write-Output "  $($m.Value)" }
    Write-Output "== HOST_PHASE (engine render phase >100ms) hits: $($hostPhase.Count)"
    foreach ($m in $hostPhase | Select-Object -First 30) { Write-Output "  $($m.Value)" }
    Write-Output "== FX_GAP (time waiting for queued work; may include normal idle) hits: $($gap.Count)"
    foreach ($m in $gap | Select-Object -First 30) { Write-Output "  $($m.Value)" }
    Write-Output "== FX_TASK (long task execution on the FX thread) hits: $($task.Count)"
    foreach ($m in $task | Select-Object -First 20) { Write-Output "  $($m.Value)" }
    $samples = [regex]::Matches($output, 'HOVER_SAMPLE f=(\d+) luma=([0-9.]+)')
    $runs = [System.Collections.Generic.List[string]]::new()
    $runStart = -1; $runValue = 0.0; $prevF = 0; $prevV = -1.0
    foreach ($s in $samples) {
        $f = [long]$s.Groups[1].Value; $v = [double]$s.Groups[2].Value
        if ($v -eq $prevV -and $f -eq $prevF + 2) {
            if ($runStart -lt 0) { $runStart = $prevF; $runValue = $v }
        } else {
            if ($f -eq $prevF + 2 -and $runStart -ge 0 -and $prevF - $runStart -ge 24 -and [math]::Abs($v - $runValue) -ge 0.03) {
                $runs.Add("f=$runStart..$prevF luma=$runValue -> jump $v (frame span=$($prevF - $runStart); elapsed time unavailable)")
            }
            $runStart = -1
        }
        $prevF = $f; $prevV = $v
    }
    Write-Output "== Constant-luma sample runs (>=24 frame span then a consecutive jump): $($runs.Count)"
    Write-Output "Static content can produce these runs; this is not proof of a freeze or an FPS measurement."
    foreach ($fz in $runs | Select-Object -First 20) { Write-Output "  $fz" }
    if ($null -eq $code) { Write-Output "Existing log; native exit code unavailable. Log: $log" }
    else { Write-Output "native exit $code. Log: $log" }
    if (($null -ne $code -and $code -ne 0) -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') {
        throw "Hover diagnostic run failed or contains errors. See $log"
    }
} finally {
    foreach ($key in $saved.Keys) { if ($null -eq $saved[$key]) { Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') } }
    Pop-Location
}
