[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe')][string]$RenderThread = 'safe', [ValidateSet('FailureShutdownProbe','FailureApplicationProbe')][string]$Probe = 'FailureShutdownProbe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedProbe = $env:GODOT_JFX_FAILURE_PROBE
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference "tests/reference/$Probe.java"
    if ($LASTEXITCODE -ne 0) { throw 'Failure probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_FAILURE_PROBE = $Probe
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path $root "artifacts/logs/failure-shutdown-$Probe-$Renderer-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-failure-shutdown'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/failure_shutdown.tscn'), (Join-Path $root 'tests/godot/failure_shutdown.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://failure_shutdown.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Failure runtime fixture import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture --rendering-method $Renderer --render-thread $RenderThread --quit-after 4000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture --path tests/godot res://failure_shutdown.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 4000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    $unexpected = @(Get-Content $log | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*(Exception|Error))|RejectedExecutionException|RenderJob.run: internal exception|Suppressed:|Caused by:' -and $_ -ne 'ERROR: Java application failed; see JVM exception in the host log' -and $_ -ne 'Exception in thread "main" java.lang.IllegalStateException: INJECTED_STAGE_FAILURE' })
    if ($result -ne 0 -or $output -notmatch 'GODOT_FAILURE_SHUTDOWN_PASS' -or $output -notmatch 'FAILURE_INNER_LOOP_RETURNED' -or $output -notmatch 'FAILURE_NESTED_LOOP_RETURNED' -or $output -notmatch 'INJECTED_STAGE_FAILURE' -or $unexpected.Count -ne 0) { throw "Failure shutdown test failed: $log" }
    Write-Output "Failure shutdown passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_FAILURE_PROBE = $savedProbe; Pop-Location }
