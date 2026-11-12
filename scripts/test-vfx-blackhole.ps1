[CmdletBinding()]
param(
    [string]$Jdk = 'D:\jdk-25.0.3+9',
    [ValidateSet('mobile','gl_compatibility')][string]$Renderer = 'mobile',
    [ValidateSet('safe','separate')][string]$RenderThread = 'safe',
    [switch]$RD,
    [switch]$NativeD3D
)
$ErrorActionPreference = 'Stop'
if ($NativeD3D -and $RD) { throw '-RD cannot be combined with -NativeD3D' }
$root = Split-Path $PSScriptRoot -Parent
$saved = @{}
foreach ($name in @('GODOT_JFX_JDK','GODOT_JFX_RD_DIRECT','GODOT_JFX_BLACKHOLE_OUTPUT')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    $classpath = 'artifacts/vfx/classes/java/main;artifacts/vfx/classes/java/test;artifacts/vfx/dependencies/*'
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing -cp $classpath -encoding UTF-8 -d artifacts/reference tests/reference/VfxBlackholeProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Blackhole probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_RD_DIRECT = if ($RD) { '1' } else { '0' }
    $caseName = "$Renderer-$RenderThread-rd$($env:GODOT_JFX_RD_DIRECT)"
    if ($NativeD3D) { $caseName = 'native-d3d' }
    $env:GODOT_JFX_BLACKHOLE_OUTPUT = Join-Path $root "artifacts/reference/vfx-blackhole-$caseName"
    $log = "artifacts/logs/vfx-blackhole-$caseName.log"
    if ($NativeD3D) {
        $nativeClassPath = "$classpath;artifacts/vfx/resources/main;artifacts/vfx/resources/test;artifacts/reference"
        & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls,javafx.swing,javafx.media '-Dglass.platform=Win' '-Dprism.order=d3d' -cp $nativeClassPath VfxBlackholeProbe *> $log
    } else {
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_blackhole.tscn --rendering-method $Renderer --render-thread $RenderThread *> $log
    }
    $code = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($code -ne 0 -or $output -notmatch 'VFX_BLACKHOLE_PROBE_PASS' -or (!$NativeD3D -and $output -notmatch 'GODOT_VFX_BLACKHOLE_PASS') -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:|AssertionError') {
        throw "Blackhole test failed: $log"
    }
    Write-Output "Blackhole test passed: $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
}
