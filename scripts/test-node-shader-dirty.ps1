[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9', [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [ValidateSet('safe','separate')][string]$RenderThread = 'safe', [switch]$RD)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedRD = $env:GODOT_JFX_RD_DIRECT
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/NodeShaderDirtyProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Node shader probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_RD_DIRECT = if ($RD) { '1' } else { '0' }
    $log = "artifacts/logs/node-shader-dirty-$Renderer-$RenderThread-rd$([int]$RD.IsPresent).log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://node_shader_dirty.tscn --rendering-method $Renderer --render-thread $RenderThread --quit-after 4000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_NODE_SHADER_DIRTY_PASS' -or $output -notmatch 'NODE_SHADER_DIRTY_PROBE_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception|java\.[a-z].*Exception)') { throw "Node shader probe failed. See $log" }
    foreach ($phase in 0,1) {
        Copy-Item "artifacts/reference/node-shader-dirty-$phase.png" "artifacts/reference/node-shader-dirty-$Renderer-$RenderThread-rd$([int]$RD.IsPresent)-$phase.png"
    }
    Write-Output "Node shader dirty-region probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_RD_DIRECT = $savedRD; Pop-Location }
