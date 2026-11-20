# Windows scene fixtures run inside the Java process using the published classifier.
. "$PSScriptRoot/native-output.ps1"
function Get-GodotJfxTestModulePath {
    $json = & python "$PSScriptRoot/maven_local.py" module-path --json
    if ($LASTEXITCODE) { throw 'Could not resolve the Maven Local test modules' }
    return (ConvertFrom-Json $json)
}

function Get-GodotFixtureLaunch {
    param([string[]]$EngineArguments, [string]$WorkingDirectory = (Get-Location).Path)
    $json = & python "$PSScriptRoot/godot-fixture.py" --print-command $WorkingDirectory @EngineArguments
    if ($LASTEXITCODE) { throw 'Could not prepare the Java scene launcher' }
    $command = ConvertFrom-Json $json
    [pscustomobject]@{ Java = $command[0]; Arguments = $command[1..($command.Length - 1)] }
}

function Invoke-GodotFixture {
    $launch = Get-GodotFixtureLaunch $args
    $prefix = $launch.Arguments
    Invoke-NativeOutput $launch.Java @prefix
}

function Start-GodotFixture {
    param([string[]]$ArgumentList, [string]$WorkingDirectory, [string]$Log, [string]$ErrorLog)
    $launch = Get-GodotFixtureLaunch $ArgumentList $WorkingDirectory
    $quoted = foreach ($argument in $launch.Arguments) { '"' + $argument + '"' }
    Start-Process -FilePath $launch.Java -ArgumentList $quoted -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $Log -RedirectStandardError $ErrorLog -PassThru
}
