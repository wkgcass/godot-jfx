[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe','separate')][string]$RenderThread = 'separate', [switch]$Runtime)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/NativeOrderProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Native order probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path (Get-Location) "artifacts/logs/native_order-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-native_order'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'godot/bin/godot.windows.template_release.x86_64.console.exe', 'godot/bin/godot.windows.template_release.x86_64.exe', 'tests/godot/native_order.gd', 'tests/godot/native_order.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://native_order.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Native order runtime import failed: $log.import" }
        Push-Location $fixture
        try { & .\godot.windows.template_release.x86_64.console.exe --rendering-method $Renderer --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://native_order.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $output = Get-Content $log -Raw
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'GODOT_NATIVE_ORDER_PASS' -or $output -notmatch 'NATIVE_ORDER_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|GodotHostStoppedException|uncaught:') { throw "Native order failed: $log" }
    Write-Output "Native order passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
