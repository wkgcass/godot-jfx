#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12', [ValidateSet('safe')][string]$RenderThread = 'safe', [switch]$Runtime)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.impl=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.prism.paint=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.geom=ALL-UNNAMED --add-exports javafx.graphics/com.sun.glass.ui=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/ImageCursorProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Image cursor probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $suffix = if ($Runtime) { '-runtime' } else { '' }
    $log = Join-Path $root "agentdir/logs/image_cursor-$Driver-$RenderThread$suffix.log"
    if ($Runtime) {
        $fixture = Join-Path $root 'artifacts/runtime-image-cursor'
        New-Item -ItemType Directory -Force $fixture | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'tests/godot/image_cursor.tscn'), (Join-Path $root 'tests/godot/image_cursor.gd') -Destination $fixture -Force
        $project = [IO.File]::ReadAllText((Join-Path $root 'tests/godot/project.godot')).Replace('res://main.tscn','res://image_cursor.tscn')
        [IO.File]::WriteAllText((Join-Path $fixture 'project.godot'),$project)
        & .\godot\bin\godot.windows.editor.x86_64.console.exe --headless --path $fixture --editor --import *> "$log.import"
        if ($LASTEXITCODE -ne 0) { throw "Cursor runtime import failed: $log.import" }
        Push-Location $fixture
        try { Invoke-GodotFixture -Driver $Driver --render-thread $RenderThread --quit-after 3000 *> $log }
        finally { Pop-Location }
    } else {
        Invoke-GodotFixture -Driver $Driver --path tests/godot res://image_cursor.tscn --render-thread $RenderThread --quit-after 3000 *> $log
    }
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'IMAGE_CURSOR_PROBE_PASS' -or $output -notmatch 'GODOT_IMAGE_CURSOR_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)') { throw "Image cursor test failed: $log" }
    Write-Output "Image cursor passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; Pop-Location }


