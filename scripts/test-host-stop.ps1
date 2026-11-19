[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedJdk = $env:GODOT_JFX_JDK
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl.ps=ALL-UNNAMED -d artifacts/reference tests/reference/HostStopProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Host stop probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path (Get-Location) "artifacts/logs/host-stop-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path (Get-Location) 'artifacts/runtime-host-stop'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath 'tests/godot/host_stop.gd', 'tests/godot/host_stop.tscn' -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path (Get-Location) 'tests/godot/project.godot')).Replace('res://main.tscn','res://host_stop.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Host stop runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture --rendering-method $Renderer --render-thread $RenderThread *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture --path tests/godot res://host_stop.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'HOST_STOP_NATIVE_WINDOWS_PASS' -or $output -notmatch 'HOST_STOP_APPLICATION_RETURNED' -or $output -notmatch 'HOST_STOP_GLASS_PEERS_CLOSED' -or $output -notmatch 'HOST_STOP_PIPELINE_DISPOSED pool_bytes=0' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error)|RenderJob.run: internal exception|QuantumRenderer-\d+ uncaught:)|GodotHostStoppedException') { throw "Host stop native-window test failed: $log" }
    # Covers native/Glass destruction, application return and renderer/pool cleanup,
    # and rejects leaked cancellation exceptions as well as ordinary failures.
    Write-Output "Host stop native-window test passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
