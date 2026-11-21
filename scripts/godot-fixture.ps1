#Requires -Version 7.4.1
# Windows scene fixtures run inside the Java process using the published classifier.
. "$PSScriptRoot/native-output.ps1"
# The calling script may redirect output before the fixture starts.
[void][IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot "../agentdir/logs"))
function Get-GodotJfxTestModulePath {
    $json = & python "$PSScriptRoot/maven_local.py" module-path --json
    if ($LASTEXITCODE) { throw 'Could not resolve the Maven Local test modules' }
    return (ConvertFrom-Json $json)
}

function Get-GodotFixtureLaunch {
    param([string[]]$EngineArguments, [string]$WorkingDirectory = (Get-Location).Path,
          [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12')
    $Driver = $Driver.ToLowerInvariant()
    $json = & python "$PSScriptRoot/godot-fixture.py" --print-command $WorkingDirectory --driver $Driver @EngineArguments
    if ($LASTEXITCODE) { throw 'Could not prepare the Java scene launcher' }
    $command = ConvertFrom-Json $json
    [pscustomobject]@{ Java = $command[0]; Arguments = $command[1..($command.Length - 1)] }
}

function Invoke-GodotFixture {
    [CmdletBinding(PositionalBinding=$false)]
    param([ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12',
          [Parameter(ValueFromRemainingArguments)][string[]]$EngineArguments)
    $launch = Get-GodotFixtureLaunch -Driver $Driver -EngineArguments $EngineArguments
    $prefix = $launch.Arguments
    Invoke-NativeOutput $launch.Java @prefix
}

function Start-GodotFixture {
    param([string[]]$ArgumentList, [string]$WorkingDirectory, [string]$Log, [string]$ErrorLog,
          [ValidateSet('d3d12','vulkan','opengl')][string]$Driver = 'd3d12')
    $launch = Get-GodotFixtureLaunch -Driver $Driver -EngineArguments $ArgumentList -WorkingDirectory $WorkingDirectory
    $quoted = foreach ($argument in $launch.Arguments) { '"' + $argument + '"' }
    Start-Process -FilePath $launch.Java -ArgumentList $quoted -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $Log -RedirectStandardError $ErrorLog -PassThru
}
