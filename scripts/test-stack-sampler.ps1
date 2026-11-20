#Requires -Version 7.4.1
[CmdletBinding()]
param([string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    New-Item -ItemType Directory -Force artifacts/reference,agentdir/logs | Out-Null
    & "$Jdk/bin/javac.exe" -encoding UTF-8 -d artifacts/reference tests/reference/ThreadStackSampler.java tests/reference/ThreadStackSamplerProbe.java
    if($LASTEXITCODE -ne 0){throw 'Stack sampler probe compilation failed'}
    & "$Jdk/bin/java.exe" -cp artifacts/reference ThreadStackSamplerProbe *> agentdir/logs/stack-sampler.log
    if($LASTEXITCODE -ne 0 -or (Get-Content agentdir/logs/stack-sampler.log -Raw) -notmatch 'THREAD_STACK_SAMPLER_PASS'){throw 'Stack sampler probe failed: agentdir/logs/stack-sampler.log'}
    Write-Output 'Stack sampler probe passed'
} finally { Pop-Location }
