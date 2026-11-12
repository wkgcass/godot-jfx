[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$saved=$env:GODOT_JFX_GEOMETRY_CACHE
$savedMax=$env:GODOT_JFX_GEOMETRY_CACHE_MAX
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $env:GODOT_JFX_GEOMETRY_CACHE='1'
    $env:GODOT_JFX_GEOMETRY_CACHE_MAX='1024'
    $moduleArgs=@('--module-path','jfx/build/sdk/lib','--add-modules','javafx.graphics','--add-exports','javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" @moduleArgs -encoding UTF-8 -d artifacts/reference tests/reference/RenderCommandValidationProbe.java
    if($LASTEXITCODE -ne 0){throw 'Encoder probe compilation failed'}
    & "$Jdk/bin/java.exe" @moduleArgs --add-opens javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp artifacts/reference RenderCommandValidationProbe *> artifacts/logs/render-command-validation.log
    if($LASTEXITCODE -ne 0 -or (Get-Content artifacts/logs/render-command-validation.log -Raw) -notmatch 'RENDER_COMMAND_VALIDATION_PASS'){throw 'Encoder validation failed: artifacts/logs/render-command-validation.log'}
    Write-Output 'Render command validation passed'
} finally { $env:GODOT_JFX_GEOMETRY_CACHE=$saved; $env:GODOT_JFX_GEOMETRY_CACHE_MAX=$savedMax; Pop-Location }
