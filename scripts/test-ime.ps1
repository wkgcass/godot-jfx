[CmdletBinding()]
param([string]$Jdk = $env:JAVA_HOME, [ValidateSet('gl_compatibility','mobile')][string]$Renderer = 'gl_compatibility', [switch]$SpacedClick)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$savedJdk = $env:GODOT_JFX_JDK
$savedSpacedClick = $env:GODOT_JFX_IME_SPACED_CLICK
Push-Location $root
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls --add-exports javafx.graphics/com.sun.javafx.tk.godot=ALL-UNNAMED -encoding UTF-8 -d artifacts/reference tests/reference/ImeProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'IME probe compilation failed' }
    $env:GODOT_JFX_JDK = $Jdk
    $env:GODOT_JFX_IME_SPACED_CLICK = if ($SpacedClick) { '1' } else { '0' }
    $suffix = if ($SpacedClick) { "-spaced" } else { "" }
    $log = "artifacts/logs/ime-$Renderer$suffix.log"
    & .\godot\bin\godot.windows.editor.x86_64.console.exe --path tests/godot res://ime.tscn --rendering-method $Renderer --quit-after 4000 *> $log
    $result = $LASTEXITCODE
    $output = Get-Content $log -Raw
    if ($result -ne 0 -or $output -notmatch 'GODOT_IME_PASS' -or $output -notmatch 'IME_PROBE_PASS' -or $output -notmatch 'IME_MOUSE_ORDER_PASS' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|Exception|java\.[a-z].*Exception)') { throw "IME probe failed: $log" }
    Write-Output "IME probe passed: $log"
} finally { $env:GODOT_JFX_JDK = $savedJdk; $env:GODOT_JFX_IME_SPACED_CLICK = $savedSpacedClick; Pop-Location }
