[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',[ValidateSet('safe')][string]$RenderThread='safe',[switch]$Smoke,[switch]$NoGodotLogo,[switch]$DisableVsync,[ValidateRange(0,1000)][int]$MaxFps=0)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $log="artifacts/logs/vfx-demo-$Renderer-$RenderThread.log"
    New-Item -ItemType Directory -Force artifacts/logs | Out-Null
    $jar='artifacts/vfx/libs/vfx-demo.jar'
    if (!(Test-Path -LiteralPath $jar -PathType Leaf)) { throw "Missing $jar. Run scripts/build-vfx.ps1 first." }
    $program=Join-Path $Jdk 'bin/java.exe'
    $engineArgs=@('-jar',$jar,'--renderer',$Renderer)
    if ($Smoke) { $engineArgs+='--smoke' }
    if ($NoGodotLogo) { $engineArgs+='--no-godot-logo' }
    if($DisableVsync){$engineArgs+='--disable-vsync';if($MaxFps -le 0){$MaxFps=60}}
    if($MaxFps -gt 0){$engineArgs+=@('--max-fps',"$MaxFps")}
    Write-Output "Starting the original VFX Demo with Viewport + safe rendering. Close its window to exit. Log: $log"
    # Windows PowerShell 5.1 wraps native stderr in ErrorRecord objects.
    # A JVM warning must not terminate the pipeline (and the hosted process).
    $savedErrorActionPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $program @engineArgs 2>&1 |
            ForEach-Object { $_.ToString() } |
            Out-File -LiteralPath $log -Encoding utf8 -ErrorAction Stop
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$savedErrorActionPreference }
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'VFX_DEMO_CLOSED' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "VFX Demo failed (native exit $code): $log"}
    Write-Output "VFX Demo closed cleanly: $log"
} finally { Pop-Location }
