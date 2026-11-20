#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $source = 'jfx/modules/javafx.graphics/src/main/java/com/sun/prism/godot'
    $patch = 'artifacts/texture-cancellation-patch'
    New-Item -ItemType Directory -Force $patch,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --patch-module "javafx.graphics=$source" -d $patch "$source/GodotTexture.java"
    if ($LASTEXITCODE -ne 0) { throw 'Texture patch compilation failed' }
    $exports = @('--add-exports','javafx.graphics/com.sun.prism=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.prism.godot=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.prism.impl=ALL-UNNAMED','--add-exports','javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics @exports -d artifacts/reference tests/reference/TextureCancellationProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Texture cancellation probe compilation failed' }
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --patch-module "javafx.graphics=$patch" @exports -cp artifacts/reference TextureCancellationProbe *> agentdir/logs/texture-cancellation.log
    if ($LASTEXITCODE -ne 0 -or (Get-Content agentdir/logs/texture-cancellation.log -Raw) -notmatch 'TEXTURE_CANCELLATION_PASS') { throw 'Texture cancellation test failed: agentdir/logs/texture-cancellation.log' }
    Write-Output 'Texture cancellation passed'
} finally { Pop-Location }
