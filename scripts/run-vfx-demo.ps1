[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('mobile','gl_compatibility')][string]$Renderer='mobile',[ValidateSet('safe')][string]$RenderThread='safe',[switch]$Smoke,[switch]$NoGodotLogo,[switch]$DisableVsync,[ValidateRange(0,1000)][int]$MaxFps=0,[switch]$ExecutableHost)
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
    New-Item -ItemType Directory -Force artifacts/logs | Out-Null
    if ($ExecutableHost) {
        $program='./godot/bin/godot.windows.editor.x86_64.console.exe'
        $engineArgs=@('--path','tests/godot','res://vfx_demo.tscn','--rendering-method',$Renderer,'--render-thread',$RenderThread)
    } else {
        $jar='artifacts/vfx/libs/vfx-demo.jar'
        if (!(Test-Path -LiteralPath $jar -PathType Leaf)) { throw "Missing $jar. Run scripts/build-vfx.ps1 first." }
        $program=Join-Path $Jdk 'bin/java.exe'
        $engineArgs=@('-jar',$jar,'--renderer',$Renderer)
        if ($Smoke) { $engineArgs+='--smoke' }
        if ($NoGodotLogo) { $engineArgs+='--no-godot-logo' }
    }
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
} finally {foreach($key in $saved.Keys){if ($null -eq $saved[$key]) { Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }};Pop-Location}
