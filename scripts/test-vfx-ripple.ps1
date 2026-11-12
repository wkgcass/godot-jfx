[CmdletBinding()]
param(
    [string]$Jdk = $env:JAVA_HOME,
    [ValidateSet('mobile','gl_compatibility')][string]$Renderer = 'mobile',
    [ValidateSet('safe')][string]$RenderThread = 'safe',
    [switch]$NativeD3D
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$saved = @{}
foreach ($name in @('GODOT_JFX_JDK','GODOT_JFX_RIPPLE_OUTPUT')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxRippleProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Ripple probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $caseName = "$Renderer-$RenderThread"
    if ($NativeD3D) { $caseName = 'native-d3d' }
    $env:GODOT_JFX_RIPPLE_OUTPUT = Join-Path $root "artifacts/reference/vfx-ripple-$caseName"
    $log = "artifacts/logs/vfx-ripple-$caseName.log"
    if ($NativeD3D) {
        $nativeClassPath = "$classpath;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/reference"
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing,javafx.media '-Dglass.platform=Win' '-Dprism.order=d3d' -cp $nativeClassPath io.vproxy.vfx.intro.VfxRippleProbe *> $log
    } else {
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_ripple.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $code = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($code -ne 0 -or $output -notmatch 'VFX_RIPPLE_PROBE_PASS' -or (!$NativeD3D -and $output -notmatch 'GODOT_VFX_RIPPLE_PASS') -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError') {
        throw "Ripple test failed: $log"
    }
    Write-Output "Ripple test passed: $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
}
