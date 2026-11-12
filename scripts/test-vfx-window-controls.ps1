[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe','separate')][string]$RenderThread = 'separate', [switch]$Runtime)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxWindowControlsProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX controls probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path (Get-Location) "artifacts/logs/vfx-window-controls-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-vfx-window-controls'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'godot/bin/godot.windows.template_release.x86_64.console.exe', 'godot/bin/godot.windows.template_release.x86_64.exe', 'tests/godot/vfx_window_controls.gd', 'tests/godot/vfx_window_controls.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://vfx_window_controls.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "VFX controls runtime import failed: $log.import" }
        Push-Location $fixture
        try { & .\godot.windows.template_release.x86_64.console.exe --rendering-method $Renderer --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_window_controls.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_VFX_WINDOW_CONTROLS_PASS' -or $output -notmatch 'VFX_WINDOW_CONTROLS_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "VFX controls failed: $log" }
    foreach ($step in 0,1,2,4) { Copy-Item "artifacts/reference/vfx-window-controls-$step.png" "artifacts/reference/vfx-window-controls-$Renderer-$RenderThread$suffix-$step.png" }
    Write-Output "VFX controls passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
