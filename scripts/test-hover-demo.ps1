#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Robot, [switch]$CompileOnly)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
if (!$CompileOnly -and !$Robot) { throw 'This test moves the real mouse. Obtain user consent, then pass -Robot; use -CompileOnly for compilation.' }
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:JAVA_HOME
$savedRobot = $env:GODOT_JFX_HOVER_DEMO_ROBOT
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    $vfxBase = Join-Path $root 'artifacts/vfx'
    $vfxCp = @("$vfxBase/classes/java/main", "$vfxBase/classes/java/test", "$vfxBase/resources/main", "$vfxBase/resources/test") + (Get-ChildItem "$vfxBase/dependencies" -Filter *.jar | ForEach-Object { $_.FullName })
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp ($vfxCp -join ';') -encoding UTF-8 -d artifacts/reference tests/reference/HoverDemoProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Hover demo probe compilation failed' }
    if ($CompileOnly) { Write-Output 'Hover demo compilation passed; physical run not performed'; return }
    $env:GODOT_JFX_HOVER_DEMO_ROBOT = '1'
    $env:JAVA_HOME = $Jdk
    $log = "agentdir/logs/hover-demo-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://hover_demo.tscn --render-thread $RenderThread *> $log
    $code = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($code -ne 0 -or $output -notmatch 'HOVER_DEMO_PASS' -or $output -notmatch 'HOVER_DEMO_PIXEL_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:') { throw "Hover demo probe failed. See $log" }
    Write-Output "Hover demo probe passed: $log"
} finally { $env:GODOT_JFX_HOVER_DEMO_ROBOT = $savedRobot; $env:JAVA_HOME = $savedJdk; Pop-Location }
