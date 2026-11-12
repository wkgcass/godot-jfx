[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME, [ValidateSet('safe')][string]$RenderThread='safe')
$ErrorActionPreference='Stop'
$names=@('GODOT_JFX_JDK','GODOT_JFX_LCD_SCREEN')
$saved=@{}; foreach($name in $names){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" --module-path jfx/build/sdk/lib --add-modules javafx.controls -encoding UTF-8 -d artifacts/reference tests/reference/LcdOverlapProbe.java
    if($LASTEXITCODE -ne 0){throw 'LCD probe compilation failed'}
    $env:GODOT_JFX_JDK=$Jdk
    foreach($mode in @('0','1')) {
        $env:GODOT_JFX_LCD_SCREEN=$mode
        $log="artifacts/logs/lcd-overlap-$RenderThread-$mode.log"
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://lcd_overlap.tscn --rendering-method mobile --render-thread $RenderThread --quit-after 3000 *> $log
        $code=$LASTEXITCODE; $output=Get-Content $log -Raw
        if($code -ne 0 -or $output -notmatch 'LCD_OVERLAP_JAVA_PASS' -or $output -notmatch 'LCD_OVERLAP_CAPTURE_PASS' -or ($mode -eq '1' -and $output -notmatch 'LCD_OVERLAP_DIFF_PASS') -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)'){throw "LCD overlap failed: $log"}
    }
    Write-Output "LCD overlap passed: $RenderThread (Godot LCDBuffer vs screen sampling)"
} finally {
    foreach($name in $names){if ($null -eq $saved[$name]) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }}
    Pop-Location
}
