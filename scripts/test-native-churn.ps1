[CmdletBinding()]
param([ValidateSet('Idle','SubViewport','Window','JavaFXNativeWindow')][string]$Kind='Window',
      [ValidateSet('gl_compatibility','mobile')][string]$Renderer='gl_compatibility',
      [ValidateSet('safe')][string]$RenderThread='safe',
      [ValidateRange(-1,2147483647)][long]$StaticRangeLimitBytes=-1)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$savedKind=$env:GODOT_JFX_NATIVE_CHURN_KIND
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $env:GODOT_JFX_NATIVE_CHURN_KIND=$Kind
    $log="artifacts/logs/native-churn-$Kind-$Renderer-$RenderThread.log"
    Invoke-GodotFixture --path tests/godot res://native_churn.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 12000 *> $log
    $result=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'NATIVE_CHURN_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') { throw "Native churn failed: $log" }
    $samples=@(Get-Content $log | Where-Object { $_.StartsWith('NATIVE_CHURN_SAMPLE ') } | ForEach-Object { $_.Substring('NATIVE_CHURN_SAMPLE '.Length) | ConvertFrom-Json })
    if ($samples.Count -ne 181) { throw 'Incomplete native churn samples' }
    $samples | ConvertTo-Json | Set-Content "artifacts/reference/native-churn-$Kind-$Renderer-$RenderThread.json"
    if ($StaticRangeLimitBytes -ge 0) {
        $range=$samples | Where-Object cycle -ge 20 | Measure-Object static_bytes -Minimum -Maximum
        if ($range.Maximum-$range.Minimum -gt $StaticRangeLimitBytes) { throw "Native static-memory range exceeds $StaticRangeLimitBytes bytes: $log" }
    }
    Write-Output "Native churn passed: $log"
    $samples[6];$samples[-1]
} finally {
    $env:GODOT_JFX_NATIVE_CHURN_KIND=$savedKind
    Pop-Location
}
