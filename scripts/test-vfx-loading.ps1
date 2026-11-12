[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime, [switch]$Cancel)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
$savedCancel = $env:GODOT_JFX_LOADING_CANCEL
try {
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxLoadingProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX loading probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_LOADING_CANCEL = if ($Cancel) { '1' } else { '0' }
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    if ($Cancel) { $suffix += '-cancel' }
    $log = Join-Path (Get-Location) "artifacts/logs/vfx-loading-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-vfx-loading'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'godot/bin/godot.windows.template_release.x86_64.console.exe', 'godot/bin/godot.windows.template_release.x86_64.exe', 'tests/godot/vfx_loading.gd', 'tests/godot/vfx_loading.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://vfx_loading.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "VFX loading runtime import failed: $log.import" }
        Push-Location $fixture
        try { & .\godot.windows.template_release.x86_64.console.exe --rendering-method $Renderer --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_loading.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_VFX_LOADING_PASS' -or $output -notmatch 'VFX_LOADING_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "VFX loading failed: $log" }
    foreach ($step in 0..2) { Copy-Item "artifacts/reference/vfx-loading-$step.png" "artifacts/reference/vfx-loading-$Renderer-$RenderThread$suffix-$step.png" }
    Write-Output "VFX loading passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_LOADING_CANCEL = $savedCancel; Pop-Location }
