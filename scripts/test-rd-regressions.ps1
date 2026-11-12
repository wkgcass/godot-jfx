[CmdletBinding()]
param([ValidateSet('safe','separate')][string]$RenderThread='safe', [switch]$NoRing, [switch]$NoBatch, [switch]$Runtime)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$names=@('GODOT_JFX_RD_DIRECT','GODOT_JFX_RD_RING','GODOT_JFX_RD_BATCH')
$saved=@{}
foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location $root
try {
    $env:GODOT_JFX_RD_DIRECT='1'
    $env:GODOT_JFX_RD_RING=if($NoRing){'0'}else{'1'}
    $env:GODOT_JFX_RD_BATCH=if($NoBatch){'0'}else{'1'}
    $suffix=$(if($NoRing){'-no-ring'}else{''})+$(if($NoBatch){'-no-batch'}else{''})+$(if($Runtime){'-runtime'}else{''})
    $log="artifacts/logs/rd-regressions-$RenderThread$suffix.log"
    if($Runtime){
        # Release templates intentionally disallow --path. Use an isolated
        # project beside the source-built executable, like other runtime probes.
        $fixture=Join-Path $root 'artifacts/runtime-rd-regressions'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath godot/bin/godot.windows.template_release.x86_64.exe,godot/bin/godot.windows.template_release.x86_64.console.exe,tests/godot/rd_regressions.gd,tests/godot/rd_regressions.tscn -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://rd_regressions.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        $log=Join-Path $root $log
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "Runtime fixture import failed: $log.import"}
        Push-Location $fixture
        try {
            & ./godot.windows.template_release.x86_64.console.exe --rendering-method mobile --render-thread $RenderThread --quit-after 120 *> $log
            $code=$LASTEXITCODE
        } finally { Pop-Location }
    }else{
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://rd_regressions.tscn --rendering-method mobile --render-thread $RenderThread --quit-after 120 *> $log
        $code=$LASTEXITCODE
    }
    $output=Get-Content -LiteralPath $log -Raw
    if($code -ne 0 -or $output -notmatch 'RD_REGRESSIONS_PASS' -or $output -notmatch 'RD_UNIFORM_RETIREMENT_PASS' -or $output -notmatch 'RD_PIPELINE_EVICTION_PASS' -or $output -notmatch 'RD_SCREEN_SNAPSHOT_PASS' -or $output -notmatch 'RD_PIXEL_COORDINATES_PASS' -or $output -notmatch 'RD_READBACK_OWNERSHIP_PASS' -or $output -notmatch 'RD_VERTEX_INPUT_OWNERSHIP_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)') {throw "RD regressions failed: $log"}
    if($env:GODOT_JFX_RD_PROFILE -eq "1" -and [regex]::Matches($output,"(?m)^RD_PROFILE draws=").Count -ne 1) {throw "Expected exactly one scene-level RD profile summary: $log"}
    Write-Output "RD regressions passed: $log"
} finally {
    foreach($name in $names){if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }}
    Pop-Location
}
