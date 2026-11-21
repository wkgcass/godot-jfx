#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    $vfxBase = Join-Path $root 'artifacts/vfx'
    $vfxCp = @("$vfxBase/classes/java/main", "$vfxBase/classes/java/test", "$vfxBase/resources/main", "$vfxBase/resources/test") + (Get-ChildItem "$vfxBase/dependencies" -Filter *.jar | ForEach-Object { $_.FullName })
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -cp ($vfxCp -join ';') -encoding UTF-8 -d artifacts/reference tests/reference/MenuClickProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Menu click probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $log = "agentdir/logs/menu-click-$Driver-$RenderThread.log"
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://menu_click.tscn --render-thread $RenderThread *> $log
    $code = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($code -ne 0 -or $output -notmatch 'MENU_CLICK_PASS' -or $output -notmatch 'GODOT_MENU_CLICK_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\..*(Exception|Error))|uncaught:') { throw "Menu click probe failed. See $log" }
    Write-Output "Menu click probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }
