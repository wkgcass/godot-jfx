[CmdletBinding()]
param([string]$Jdk='D:\jdk-25.0.3+9')
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,artifacts/logs | Out-Null
    & "$Jdk/bin/javac.exe" -encoding UTF-8 -d artifacts/reference tests/reference/ThreadStackSampler.java tests/reference/ThreadStackSamplerProbe.java
    if($LASTEXITCODE -ne 0){throw 'Stack sampler probe compilation failed'}
    & "$Jdk/bin/java.exe" -cp artifacts/reference ThreadStackSamplerProbe *> artifacts/logs/stack-sampler.log
    if($LASTEXITCODE -ne 0 -or (Get-Content artifacts/logs/stack-sampler.log -Raw) -notmatch 'THREAD_STACK_SAMPLER_PASS'){throw 'Stack sampler probe failed: artifacts/logs/stack-sampler.log'}
    Write-Output 'Stack sampler probe passed'
} finally { Pop-Location }
