#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" -encoding UTF-8 -d artifacts/reference tests/reference/ClipboardEncodingProbe.java
    if($LASTEXITCODE -ne 0){throw 'Clipboard encoding probe compilation failed'}
    $log='agentdir/logs/clipboard-encoding.log'
    & "$Jdk/bin/java.exe" -Xmx32m -XX:MaxDirectMemorySize=96m --module-path jfx/build/sdk/lib --add-modules javafx.graphics --add-opens javafx.graphics/com.sun.glass.ui.godot=ALL-UNNAMED -cp artifacts/reference ClipboardEncodingProbe *> $log
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'CLIPBOARD_ENCODING_PASS' -or $output -notmatch 'CLIPBOARD_IMAGE_BUDGET_PASS'){throw "Clipboard encoding failed: $log"}
    Write-Output 'Clipboard encoding passed (no system clipboard access)'
} finally { Pop-Location }
