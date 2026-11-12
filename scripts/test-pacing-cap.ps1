[CmdletBinding()]
param([string]$Jdk='D:\jdk-25.0.3+9', [ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile', [ValidateSet('cap','restore','override')][string]$Mode='cap')
$ErrorActionPreference='Stop'
$savedJdk=$env:GODOT_JFX_JDK
$savedFallback=$env:GODOT_JFX_VSYNC_FALLBACK
$savedMode=$env:GODOT_JFX_TEST_PACING_MODE
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" -d artifacts/reference tests/reference/PacingCapProbe.java
    if($LASTEXITCODE -ne 0){throw 'Pacing fixture compilation failed'}
    $env:GODOT_JFX_JDK=$Jdk
    $env:GODOT_JFX_VSYNC_FALLBACK='1'
    $env:GODOT_JFX_TEST_PACING_MODE=$Mode
    $log="artifacts/logs/pacing-cap-$Renderer-$Mode.log"
    & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://pacing_cap.tscn --rendering-method $Renderer *> $log
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch '(?m)^PACING_CAP_PASS' -or $output -notmatch 'PACING_CAP_JAVA_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)' -or (($Mode -eq 'cap') -eq ($output -match 'JAVAFX_VSYNC_FALLBACK'))){throw "Pacing cap test failed: $log"}
    Write-Output "Pacing cap test passed: $log"
} finally { $env:GODOT_JFX_JDK=$savedJdk; $env:GODOT_JFX_VSYNC_FALLBACK=$savedFallback; $env:GODOT_JFX_TEST_PACING_MODE=$savedMode; Pop-Location }
