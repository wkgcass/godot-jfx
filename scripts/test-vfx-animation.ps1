[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime, [switch]$TimingOnly)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
$savedTiming = $env:GODOT_JFX_ANIMATION_TIMING_ONLY
try {
    $env:GODOT_JFX_ANIMATION_TIMING_ONLY = if ($TimingOnly) { '1' } else { '0' }
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxAnimationProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VFX animation probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    if ($TimingOnly) { $suffix += '-timing-only' }
    $log = Join-Path (Get-Location) "artifacts/logs/vfx-animation-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-vfx-animation'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'godot/bin/godot.windows.template_release.x86_64.console.exe', 'godot/bin/godot.windows.template_release.x86_64.exe', 'tests/godot/vfx_animation.gd', 'tests/godot/vfx_animation.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://vfx_animation.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "VFX animation runtime import failed: $log.import" }
        Push-Location $fixture
        try { & .\godot.windows.template_release.x86_64.console.exe --rendering-method $Renderer --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_animation.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_VFX_ANIMATION_PASS' -or $output -notmatch 'VFX_ANIMATION_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "VFX animation failed: $log" }
    if ($TimingOnly) {
        if ($output -notmatch 'VFX_ANIMATION_TIMING_STATS') { throw "Missing timing evidence: $log" }
        Write-Output "Animation timing control completed (no GPU-motion acceptance): $log"
        return
    }
    foreach ($step in 0..7) { Copy-Item "artifacts/reference/vfx-animation-$step.png" "artifacts/reference/vfx-animation-$Renderer-$RenderThread$suffix-$step.png" }
    if ($output -notmatch 'VFX_ANIMATION_GPU_MOTION') { throw "No GPU motion evidence: $log" }
    foreach ($file in 'motion-start.png','motion.json') { Copy-Item "artifacts/reference/vfx-animation-$file" "artifacts/reference/vfx-animation-$Renderer-$RenderThread$suffix-$file" }
    Write-Output "VFX animation passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_ANIMATION_TIMING_ONLY = $savedTiming; Pop-Location }
