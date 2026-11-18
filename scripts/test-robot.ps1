[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/RobotProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Robot probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix=if($Runtime){'-runtime'}else{''}
    $log = Join-Path $root "artifacts/logs/robot-$Renderer-$RenderThread$suffix.log"
    if($Runtime) {
        $fixture=Join-Path $root 'artifacts/runtime-robot'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/robot.gd'),(Join-Path $root 'tests/godot/robot.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://robot.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0) { throw "Robot runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture --path tests/godot res://robot.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 10000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_ROBOT_PASS' -or $output -notmatch 'ROBOT_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Robot test failed: $log" }
    Write-Output "Robot passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }




