[CmdletBinding()]
param([switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $target = if ($Runtime) { 'template_release' } else { 'editor' }
    $projectPath = Join-Path $root 'tests/godot'
    if ($Runtime) {
        $projectPath = Join-Path $root 'artifacts/runtime-thread-shutdown'
        New-Item -ItemType Directory -Force $projectPath | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/render_thread_shutdown.tscn') -Destination $projectPath -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://render_thread_shutdown.tscn')
        [IO.File]::WriteAllText((Join-Path $projectPath 'project.godot'), $project)
        $importLog = Join-Path $root 'artifacts/logs/render-thread-shutdown-import.log'
        & "$root/godot/bin/godot.windows.editor.x86_64.console.exe" --headless --path $projectPath --editor --import *> $importLog
        if ($LASTEXITCODE -ne 0) { throw "Shutdown fixture import failed: $importLog" }
    }
    foreach ($threadMode in @('safe')) {
        $log = Join-Path $root "artifacts/logs/render-thread-shutdown-$target-$threadMode.log"
        $pathArgs = if ($Runtime) { @() } else { @('--path', $projectPath, 'res://render_thread_shutdown.tscn') }
        Push-Location $projectPath
        try { Invoke-GodotFixture @pathArgs --rendering-method mobile --render-thread $threadMode --quit-after 3 *> $log }
        finally { Pop-Location }
        $exitCode = $LASTEXITCODE
        $output = Get-Content $log -Raw
        if ($exitCode -ne 0 -or $output -notmatch 'Vulkan' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:)|leaked at exit') {
            throw "Render thread shutdown failed: $log"
        }
        Write-Output "Render thread shutdown passed: $target / $threadMode"
    }
} finally { Pop-Location }
