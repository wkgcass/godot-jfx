[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('yes','no')][string]$ExpectCompiled,
    [switch]$RequestRD,
    [ValidateSet('mobile','gl_compatibility')][string]$Renderer = 'mobile',
    [ValidateSet('safe','separate')][string]$RenderThread = 'safe',
    [string]$Jdk = 'D:\jdk-25.0.3+9'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$saved = @{}
foreach ($name in @('GODOT_JFX_RD_DIRECT','GODOT_JFX_EXPECT_RD_COMPILED','GODOT_JFX_JDK')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -d artifacts/reference tests/reference/RDBuildProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'RDBuildProbe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_EXPECT_RD_COMPILED = if ($ExpectCompiled -eq 'yes') { '1' } else { '0' }
    $env:GODOT_JFX_RD_DIRECT = if ($RequestRD) { '1' } else { '0' }
    New-Item -ItemType Directory -Force artifacts/logs | Out-Null
    $log = "artifacts/logs/rd-build-$ExpectCompiled-request$($env:GODOT_JFX_RD_DIRECT)-$Renderer-$RenderThread.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot --script res://rd_build.gd --rendering-method $Renderer --render-thread $RenderThread --quit-after 600 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'RD_BUILD_PASS' -or $output -match '(?m)^(SCRIPT ERROR:|SHADER ERROR:)') {
        throw "RD build test failed: $log"
    }
    $errors = @($output -split "`n" | Where-Object { $_ -match '^ERROR:' })
    if ($ExpectCompiled -eq 'no' -and $RequestRD) {
        if ($errors.Count -ne 5 -or @($errors | Where-Object { $_ -notmatch 'RD-direct was not compiled' }).Count) {
            throw "Missing rejection diagnostics or unexpected errors: $log"
        }
    } else {
        if ($errors.Count) { throw "Unexpected errors: $log" }
        if ($output -notmatch 'RD_BUILD_JNI_PASS') { throw "JNI build probe did not finish: $log" }
    }
    Write-Output "RD build test passed: $log"
} finally {
    Pop-Location
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
