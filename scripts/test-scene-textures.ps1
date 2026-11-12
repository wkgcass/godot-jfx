[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [switch]$MissingScene, [switch]$Resize)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedMissing = $env:GODOT_JFX_SCENE_MISSING
$savedResize = $env:GODOT_JFX_SCENE_RESIZE
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/SceneTextureProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Scene texture probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_SCENE_MISSING = if ($MissingScene) { '1' } else { '0' }
    $env:GODOT_JFX_SCENE_RESIZE = if ($Resize) { '1' } else { '0' }
    $suffix = if ($MissingScene) { '-missing' } elseif ($Resize) { '-resize' } else { '' }
    $log = "artifacts/logs/scene-textures-$Renderer$suffix.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://scene_textures.tscn --rendering-method $Renderer --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($MissingScene) {
        if ($result -ne 0 -or $output -notmatch 'SCENE_TEXTURE_FAILURE_PASS' -or $output -match '(?m)^(SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Scene failure probe failed. See $log" }
    } else {
        if ($result -ne 0 -or $output -notmatch 'GODOT_SCENE_TEXTURE_PASS' -or $output -notmatch 'SCENE_TEXTURE_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Scene texture probe failed. See $log" }
        Copy-Item artifacts/reference/godot-scene-textures.png "artifacts/reference/godot-scene-textures-$Renderer$suffix.png"
    }
    Write-Output "Scene texture probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_SCENE_MISSING = $savedMissing; $env:GODOT_JFX_SCENE_RESIZE = $savedResize; Pop-Location }
