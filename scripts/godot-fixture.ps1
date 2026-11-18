# Windows scene fixtures run inside the Java process using the published classifier.
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
    & $launch.Java @prefix
}

function Start-GodotFixture {
    param([string[]]$ArgumentList, [string]$WorkingDirectory, [string]$Log, [string]$ErrorLog)
    $launch = Get-GodotFixtureLaunch $ArgumentList $WorkingDirectory
    $quoted = foreach ($argument in $launch.Arguments) { '"' + $argument + '"' }
    Start-Process -FilePath $launch.Java -ArgumentList $quoted -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -RedirectStandardOutput $Log -RedirectStandardError $ErrorLog -PassThru
}
