#Requires -Version 7.4.1
# Keep native diagnostics in the log and let the caller check the exit code.
function Invoke-NativeOutput {
    param([string]$Executable)
    $program = Get-Command -Name $Executable -CommandType Application -TotalCount 1 -ErrorAction Stop
    $PSNativeCommandUseErrorActionPreference = $false
    & $program @args 2>&1 | ForEach-Object { $_.ToString() }
}

function Assert-GodotDriver {
    param([string]$Driver, [string]$Log)
    & python "$PSScriptRoot/godot_driver.py" --driver $Driver.ToLowerInvariant() $Log
    if ($LASTEXITCODE) { throw "Godot driver verification failed: $Log" }
}
