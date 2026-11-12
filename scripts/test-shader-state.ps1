[CmdletBinding()]
param([string]$Jdk = 'D:\jdk-25.0.3+9')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $options = @('--module-path', 'jfx/build/sdk/lib', '--add-modules', 'javafx.graphics',
        '--add-exports', 'javafx.graphics/com.sun.prism.godot=ALL-UNNAMED',
        '--add-exports', 'javafx.graphics/com.sun.prism.ps=ALL-UNNAMED',
        '--add-exports', 'javafx.graphics/com.sun.prism.shader=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" @options -encoding UTF-8 -d artifacts/reference tests/reference/ShaderStateProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'ShaderStateProbe compilation failed' }
    & "$Jdk/bin/java.exe" @options -cp artifacts/reference ShaderStateProbe jfx/build/sdk/lib/javafx.graphics.jar *> artifacts/logs/m2-shader-state.log
    if ($LASTEXITCODE -ne 0) { throw 'ShaderStateProbe failed; see artifacts/logs/m2-shader-state.log' }
    Get-Content artifacts/logs/m2-shader-state.log
} finally { Pop-Location }
