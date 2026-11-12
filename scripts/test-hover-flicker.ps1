[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'mobile', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Robot)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedRobot = $env:GODOT_JFX_HOVER_ROBOT
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $vfxBase = Join-Path $root 'artifacts/vfx'
    $vfxCp = @("$vfxBase/classes/java/main", "$vfxBase/classes/java/test", "$vfxBase/resources/main", "$vfxBase/resources/test") + (Get-ChildItem "$vfxBase/dependencies" -Filter *.jar | ForEach-Object { $_.FullName })
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp ($vfxCp -join ';') -encoding UTF-8 -d artifacts/reference tests/reference/HoverFlickerProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Hover flicker probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_HOVER_ROBOT = if($Robot){'1'}else{'0'}
    $log = "artifacts/logs/hover-flicker-$Renderer-$RenderThread$(if($Robot){'-robot'}else{''}).log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://hover_flicker.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    $code = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($code -ne 0 -or $output -notmatch 'HOVER_PIXEL_STATS' -or $output -notmatch 'HOVER_FLICKER_PASS' -or $output -notmatch 'HOVER_FUSION_PIXEL_PASS' -or $output -notmatch 'HOVER_RESOURCE_CLEANUP_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:') { throw "Hover flicker probe failed. See $log" }
    Write-Output "Hover flicker probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_HOVER_ROBOT = $savedRobot; Pop-Location }
