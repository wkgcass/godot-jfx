[CmdletBinding()]
param(
    [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/godot-library'),
    [string]$Jdk = $env:JAVA_HOME,
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9.-]*$')][string]$Version = '28-godot.3'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$sdk = Join-Path $root 'jfx/build/sdk'
$bin = Join-Path $Destination 'bin'
$engine = Join-Path $root 'godot/bin/godot.windows.template_release.x86_64.library.dll'
foreach ($file in @($engine, "$Jdk/bin/jar.exe", "$sdk/bin/fxplugins.dll", "$sdk/bin/jfxmedia.dll")) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing build product: $file" }
}
New-Item -ItemType Directory -Force $bin | Out-Null
Copy-Item -Path "$sdk/bin/*.dll" -Destination $bin
Copy-Item -LiteralPath $engine -Destination (Join-Path $bin 'godot.dll')
Copy-Item -LiteralPath "$root/runtime/run-javafx.ps1" -Destination $Destination
Copy-Item -LiteralPath "$sdk/legal" -Destination $Destination -Recurse -Force
Copy-Item -LiteralPath "$root/godot/LICENSE.txt","$root/godot/COPYRIGHT.txt","$root/LICENSE" -Destination $Destination
& python "$PSScriptRoot/publish-godot-modules.py" $Destination $Version "$Jdk/bin/jar.exe"
if ($LASTEXITCODE -ne 0) { throw 'Maven module publication failed' }
[IO.File]::WriteAllText("$Destination/version.txt", $Version)
Write-Output "Staged Windows runtime and Maven repository in $Destination"
