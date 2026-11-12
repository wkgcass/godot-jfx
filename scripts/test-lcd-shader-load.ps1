[CmdletBinding()]
param([string]$Jdk='D:\jdk-25.0.3+9')
$ErrorActionPreference='Stop'
$saved=$env:GODOT_JFX_LCD_SCREEN
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $patch='artifacts/reference/lcd-shader-format-patch'
    $resource='com/sun/prism/godot/shaders'
    New-Item -ItemType Directory -Force "$patch/$resource",artifacts/logs | Out-Null
    foreach($name in @('Solid_TextureSecondPassLCD','Solid_TextureSecondPassLCD_AlphaTest')) {
        $source=[IO.File]::ReadAllText((Join-Path $PWD "jfx/build/modular-sdk/modules/javafx.graphics/$resource/$name.gdshader"))
        $modified=$source.Replace('uniform sampler2D dstColor;', 'uniform sampler2D dstColor ;')
        if($modified -eq $source){throw "Stock shader fixture no longer matches: $name"}
        [IO.File]::WriteAllText((Join-Path $PWD "$patch/$resource/$name.gdshader"),$modified)
    }
    $moduleArgs=@('--module-path','jfx/build/sdk/lib','--add-modules','javafx.graphics','--add-exports','javafx.graphics/com.sun.prism.godot=ALL-UNNAMED')
    & "$Jdk/bin/javac.exe" @moduleArgs -encoding UTF-8 -d artifacts/reference tests/reference/LcdShaderLoadProbe.java
    if($LASTEXITCODE -ne 0){throw 'LCD shader load probe compilation failed'}
    foreach($mode in @('0','1')) {
        $env:GODOT_JFX_LCD_SCREEN=$mode
        foreach($altered in @($false,$true)) {
            $extra=@(); $expect=@()
            if($altered){$extra=@('--patch-module',"javafx.graphics=$patch")}
            if($altered -and $mode -eq '1'){$expect=@('reject')}
            $log="artifacts/logs/lcd-shader-load-$mode-$altered.log"
            & "$Jdk/bin/java.exe" @moduleArgs @extra -cp artifacts/reference LcdShaderLoadProbe @expect *> $log
            if($LASTEXITCODE -ne 0 -or (Get-Content $log -Raw) -notmatch 'LCD_SHADER_LOAD_PASS'){throw "LCD shader loading failed: $log"}
        }
    }
    Write-Output 'LCD shader loading passed: stock and changed format, both LCD modes'
} finally { $env:GODOT_JFX_LCD_SCREEN=$saved; Pop-Location }
