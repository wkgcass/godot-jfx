[CmdletBinding()]
param([ValidateSet('safe','separate')][string]$RenderThread='safe', [switch]$Runtime)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/logs | Out-Null
    $suffix=if($Runtime){'-runtime'}else{''}
    $log=Join-Path $root "artifacts/logs/rd-lcd-$RenderThread$suffix.log"
    if($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-rd-lcd'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath godot/bin/godot.windows.template_release.x86_64.exe,godot/bin/godot.windows.template_release.x86_64.console.exe,tests/godot/rd_lcd_spike.gd,tests/godot/rd_lcd_spike.tscn -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://rd_lcd_spike.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "RD LCD Runtime import failed: $log.import"}
        Push-Location $fixture
        try {
            & ./godot.windows.template_release.x86_64.console.exe --rendering-method mobile --render-thread $RenderThread --quit-after 3000 *> $log
            $code=$LASTEXITCODE
        } finally { Pop-Location }
    }else{
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://rd_lcd_spike.tscn --rendering-method mobile --render-thread $RenderThread --quit-after 3000 *> $log
        $code=$LASTEXITCODE
    }
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'RD_LCD_SPIKE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:)'){throw "RD LCD probe failed: $log"}
    Write-Output "RD LCD probe passed: $log"
} finally { Pop-Location }
