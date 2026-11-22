#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime, [switch]$StopHost)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedToken = $env:GODOT_JFX_DIALOG_TOKEN
$savedStop = $env:GODOT_JFX_DIALOG_STOP
$savedReady = $env:GODOT_JFX_DIALOG_READY
$process = $null
$readyPath = $null
$cancel = [Threading.CancellationTokenSource]::new()
$driver = $null
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.ps=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/FileDialogProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'File dialog probe compilation failed' }
    $env:JAVA_HOME = $Jdk
    $env:GODOT_JFX_DIALOG_TOKEN = 'JFX-' + [guid]::NewGuid().ToString('N')
    Add-Type -Path (Join-Path $root 'tests/reference/FileDialogDriver.cs')
    $env:GODOT_JFX_DIALOG_STOP=if($StopHost){'1'}else{'0'}
    $readyPath=Join-Path $root ("agentdir/logs/"+$env:GODOT_JFX_DIALOG_TOKEN+'.ready')
    $env:GODOT_JFX_DIALOG_READY=$readyPath
    $driver = [FileDialogDriver]::Start($env:GODOT_JFX_DIALOG_TOKEN,$cancel.Token,[bool]$StopHost,$env:GODOT_JFX_DIALOG_READY)
    $suffix=$(if($Runtime){'-runtime'}else{''})+$(if($StopHost){'-stop'}else{''})
    $log = Join-Path $root "agentdir/logs/file-dialog-$Driver-$RenderThread$suffix.log"
    if($Runtime) {
        $fixture=Join-Path $root 'artifacts/runtime-file-dialog'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/file_dialog.gd'),(Join-Path $root 'tests/godot/file_dialog.tscn') -Destination $fixture -Force
        $project=[IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://file_dialog.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if($LASTEXITCODE -ne 0) { throw "File dialog runtime import failed: $log.import" }
        $directory=$fixture
        $arguments=@('--render-thread',$RenderThread)
    } else {
        $directory=$root
        $arguments=@('--path','tests/godot','res://file_dialog.tscn','--render-thread',$RenderThread)
    }
    $err="$log.stderr"
    $process=Start-GodotFixture -Driver $Driver -ArgumentList $arguments -WorkingDirectory $directory -Log $log -ErrorLog $err
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(!$process.WaitForExit(250)) {
        if($driver.IsFaulted) { $null=$driver.GetAwaiter().GetResult() }
        if($watch.Elapsed.TotalSeconds -gt 70) { throw 'Native chooser process timeout' }
    }
    $process.WaitForExit()
    $output=[IO.File]::ReadAllText($log)+[IO.File]::ReadAllText($err)
    if ($process.ExitCode -ne 0 -or $output -notmatch 'GODOT_FILE_DIALOG_PASS' -or $output -notmatch 'FILE_DIALOG_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "File dialog test failed: $log / $err" }
    if($StopHost -and $output -notmatch 'FILE_DIALOG_HOST_STOP_RETURNED') { throw 'Host-stop path not completed' }
    $report=$driver.GetAwaiter().GetResult()
    [IO.File]::WriteAllText("$log.native",$report)
    if($report -notmatch 'FILE_DIALOG_NATIVE_PASS') { throw 'Native dialog checks incomplete' }
    Write-Output "File dialog passed: $log"
} finally {
    if($process -and !$process.HasExited) { $process.Kill(); $process.WaitForExit() }
    if($process) { $process.Dispose() }
    $cancel.Cancel()
    if($driver) { try { $null=$driver.GetAwaiter().GetResult() } catch { Write-Warning $_.Exception.Message } }
    $cancel.Dispose()
    if($readyPath -and (Test-Path -LiteralPath $readyPath)) { Remove-Item -LiteralPath $readyPath }
    $env:GODOT_JFX_DIALOG_READY=$savedReady
    $env:GODOT_JFX_DIALOG_STOP=$savedStop
    $env:GODOT_JFX_DIALOG_TOKEN=$savedToken
    $env:JAVA_HOME=$savedJdk
    Pop-Location
}




