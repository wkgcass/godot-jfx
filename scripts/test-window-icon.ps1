[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',[ValidateSet('safe')][string]$RenderThread='safe',[switch]$Runtime)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
$savedJdk=$env:GODOT_JFX_JDK
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/WindowIconProbe.java
    if($LASTEXITCODE -ne 0){throw 'Icon probe compilation failed'}
    $env:GODOT_JFX_JDK=$Jdk
    $suffix=if($Runtime){'-runtime'}else{''}
    $log=Join-Path $root "artifacts/logs/window-icon-$Renderer-$RenderThread$suffix.log"
    if($Runtime){
        $fixture=Join-Path $root 'artifacts/runtime-window-icon'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.console.exe'),(Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.exe'),(Join-Path $root 'tests/godot/window_icon.gd'),(Join-Path $root 'tests/godot/window_icon.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://window_icon.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0){throw "Icon runtime import failed: $log.import"}
        Push-Location $fixture
        try { & (Join-Path $fixture 'godot.windows.template_release.x86_64.console.exe') --rendering-method $Renderer --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    }else{
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://window_icon.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'WINDOW_ICON_PROBE_PASS' -or $output -notmatch 'GODOT_WINDOW_ICON_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "Window icon failed: $log"}
    Write-Output "Window icon passed: $log"
} finally {$env:GODOT_JFX_JDK=$savedJdk;Pop-Location}
