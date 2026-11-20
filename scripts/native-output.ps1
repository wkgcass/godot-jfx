# Windows PowerShell wraps redirected native stderr in ErrorRecord objects.
# Preserve diagnostic lines and let the caller check the program's exit code.
function Invoke-NativeOutput {
    param([string]$Executable)
    $program = Get-Command -Name $Executable -CommandType Application -TotalCount 1 -ErrorAction Stop
    $ErrorActionPreference = 'Continue'
    & $program @args 2>&1 | ForEach-Object { $_.ToString() }
}
