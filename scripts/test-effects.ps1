[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/EffectsProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Effects probe compilation failed' }
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED '-Dprism.order=d3d' '-Deffects.reference=artifacts/reference/d3d-effects.png' -cp artifacts/reference EffectsProbe *> artifacts/logs/effects-d3d.log
    if ($LASTEXITCODE -ne 0 -or (Get-Content artifacts/logs/effects-d3d.log -Raw) -notmatch 'EFFECTS_REFERENCE_PASS') { throw 'D3D effects reference failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = ''
    if ($Runtime) { $suffix += '-runtime' }
    $log = Join-Path $root "artifacts/logs/effects-$Renderer$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-effects'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/effects.tscn'), (Join-Path $root 'tests/godot/effects_test.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://effects.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Effects runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture --rendering-method $Renderer --render-thread $RenderThread --quit-after 3000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture --path tests/godot res://effects.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 3000 *> $log
    }
    $result = $LASTEXITCODE
    Add-Content -LiteralPath $log -Value "EFFECTS_NATIVE_EXIT_CODE $result"
    $output = Get-Content $log -Raw
    if (Test-Path artifacts/reference/godot-effects.png) { Copy-Item artifacts/reference/godot-effects.png "artifacts/reference/godot-effects-$Renderer$suffix.png" }
    if ($result -ne 0 -or $output -notmatch 'GODOT_EFFECTS_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "Effects probe failed (native exit $result). See $log" }
    Write-Output "Effects probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
