[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe','separate')][string]$RenderThread = 'safe', [switch]$Robot, [switch]$CompileOnly)
$ErrorActionPreference = 'Stop'
if (!$CompileOnly -and !$Robot) { throw 'This test moves the real mouse. Obtain user consent, then pass -Robot; use -CompileOnly for compilation.' }
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedRd = $env:GODOT_JFX_RD_DIRECT
$savedRobot = $env:GODOT_JFX_HOVER_DEMO_ROBOT
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $vfxBase = Join-Path $root 'artifacts/vfx'
    $vfxCp = @("$vfxBase/classes/java/main", "$vfxBase/classes/java/test", "$vfxBase/resources/main", "$vfxBase/resources/test") + (Get-ChildItem "$vfxBase/dependencies" -Filter *.jar | ForEach-Object { $_.FullName })
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp ($vfxCp -join ';') -encoding UTF-8 -d artifacts/reference tests/reference/HoverDemoProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Hover demo probe compilation failed' }
    if ($CompileOnly) { Write-Output 'Hover demo compilation passed; physical run not performed'; return }
    $env:GODOT_JFX_HOVER_DEMO_ROBOT = '1'
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_RD_DIRECT = '1'
    $log = "artifacts/logs/hover-demo-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://hover_demo.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    $code = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($code -ne 0 -or $output -notmatch 'HOVER_DEMO_PASS' -or $output -notmatch 'HOVER_DEMO_PIXEL_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:') { throw "Hover demo probe failed. See $log" }
    Write-Output "Hover demo probe passed: $log"
} finally { $env:GODOT_JFX_HOVER_DEMO_ROBOT = $savedRobot; $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_RD_DIRECT = $savedRd; Pop-Location }
