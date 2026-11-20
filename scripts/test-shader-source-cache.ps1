#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$savedCache=$env:GODOT_JFX_SHADER_SOURCE_CACHE
try {
    $env:GODOT_JFX_SHADER_SOURCE_CACHE='1'
    $exports=@('--add-exports','javafx.graphics/com.sun.prism.godot=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics @exports -d artifacts/reference tests/reference/ShaderSourceCacheProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Shader source cache test compilation failed' }
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics @exports --add-exports javafx.graphics/com.sun.prism=ALL-UNNAMED --add-opens javafx.graphics/com.sun.prism.godot=ALL-UNNAMED --add-opens javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -cp artifacts/reference ShaderSourceCacheProbe
    if ($LASTEXITCODE -ne 0) { throw 'Shader source cache test failed' }
} finally { $env:GODOT_JFX_SHADER_SOURCE_CACHE=$savedCache; Pop-Location }
