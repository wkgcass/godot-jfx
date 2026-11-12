[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe', [switch]$Runtime)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/RenderScaleProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Render scale probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path $root "artifacts/logs/render-scale-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-render-scale'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.console.exe'), (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.exe') -Destination $fixture -Force
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/render_scale.tscn'), (Join-Path $root 'tests/godot/render_scale.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://render_scale.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Scale runtime import failed: $log.import" }
        Push-Location $fixture
        try { & (Join-Path $fixture 'godot.windows.template_release.x86_64.console.exe') --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log }
        finally { Pop-Location }
    } else {
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://render_scale.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_RENDER_SCALE_PASS' -or $output -notmatch 'RENDER_SCALE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Render scale test failed: $log" }
    Write-Output "Render scale passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }




