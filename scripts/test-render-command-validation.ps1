#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$saved=$env:GODOT_JFX_GEOMETRY_CACHE
$savedMax=$env:GODOT_JFX_GEOMETRY_CACHE_MAX
$savedSuppress=$env:GODOT_JFX_STATE_SUPPRESS
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    $env:GODOT_JFX_GEOMETRY_CACHE='1'
    $env:GODOT_JFX_GEOMETRY_CACHE_MAX='1024'
    $moduleArgs=@('--module-path',(Get-GodotJfxTestModulePath),'--add-modules','javafx.graphics','--add-exports','javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.prism.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" @moduleArgs -encoding UTF-8 -d artifacts/reference tests/reference/RenderCommandValidationProbe.java tests/reference/ShaderStateSuppressionProbe.java
    if($LASTEXITCODE -ne 0){throw 'Encoder probe compilation failed'}
    & "$Jdk/bin/java.exe" @moduleArgs --add-opens javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp artifacts/reference RenderCommandValidationProbe *> agentdir/logs/render-command-validation.log
    if($LASTEXITCODE -ne 0 -or (Get-Content agentdir/logs/render-command-validation.log -Raw) -notmatch 'RENDER_COMMAND_VALIDATION_PASS'){throw 'Encoder validation failed: agentdir/logs/render-command-validation.log'}
    foreach ($suppress in '0','1') {
        $env:GODOT_JFX_STATE_SUPPRESS=$suppress
        $log="agentdir/logs/shader-state-suppression-$suppress.log"
        & "$Jdk/bin/java.exe" @moduleArgs -cp artifacts/reference ShaderStateSuppressionProbe *> $log
        if ($LASTEXITCODE -ne 0) { throw "Shader state suppression check failed: $log" }
    }
    Write-Output 'Render command validation passed'
} finally {
    $env:GODOT_JFX_STATE_SUPPRESS=$savedSuppress
    $env:GODOT_JFX_GEOMETRY_CACHE=$saved
    $env:GODOT_JFX_GEOMETRY_CACHE_MAX=$savedMax
    Pop-Location
}
