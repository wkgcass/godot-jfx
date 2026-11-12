[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$saved=$env:GODOT_JFX_IMAGE_POOL_LIFO
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $options=@('--module-path','jfx/build/sdk/lib','--add-modules','javafx.graphics')
    foreach($package in @('com.sun.javafx.geom','com.sun.javafx.geom.transform','com.sun.scenario.effect','com.sun.scenario.effect.impl')) {
        $options+=@('--add-exports',"javafx.graphics/$package=ALL-UNNAMED")
    }
    & "$Jdk/bin/javac.exe" @options -encoding UTF-8 -d artifacts/reference tests/reference/ImagePoolReuseProbe.java
    if($LASTEXITCODE -ne 0){throw 'Image pool probe compilation failed'}
    foreach($mode in @('1','0')){
        $env:GODOT_JFX_IMAGE_POOL_LIFO=$mode
        $log="artifacts/logs/image-pool-reuse-$mode.log"
        & "$Jdk/bin/java.exe" @options --add-opens javafx.graphics/com.sun.scenario.effect.impl=ALL-UNNAMED -cp artifacts/reference ImagePoolReuseProbe *> $log
        if($LASTEXITCODE -ne 0 -or (Get-Content $log -Raw) -notmatch 'IMAGE_POOL_REUSE_PASS'){throw "Image pool reuse failed: $log"}
    }
    Write-Output 'Image pool reuse passed in FIFO and LIFO modes'
} finally { $env:GODOT_JFX_IMAGE_POOL_LIFO=$saved; Pop-Location }
