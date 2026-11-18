[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [switch]$AllPages, [ValidateSet('safe')][string]$RenderThread = 'safe', [int]$PageLimit = 0, [switch]$FreezeFusion)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedPages = $env:GODOT_JFX_VFX_PAGES
$savedFreeze = $env:GODOT_JFX_VFX_FREEZE
Push-Location $root
try {
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_VFX_FREEZE = if ($FreezeFusion) { '1' } else { '0' }
    $env:GODOT_JFX_VFX_PAGES = if ($AllPages) { (Select-String -Path vfx/src/test/java/io/vproxy/vfx/intro/IntroFXMain.java -Pattern 'mainScenes.add\(new').Count.ToString() } else { '2' }
    if ($PageLimit -ne 0) {
        if (!$AllPages -or $PageLimit -lt 3 -or $PageLimit -gt [int]$env:GODOT_JFX_VFX_PAGES) { throw 'PageLimit requires AllPages and a valid count of at least 3' }
        $env:GODOT_JFX_VFX_PAGES = $PageLimit.ToString()
    }
    if ($AllPages) {
        $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
        & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxNavigationProbe.java
        if ($LASTEXITCODE -ne 0) { throw 'VFX navigation observer compilation failed' }
    }
    $coverage = if ($AllPages) { '-all-pages' } else { '' }
    if ($PageLimit) { $coverage += "-$PageLimit" }
    if ($FreezeFusion) { $coverage += '-frozen' }
    $log = "artifacts/logs/vfx-intro-$Renderer-$RenderThread$coverage.log"
    Invoke-GodotFixture --path tests/godot res://vfx_intro.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 30000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'VFX_INTRO_SMOKE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "VFX Intro smoke failed. See $log" }
    Copy-Item artifacts/reference/vfx-intro.png "artifacts/reference/vfx-intro-$Renderer.png"
    Copy-Item artifacts/reference/vfx-intro-next.png "artifacts/reference/vfx-intro-next-$Renderer.png"
    Write-Output "VFX Intro smoke passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_VFX_PAGES = $savedPages; $env:GODOT_JFX_VFX_FREEZE = $savedFreeze; Pop-Location }

