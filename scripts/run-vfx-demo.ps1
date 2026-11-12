[CmdletBinding()]
param([string]$Jdk='D:\jdk-25.0.3+9',[ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',[ValidateSet('safe','separate')][string]$RenderThread='safe',[switch]$Smoke,[switch]$NoGodotLogo)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$saved=@{}
$settings=@{
    GODOT_JFX_JDK=$Jdk;
    GODOT_JFX_STARTUP=$(if($NoGodotLogo){'hidden'}else{'logo'});
    GODOT_JFX_DEMO_SMOKE=$(if($Smoke){'1'}else{'0'})
}
try {
    foreach($key in $settings.Keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$settings[$key],'Process')}
    $log="artifacts/logs/vfx-demo-$Renderer-$RenderThread.log"
    Write-Output "Starting the original VFX Demo with backend defaults (explicit environment overrides are preserved). Close its window to exit. Log: $log"
    # Windows PowerShell 5.1 wraps native stderr in ErrorRecord objects.
    # A JVM warning must not terminate the pipeline (and the hosted process).
    $savedErrorActionPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & ./godot/bin/godot.windows.editor.x86_64.console.exe --path tests/godot res://vfx_demo.tscn --rendering-method $Renderer --render-thread $RenderThread 2>&1 |
            ForEach-Object { $_.ToString() } |
            Out-File -LiteralPath $log -Encoding utf8 -ErrorAction Stop
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$savedErrorActionPreference }
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'VFX_DEMO_CLOSED' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "VFX Demo failed (native exit $code): $log"}
    Write-Output "VFX Demo closed cleanly: $log"
} finally {foreach($key in $saved.Keys){if ($null -eq $saved[$key]) { Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }};Pop-Location}
