#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [switch]$Robot, [switch]$CompileOnly, [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12')
. "$PSScriptRoot/godot-fixture.ps1"
$ErrorActionPreference = 'Stop'
if (!$CompileOnly -and !$Robot) {
    throw 'This test opens the system touch keyboard. Pass -Robot to run it, or -CompileOnly to compile the probe.'
}
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$log = Join-Path $root 'agentdir/logs/virtual-keyboard.log'
Push-Location $root
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.javafx.tk=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED --add-exports javafx.graphics/com.sun.javafx.stage=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/VirtualKeyboardProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'VirtualKeyboardProbe compilation failed' }
    if ($CompileOnly) { Write-Output 'VirtualKeyboardProbe compilation passed; system keyboard not requested'; return }
    $env:GODOT_JFX_JDK = $Jdk
    Invoke-GodotFixture -Driver $Driver --path tests/godot res://virtual_keyboard.tscn --quit-after 3000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content -LiteralPath $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_VIRTUAL_KEYBOARD_PASS' -or $output -notmatch 'VIRTUAL_KEYBOARD_PASS:' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception)') {
        throw "Virtual keyboard test failed or incomplete (exit $result). See $log"
    }
    # This probe checks call completion and host liveness, not OS visibility.
    # Keep native request failures visible even when those narrower checks pass.
    $output -split "`r?`n" | Where-Object { $_ -match '^WARNING: JavaFX touch keyboard ' } | Write-Output
    Write-Output "Virtual keyboard call/liveness checks passed; OS visibility and close success are not verified. Log: $log"
} finally {
    $env:GODOT_JFX_JDK = $savedJdk
    Pop-Location
}
