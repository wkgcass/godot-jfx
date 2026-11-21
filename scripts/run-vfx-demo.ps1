#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME,[ValidateSet('safe')][string]$RenderThread='safe',[switch]$Smoke,[switch]$NoGodotLogo,[switch]$DisableVsync,[ValidateRange(0,1000)][int]$MaxFps=0,[ValidateSet('d3d12','vulkan','opengl')][string]$Driver='d3d12')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/native-output.ps1"
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $Driver = $Driver.ToLowerInvariant()
    $log="agentdir/logs/vfx-demo-$Driver-$RenderThread.log"
    New-Item -ItemType Directory -Force agentdir/logs | Out-Null
    $jar='artifacts/vfx/libs/vfx-demo.jar'
    if (!(Test-Path -LiteralPath $jar -PathType Leaf)) { throw "Missing $jar. Run scripts/build-vfx.ps1 first." }
    $program=Join-Path $Jdk 'bin/java.exe'
    $engineArgs=@("-Djavafx.godot.driver=$Driver",'-jar',$jar)
    if ($Smoke) { $engineArgs+='--smoke' }
    if ($NoGodotLogo) { $engineArgs+='--no-godot-logo' }
    if($DisableVsync){$engineArgs+='--disable-vsync';if($MaxFps -le 0){$MaxFps=60}}
    if($MaxFps -gt 0){$engineArgs+=@('--max-fps',"$MaxFps")}
    Write-Output "Starting the original VFX Demo with Viewport + safe rendering. Close its window to exit. Log: $log"
    Invoke-NativeOutput $program @engineArgs | Out-File -LiteralPath $log -Encoding utf8
    $code=$LASTEXITCODE
    $output=Get-Content $log -Raw
    if($code -ne 0 -or $output -notmatch 'VFX_DEMO_CLOSED' -or $output -match '(?m)^(ERROR:|SCRIPT ERROR:|SHADER ERROR:|Exception)|uncaught:'){throw "VFX Demo failed (native exit $code): $log"}
    Assert-GodotDriver $Driver $log
    Write-Output "VFX Demo closed cleanly: $log"
} finally { Pop-Location }
