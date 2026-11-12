[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [switch]$Runtime)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$log = Join-Path $root 'artifacts/logs/m2-glass-window.log'
$binary = '.\godot\bin\godot.windows.editor.x86_64.console.exe'
if ($Runtime) {
    $binary = '.\godot\bin\godot.windows.template_release.x86_64.console.exe'
    $log = Join-Path $root 'artifacts/logs/m2-glass-window-runtime.log'
}
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/GlassWindowProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'GlassWindowProbe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    if ($Runtime) {
        # Release templates load the project beside the executable. Package a
        # dedicated fixture there instead of enabling development path overrides.
        $fixture = Join-Path $root 'artifacts/runtime-window'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $binary), (Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.exe') -Destination $fixture -Force
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/window.tscn'), (Join-Path $root 'tests/godot/window_test.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn', 'res://window.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'), $project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Runtime fixture import failed. See $log.import" }
        $runtimeBinary = Join-Path $fixture 'godot.windows.template_release.x86_64.console.exe'
        Push-Location $fixture
        try { & $runtimeBinary --quit-after 3000 *> $log }
        finally { Pop-Location }
    } else {
        & $binary --path tests/godot res://window.tscn --quit-after 3000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'M2_GLASS_WINDOW_PASS' -or $output -notmatch 'GLASS_WINDOW_PASS:' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "Glass window test failed or incomplete (exit $result). See $log"
    }
    Write-Output "Glass window test passed. Log: $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    Pop-Location
}
