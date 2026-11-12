[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -d artifacts/reference tests/reference/TimerCadenceProbe.java
    if ($LASTEXITCODE -ne 0) { throw 'Timer test compilation failed' }
    & "$Jdk/bin/java.exe" --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-exports javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED --add-opens javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -cp artifacts/reference TimerCadenceProbe
    if ($LASTEXITCODE -ne 0) { throw 'Timer cadence failed' }
} finally { Pop-Location }
